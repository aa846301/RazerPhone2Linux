#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

src=/tmp/ath10k_snoc-force-skip-host-cap.ko
release="$(uname -r)"
dst="/lib/modules/$release/kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko"
backup="$dst.before-force-skip-host-cap"
options=/etc/modprobe.d/ath10k-snoc-force-skip-host-cap.conf

test -f "$src"
test -f "$dst"

module_release="$(modinfo -F vermagic "$src" | awk '{print $1}')"
if [ "$module_release" != "$release" ]; then
	echo "release mismatch: phone=$release module=$module_release" >&2
	exit 2
fi

if ! modinfo "$src" | grep -q '^parm:.*force_skip_host_cap:'; then
	echo "diagnostic module parameter is missing" >&2
	exit 3
fi

if [ ! -e "$backup" ]; then
	cp -p "$dst" "$backup"
fi

install -m 0644 "$src" "$dst"
cat > "$options" <<'EOF'
options ath10k_snoc force_skip_host_cap=1
EOF

depmod -a "$release"
sync

echo "ATH10K_HOSTCAP_SKIP_INSTALLED"
sha256sum "$dst" "$backup"
cat "$options"
reboot
