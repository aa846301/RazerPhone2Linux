# QRTR QMI Dump — 步驟（中文）

目的：抓出 modem fatal 前 AP↔modem 的 QMI 對話。
開關：`qrtr.qmi_dump=1`（開機參數）或 `/sys/module/qrtr/parameters/qmi_dump`。

---

## 0. 若 build 報 patch 錯，先還原 kernel 樹（WSL）

```bash
cd ~/razorphone2linux/kernel/linux
git checkout -- .
```

## 1. 編譯（WSL）

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/build-all.sh kernel
```

## 2. 確認模組產生並複製到 Windows（WSL）

```bash
find ~/razorphone2linux/output -name qrtr.ko
cp ~/razorphone2linux/output/modules_install/lib/modules/6.16.0-rc2-sdm845-ged6098a37a4c-dirty/kernel/net/qrtr/qrtr.ko /mnt/c/repo/razorphone2linux/output/live-modules/qrtr.ko
```

## 3. 部署到手機並重開機（PowerShell）

```powershell
.\scripts\deploy-live-module.ps1 -Module C:\repo\razorphone2linux\output\live-modules\qrtr.ko -TargetRelativePath kernel\net\qrtr\qrtr.ko -Reboot
```

## 4. 開 dump + 重啟 MSS（手機 SSH）

```sh
echo 1 | sudo tee /sys/module/qrtr/parameters/qmi_dump
for r in /sys/class/remoteproc/remoteproc*; do
  [ "$(cat $r/name 2>/dev/null)" = "4080000.remoteproc" ] && MSS=$r
done
echo disabled | sudo tee $MSS/recovery
echo stop  | sudo tee $MSS/state 2>/dev/null || true
echo start | sudo tee $MSS/state
```

## 5. 抓 log（手機 SSH）

```sh
dmesg -t | grep "@QMI@" | sed -e "s/@QMI@//g" > /tmp/razer_qmi_dump.xml
```

## 6. 解析（手機或 WSL）

```sh
sudo apt install -y meson ninja-build pkg-config libglib2.0-dev libqmi-glib-dev libxml2-dev
git clone https://gitlab.com/sdm845-mainline/qmi-parse-kernel-dump
cd qmi-parse-kernel-dump && meson setup build && meson compile -C build
build/parse_qmi_kernel_dump -f /tmp/razer_qmi_dump.xml
```

把第 6 步的輸出貼回來即可。
