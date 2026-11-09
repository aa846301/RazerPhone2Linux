#!/bin/bash
# After a kernel change: logits KL vs CPU (GPU fp16 and fp32) for both models, then tuned-CPU decode speed.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn/MNN-3.6.2/build
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
echo "== accuracy (KL vs CPU, lower is better)"
for M in Qwen3.5-0.8B-text Qwen3-1.7B-MNN; do
  D=$HOME/voice/models/mnn/$M
  for cfg in config-opencl.json config-opencl-high.json; do
    rm -f tmp/mnn_cachefile.bin
    r=$(timeout 1500 ./llm_logits_diff $D/config-cpu.json $D/$cfg /tmp/lp2.txt 48 2>&1 | grep -oE 'disagreements=[0-9]+|mean KL\(A\|\|B\)=[0-9.]+' | tr '\n' ' ')
    echo "$M lp2 $cfg: $r"
  done
done
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
echo "== speed (tuned CPU power settings)"
for m in Qwen3.5-0.8B-MNN Qwen3-1.7B-MNN; do
  for c in 2 1; do
    rm -f tmp/mnn_cachefile.bin
    timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c $c -p 0 -n 8 -rep 1 -load false > /dev/null 2>&1
    r=$(timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c $c -p 256 -n 32 -rep 2 -load false 2>&1 | grep -E 'pp256|tg32' | awk -F'|' '{gsub(/ /,"",$7); gsub(/ /,"",$8); printf "%s=%s ", $7, $8}')
    echo "$m GPU precision=$c: $r (temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1))"
    sleep 10
  done
done
