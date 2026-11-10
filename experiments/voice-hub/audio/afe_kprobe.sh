#!/bin/bash
# kretprobes on the Q6 AFE calls made when the QUAT MI2S speaker path starts: return values tell whether the ADSP
# accepted the bit-clock and port-start requests (the machine driver ignores set_sysclk errors).
T=/sys/kernel/tracing
[ -d $T/events ] || T=/sys/kernel/debug/tracing
CARD=0
cleanup() {
  echo 0 | sudo tee $T/tracing_on >/dev/null
  echo 0 | sudo tee $T/events/kprobes/enable >/dev/null 2>&1
  echo | sudo tee $T/kprobe_events >/dev/null
}
trap cleanup EXIT
sudo grep -E " (q6afe_port_set_sysclk|q6afe_port_start|q6afe_port_stop|q6afe_set_lpass_clock|q6afe_i2s_port_prepare|q6afe_port_get_from_id)\b" /proc/kallsyms | head
probes=""
for f in q6afe_port_set_sysclk q6afe_port_start q6afe_set_lpass_clock q6afe_i2s_port_prepare; do
  if sudo grep -qE " $f\b" /proc/kallsyms; then
    echo "r:rz_$f $f ret=\$retval:s32" | sudo tee -a $T/kprobe_events >/dev/null && probes="$probes $f"
    echo "p:rz_in_$f $f a1=%x1:x64 a2=%x2:s32 a3=%x3:s32" | sudo tee -a $T/kprobe_events >/dev/null
  fi
done
echo "probes:$probes"
echo | sudo tee $T/trace >/dev/null
echo 1 | sudo tee $T/events/kprobes/enable >/dev/null
echo 1 | sudo tee $T/tracing_on >/dev/null
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
sudo aplay -q -D plughw:$CARD,0 /tmp/spk2/tone1000.wav
echo 0 | sudo tee $T/tracing_on >/dev/null
sudo cat $T/trace | grep -v "^#" | sed -E 's/^ +//' | cut -c1-200 | tail -40
