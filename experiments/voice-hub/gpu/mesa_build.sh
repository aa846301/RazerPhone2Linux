#!/bin/bash
# Build Mesa 26.2.6 (freedreno gallium + rusticl + turnip) into /opt/mesa-26.2.6.
# The system Mesa is not touched; use it via OCL_ICD_VENDORS / VK_ICD_FILENAMES.
set -e
exec > /tmp/mesa-build.log 2>&1
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  rustc-1.89 cargo-1.89 bindgen-0.71 ninja-build pkg-config bison flex \
  llvm-18-dev libclang-18-dev clang-18 libclc-18-dev llvm-spirv-18 libllvmspirvlib-18-dev \
  spirv-tools glslang-tools python3-mako python3-yaml python3-ply python3-pycparser python3-venv \
  libdrm-dev libelf-dev libexpat1-dev libzstd-dev zlib1g-dev libudev-dev
mkdir -p ~/voice/mesa-tools
[ -x ~/voice/mesa-tools/venv/bin/meson ] || { python3 -m venv ~/voice/mesa-tools/venv; ~/voice/mesa-tools/venv/bin/pip install -q 'meson>=1.4,<2' mako pyyaml ply pycparser packaging; }
mkdir -p ~/voice/mesa-tools/bin
ln -sf /usr/bin/rustc-1.89 ~/voice/mesa-tools/bin/rustc
ln -sf /usr/bin/cargo-1.89 ~/voice/mesa-tools/bin/cargo
for b in /usr/bin/bindgen-0.71 /usr/lib/rust-bindgen-0.71/bin/bindgen; do [ -x $b ] && ln -sf $b ~/voice/mesa-tools/bin/bindgen && break; done
export PATH=~/voice/mesa-tools/bin:~/voice/mesa-tools/venv/bin:/usr/lib/llvm-18/bin:$PATH
rustc --version; bindgen --version; meson --version; llvm-config --version
cd ~/voice/mesa-26.2.6
rm -rf build
meson setup build --prefix=/opt/mesa-26.2.6 --buildtype=release \
  -Dgallium-drivers=freedreno -Dvulkan-drivers=freedreno -Dgallium-rusticl=true \
  -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
  -Dllvm=enabled -Dshared-llvm=enabled -Dvideo-codecs= -Dtools= -Dvalgrind=disabled -Dlibunwind=disabled \
  -Dfreedreno-kmds=msm -Dbuild-tests=false
nice ninja -C build -j6
sudo ninja -C build install
echo BUILD_OK
