#!/bin/bash
# Install (or roll back) rebuilt audio modules: snd-soc-sdm845.ko (patches 0008+0016, 24-bit QUAT MI2S) and
# snd-soc-tfa98xx.ko (patch 0017, standard I2S alignment). Runtime rmmod/insmod of the sound card breaks SLIMbus
# capture (AFE port 0x4001 start -> DSP error 9), so every change takes effect only after a reboot.
#   sndcard_install.sh install <new.ko>...   back up each stock module once, install the new ones, disable the
#                                            16-bit TFA workaround (it would mismatch the 24-bit clock)
#   sndcard_install.sh rollback              restore every backed-up stock module and re-enable the workaround
set -eu
REL=$(uname -r)
BAKDIR=/var/lib/razer-sndcard
case "${1:-}" in
  install)
    shift
    for NEW in "$@"; do
      NAME=$(modinfo -F name "$NEW")
      DST=$(modinfo -n "$NAME")
      case "$DST" in /lib/modules/$REL/*) ;; *) echo "$NAME: not an on-disk module ($DST)"; exit 1 ;; esac
      [ "$(modinfo -F vermagic "$NEW")" = "$(modinfo -F vermagic "$DST")" ] || { echo "$NAME: vermagic mismatch"; exit 1; }
      sudo mkdir -p "$BAKDIR"
      BAK=$BAKDIR/$(basename "$DST").stock
      [ -f "$BAK" ] || sudo cp -p "$DST" "$BAK"
      echo "$DST" | sudo tee "$BAK.path" >/dev/null
      sudo install -m 0644 "$NEW" "$DST"
      echo "$NAME: installed $(sha256sum "$DST" | cut -c1-16) (stock backup $(sha256sum "$BAK" | cut -c1-16))"
    done
    sudo depmod "$REL"
    sudo systemctl disable razer-speaker-setup 2>&1 | tail -1
    echo "reboot to load"
    ;;
  rollback)
    for BAK in "$BAKDIR"/*.ko.stock; do
      if [ -f "$BAK.path" ]; then DST=$(cat "$BAK.path")
      else DST=/lib/modules/$REL/kernel/sound/soc/qcom/$(basename "$BAK" .stock); fi   # first-version backups
      sudo install -m 0644 "$BAK" "$DST"
      echo "restored stock $DST $(sha256sum "$DST" | cut -c1-16)"
    done
    sudo depmod "$REL"
    sudo systemctl enable razer-speaker-setup 2>&1 | tail -1
    echo "reboot to load"
    ;;
  *) echo "usage: $0 install <new.ko>... | rollback"; exit 2 ;;
esac
