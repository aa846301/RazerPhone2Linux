# QRTR QMI Dump - capture + parse workflow (2026-06-10)

Goal: see the actual QMI conversation between the AP and the modem in the
window between `4080000.remoteproc is now up` and `fatal error without message`,
using `kernel-patches/0005-qrtr-qmi-dump.patch` + sdm845-mainline
`parse_qmi_kernel_dump`.

## What the patch does

Hooks mainline `net/qrtr/af_qrtr.c`:

- `qrtr_endpoint_post()` (RX, modem -> AP): dumps every `QRTR_TYPE_DATA` SDU and
  snoops `QRTR_TYPE_NEW_SERVER` to learn each service's `(node, port)`.
- `qrtr_node_enqueue()` (TX, AP -> modem): dumps every `QRTR_TYPE_DATA` SDU.

Each message is printed in the exact format `parse_qmi_kernel_dump` expects:

```
@QMI@<qmi svc_id="0x.." type="N" txn_id=".." msg_id="0x...." android_process="RX:node:port">
@QMI@xx xx xx xx ...
@QMI@</qmi>
```

`type`: 0=request, 2=response, 4=indication. `svc_id` comes from the snooped
NEW_SERVER table; if a port is seen before its NEW_SERVER, svc_id prints `0xff`
and libqmi will fall back to a raw dump (still readable). It is opt-in:

- kernel cmdline `qrtr.qmi_dump=1` (applied when qrtr.ko loads - best for the
  first MSS boot), or
- runtime `/sys/module/qrtr/parameters/qmi_dump` (set to 1 before bouncing MSS).

It does not touch MPSS memory, so it is safe for the normal boot path (unlike
the rejected pre-stop snapshot).

## 1. Build (applies the patch, rebuilds qrtr.ko)

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/build-all.sh kernel
```

`02-build-kernel.sh` applies `kernel-patches/0005-qrtr-qmi-dump.patch`
automatically. `CONFIG_QRTR=m`, so the change lands in `qrtr.ko`.

## 2. Get the new qrtr.ko + enable the dump

Option A - clean (captures the very first MSS boot): rebuild boot with the
cmdline param and reflash the changed module.

```powershell
# deploy the rebuilt module live, matching the running kernel.release
.\scripts\deploy-live-module.ps1 `
  -Module C:\repo\razorphone2linux\output\modules_install\lib\modules\<rel>\kernel\net\qrtr\qrtr.ko `
  -TargetRelativePath kernel\net\qrtr\qrtr.ko
```

Then add `qrtr.qmi_dump=1` to the boot cmdline (in `04-make-boot-image.sh`),
rebuild boot, flash, and reboot.

Option B - quick, no cmdline edit (controlled MSS bounce over SSH): deploy the
module + reboot as above, then on the phone:

```sh
echo 1 | sudo tee /sys/module/qrtr/parameters/qmi_dump

# find MSS remoteproc, disable recovery, then bounce it
for r in /sys/class/remoteproc/remoteproc*; do
  [ "$(cat $r/name 2>/dev/null)" = "4080000.remoteproc" ] && MSS=$r
done
echo disabled | sudo tee $MSS/recovery
echo stop  | sudo tee $MSS/state 2>/dev/null || true
echo start | sudo tee $MSS/state
# (or: sudo modprobe -r qcom_q6v5_mss; sudo modprobe qcom_q6v5_mss)
```

`qmi_dump` is a live bool; setting it before the bounce captures that MSS boot.

## 3. Capture + parse

On the phone:

```sh
dmesg -t | grep "@QMI@" | sed -e "s/@QMI@//g" > /tmp/razer_qmi_dump.xml
```

Build `parse_qmi_kernel_dump` (on the phone rootfs or in WSL):

```sh
sudo apt install -y meson ninja-build pkg-config libglib2.0-dev libqmi-glib-dev libxml2-dev
git clone https://gitlab.com/sdm845-mainline/qmi-parse-kernel-dump
cd qmi-parse-kernel-dump
meson setup build && meson compile -C build
build/parse_qmi_kernel_dump -f /tmp/razer_qmi_dump.xml
# optional: -t request -t response -t indication to filter
```

## What to look for

The modem only answers one `tms/pddump_disabled` servreg lookup before fatal, so
the interesting evidence is small and specific:

- the last servreg (PDR locator) request/response before fatal, and which
  domain/service it concerned;
- any QMI **indication** the modem emits right before dying (an error/SSR hint
  that never reaches SMEM item 421);
- whether the AP sends a QMI the modem rejects, or the modem requests a service
  the AP never answers.

Save the parsed output to `output/` and compare against a working SDM845
(OnePlus 6) capture if one becomes available.
