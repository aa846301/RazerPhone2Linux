#!/bin/bash
F="/mnt/c/repo/razorphone2linux/android-fdt/android-base-00.dts"
echo "=== panel-name ==="
grep -n "panel-name\|nt36830\|novatek\|wqhd" "$F" | head -20
echo ""
echo "=== reset gpio ==="
grep -n "platform-reset\|reset-gpio\|gpio.*6\b" "$F" | head -20
echo ""
echo "=== vddio/lab/ibb ==="
grep -n "vddio\|\"lab\"\|\"ibb\"\|supply-name" "$F" | head -20
echo ""
echo "=== wcn3990 ==="
grep -n "wcn3990\|wifi.*address\|ath10k" "$F" | head -10
echo ""
echo "=== a630 / gpu firmware ==="
grep -n "a630\|zap-fw\|gpu.*fw\|firmware" "$F" | head -10
echo ""
echo "=== model ==="
grep -n "^	model" "$F" | head -5
