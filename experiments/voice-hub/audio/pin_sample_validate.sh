#!/bin/bash
# Validate the debugfs pin-level sampling method on a pin that is known to toggle: the TFA I2C bus
# (QUP5, GPIO85/86) while hammering it with reads. If SCL/SDA show both levels here, the method can see a
# function-muxed pin switching, and the constant-high QUAT MI2S result is meaningful.
sample() {
  sudo sh -c 'for i in $(seq 1 300); do grep -E "gpio8[56] " /sys/kernel/debug/gpio; done' | \
    awk '{n[$1]++; if ($0 ~ / high/) h[$1]++} END {for (g in n) printf "%s high %d/%d  ", g, h[g], n[g]; print ""}'
}
echo "i2c idle:  $(sample)"
( end=$((SECONDS + 6)); while [ $SECONDS -lt $end ]; do sudo i2cget -f -y 5 0x34 0x00 w >/dev/null 2>&1; done ) &
L=$!
sleep 0.3
echo "i2c busy:  $(sample)"
wait $L
