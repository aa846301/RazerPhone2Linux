#!/bin/bash
# Read-only audit of DT / kernel state relevant to GPU+CPU inference performance.
be32() { od -An -tu4 --endian=big "$1" 2>/dev/null | xargs; }
GPU=/proc/device-tree/soc@0/gpu@5000000
echo "== GPU OPPs (Hz, peak kBps, supported-hw)"
for o in $GPU/opp-table/opp-*; do
  printf "%s peak=%s hw=%s\n" "$(basename $o)" "$(be32 $o/opp-peak-kBps)" "$(be32 $o/opp-supported-hw)"
done
echo "gpu speed-bin nvmem: $(ls $GPU | grep -i nvmem | xargs)"
echo "devfreq: $(cat /sys/class/devfreq/5000000.gpu/available_frequencies)  max=$(cat /sys/class/devfreq/5000000.gpu/max_freq)"
echo "== GMU / zap / msm messages"
sudo dmesg | grep -iE "msm|adreno|a6xx|gmu|zap|llcc|smmu|iommu" | grep -viE "dsi|dpu|mdss|panel" | head -30
echo "== LLCC"
ls /sys/bus/platform/drivers/ | grep -i llcc; ls /sys/bus/platform/drivers/qcom-llcc 2>/dev/null
ls /proc/device-tree/soc@0/ | grep -i -E "llcc|system-cache"
for n in /proc/device-tree/soc@0/system-cache-controller*; do echo "$n status=$(cat $n/status 2>/dev/null)"; done
echo "== CPU OPPs"
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "$(basename $p): max=$(cat $p/cpuinfo_max_freq) scaling_max=$(cat $p/scaling_max_freq) avail=$(cat $p/scaling_available_frequencies | wc -w) top=$(cat $p/scaling_available_frequencies | tr ' ' '\n' | sort -n | tail -1) boost=$(cat $p/scaling_boost_frequencies 2>/dev/null)"; done
echo "== CPU idle states"
for s in /sys/devices/system/cpu/cpu4/cpuidle/state*; do echo "$(cat $s/name) lat=$(cat $s/latency) disable=$(cat $s/disable)"; done
echo "== thermal trips that can cap GPU/CPU"
for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type); case $t in *gpu*|*cpu*) echo "$t temp=$(cat $z/temp) policy=$(cat $z/policy) trips=$(cat $z/trip_point_*_temp 2>/dev/null | xargs)";; esac; done
for c in /sys/class/thermal/cooling_device*; do t=$(cat $c/type); echo "$t cur=$(cat $c/cur_state)/$(cat $c/max_state)"; done | sort | uniq -c | head -20
echo "== deferred / missing devices"
sudo cat /sys/kernel/debug/devices_deferred 2>/dev/null
sudo dmesg | grep -E "sync_state\(\) pending" | head
echo "== IOMMU page sizes / GPU smmu"
sudo dmesg | grep -iE "arm-smmu|page sizes" | head -5
echo "== kernel config bits"
zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_(HZ|PREEMPT|QCOM_LLCC|DRM_MSM_GPU_STATE|ARM_SMMU_QCOM|DEVFREQ_GOV|QCOM_IPA|IPA|INTERCONNECT_QCOM_SDM845|TRANSPARENT_HUGEPAGE|ARM64_64K|ARM64_4K|CPU_FREQ_DEFAULT_GOV)" | head -30
echo "== msm module params"
for f in /sys/module/msm/parameters/*; do echo "$(basename $f)=$(cat $f 2>/dev/null)"; done 2>/dev/null | head -30
