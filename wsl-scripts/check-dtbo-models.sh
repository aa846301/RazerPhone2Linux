#!/bin/bash
for f in /root/razorphone2linux/android-fdt/*.dts; do
    name=$(basename "$f")
    echo "--- $name ---"
    grep -m4 'model\|compatible\|razer\|aura\|rc2\|razor' "$f" 2>/dev/null | head -5
    echo ""
done
