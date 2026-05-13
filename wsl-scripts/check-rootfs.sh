#!/bin/bash
echo "=== rootfs-sparse.img ==="
ls -lh ~/razorphone2linux/output/rootfs-sparse.img 2>/dev/null || echo NOT_FOUND

python3 -c "
import os
path = os.path.expanduser('~/razorphone2linux/output/rootfs-sparse.img')
if not os.path.exists(path):
    print('FILE NOT FOUND')
    exit()
with open(path,'rb') as f:
    d = f.read(4)
if d == b'\xed\x26\xff\x3a':
    print('FORMAT: Android Sparse Image -> fastboot sends only non-zero chunks (FAST)')
else:
    print(f'FORMAT: raw/other ({d.hex()}) -> fastboot sends ALL bytes (SLOW)')
"

echo ""
echo "=== rootfs directory ==="
ls ~/razorphone2linux/rootfs/ 2>/dev/null | head -10 || echo "No rootfs dir - was it already packed into img?"

echo ""
echo "=== Kernel modules in rootfs ==="
ls ~/razorphone2linux/rootfs/lib/modules/ 2>/dev/null || echo "NOT in rootfs/"

echo ""
echo "=== Kernel modules in output/modules_install ==="
ls ~/razorphone2linux/output/modules_install/lib/modules/ 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== systemd serial-getty in rootfs ==="
ls ~/razorphone2linux/rootfs/etc/systemd/system/ 2>/dev/null || echo "No etc/systemd/system"
ls ~/razorphone2linux/rootfs/etc/systemd/system/getty.target.wants/ 2>/dev/null || echo "No getty.target.wants"
ls ~/razorphone2linux/rootfs/lib/systemd/system/serial-getty@.service 2>/dev/null || echo "No serial-getty@.service"

echo ""
echo "=== SSH in rootfs ==="
ls ~/razorphone2linux/rootfs/etc/ssh/sshd_config 2>/dev/null || echo "No sshd_config"
ls ~/razorphone2linux/rootfs/lib/systemd/system/ssh.service 2>/dev/null && echo "ssh.service exists" || echo "No ssh.service"
ls ~/razorphone2linux/rootfs/etc/systemd/system/multi-user.target.wants/ssh.service 2>/dev/null && echo "SSH autostart: YES" || echo "SSH autostart: NOT configured"
