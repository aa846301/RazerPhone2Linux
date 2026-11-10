#!/bin/bash
# Dump TFA9912 interface/status/gain registers while a tone plays (left amp 0x34 and right 0x35).
rd() { v=$(sudo i2cget -f -y 5 $1 $2 w); printf "%02x%02x" $((v & 0xff)) $((v >> 8)); }
dump() { for a in 0x34 0x35; do printf "%s:" $a; for r in 00 01 02 10 13 14 20 21 22 23 24 25 26 27 50 51 52 53; do printf " %s=%s" $r "$(rd $a 0x$r)"; done; echo; done; }
echo "idle:"; dump
sudo aplay -q -D plughw:0,0 /tmp/spk2/tone1000.wav & p=$!
sleep 1.2; echo "playing:"; dump
wait $p
