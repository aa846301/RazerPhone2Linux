#!/bin/bash
# Build mesa-libclc (llvm_21 branch, clang-20) into /opt/mesa-libclc, then rebuild Mesa 26.2.6 against it.
set -e
exec > /tmp/libclc-build.log 2>&1
export PATH=~/voice/mesa-tools/bin:~/voice/mesa-tools/venv/bin:/usr/lib/llvm-20/bin:$PATH
cd ~/voice/mesa-libclc-llvm21
rm -rf build
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/mesa-libclc \
      -DCMAKE_C_COMPILER=clang-20 -DLLVM_SPIRV=/usr/bin/llvm-spirv-20 -DLLVM_CONFIG=/usr/lib/llvm-20/bin/llvm-config
nice cmake --build build -j6
sudo cmake --install build
find /opt/mesa-libclc -type f | head
cat /opt/mesa-libclc/share/pkgconfig/mesa-libclc.pc
export PKG_CONFIG_PATH=/opt/mesa-libclc/share/pkgconfig
cd ~/voice/mesa-26.2.6
meson configure build -Dmesa-clc-bundle-headers=auto 2>/dev/null || true
meson setup --reconfigure build
grep -iE 'mesa-libclc' build/meson-logs/meson-log.txt | tail -n 3
nice ninja -C build -j6
sudo ninja -C build install
echo LIBCLC_MESA_OK
