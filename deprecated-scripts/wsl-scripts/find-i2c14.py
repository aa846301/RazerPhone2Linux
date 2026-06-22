#!/usr/bin/env python3
import re

data = open('/home/dinochang/razorphone2linux/kernel/linux/arch/arm64/boot/dts/qcom/sdm845.dtsi').read()

print("=== All i2c nodes in mainline sdm845.dtsi ===")
for m in re.finditer(r'(\w+):\s+i2c@([0-9a-fA-F]+)', data):
    addr = int(m.group(2), 16)
    print(f"  label={m.group(1):<20} addr=0x{m.group(2)}  ({addr})")

print()
print("=== Search for 0xa98000 ===")
if 'a98000' in data.lower():
    idx = data.lower().index('a98000')
    print(data[max(0,idx-100):idx+100])
else:
    print("NOT FOUND in sdm845.dtsi!")
    # Maybe it's in a separate file
    import glob, os
    for f in glob.glob('/home/dinochang/razorphone2linux/kernel/linux/arch/arm64/boot/dts/qcom/*.dtsi'):
        try:
            content = open(f).read()
            if 'a98000' in content.lower():
                print(f"Found in: {os.path.basename(f)}")
                idx = content.lower().index('a98000')
                print(content[max(0,idx-150):idx+150])
                print("---")
        except:
            pass
