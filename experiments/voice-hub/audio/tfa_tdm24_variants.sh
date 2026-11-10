#!/bin/bash
# With the 24-bit snd-soc-sdm845 module: the amps lock (MANSTATE 9 = operating) but the speakers are ~silent.
# Hypothesis: sample placement inside the 32-bit slot. Rewrite TDM reg 0x21 (bit15 TDMADJ, bit14 TDMDEL) and 0x22
# (TDMSSIZE [6:2]) at idle on both amps, then run the DMIC loopback for each variant. Restores factory values at the end.
set -u
wr() { v=$((16#$3)); sudo i2cset -f -y 5 $1 $2 $(( ((v & 0xff) << 8) | (v >> 8) )) w; }  # registers are big-endian
setv() { for a in 0x34 0x35; do wr $a 0x21 $1; wr $a 0x22 $2; done; }
for pair in c1f1:545c 41f1:545c 81f1:545c 01f1:545c c1f1:543c 41f1:543c; do
  setv ${pair%:*} ${pair#*:}
  echo "== 0x21=${pair%:*} 0x22=${pair#*:}"
  bash ~/voice/audio/speaker_loopback2.sh -12 1000 2>&1 | grep -E 'Hz:|ERROR'
done
setv c1f1 545c
