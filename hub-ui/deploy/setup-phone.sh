#!/bin/bash
# One-time phone setup for the Slint hub UI: sway kiosk stack, CJK fonts, build deps, rustup toolchain.
set -e
exec > /tmp/hub-ui-setup.log 2>&1
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  sway swaybg seatd wlr-randr wev libinput-tools fonts-noto-cjk fonts-noto-color-emoji \
  build-essential pkg-config cmake libfontconfig-dev libfreetype-dev libxkbcommon-dev libinput-dev \
  libudev-dev libgbm-dev libdrm-dev libwayland-dev libegl-dev libgles-dev libseat-dev
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain stable
fi
"$HOME/.cargo/bin/rustc" --version
"$HOME/.cargo/bin/cargo" --version
echo "setup exit=0"
