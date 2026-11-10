#!/bin/bash
# Phone: link an MLC model lib .tar (objects cross-compiled on the PC) into a shared library next to it.
# Usage: phone_link.sh <model_dir> [device]
d=$1; dev=${2:-opencl}
cd "$d" || exit 1
rm -rf "objs-$dev" && mkdir "objs-$dev" && tar -xf "lib-$dev.tar" -C "objs-$dev" && \
  g++ -shared -fPIC -o "lib-$dev.so" "objs-$dev"/*.o && ls -la "lib-$dev.so"
