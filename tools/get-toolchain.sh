#!/bin/sh
# AdaWebPack 24 (GNAT LLVM) into ./toolchain, the same public packages the
# spectrum-analyzer and symmetry-visualizations demos use.
# Once: sudo apt install rpm2cpio cpio lld curl
# GNAT 14 supplies libgnat-14.so (the compiler is written in Ada) and the
# string / numeric units the light wasm runtime does not ship.
set -e
cd "$(dirname "$0")/.."
mkdir -p toolchain
cd toolchain
F=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/40/Everything/x86_64/os/Packages
for U in \
  https://github.com/godunko/adawebpack/releases/download/24.0.0/adawebpack-24.0.0-git.fc40.x86_64.rpm \
  "$F/l/llvm16-libs-16.0.6-7.fc40.x86_64.rpm" \
  "$F/c/clang16-libs-16.0.6-5.fc40.x86_64.rpm"
do
  echo "Downloading $U"
  curl -fsSL "$U" | rpm2cpio | cpio -idm --quiet
done
mkdir -p lib
cp usr/lib64/llvm16/lib/libLLVM-16.so usr/lib64/llvm16/lib/libclang-cpp.so.16 lib/
if [ -e /usr/lib/x86_64-linux-gnu/libedit.so.2 ] && [ ! -e lib/libedit.so.0 ]; then
  ln -sf /usr/lib/x86_64-linux-gnu/libedit.so.2 lib/libedit.so.0
fi
if ! ldconfig -p 2>/dev/null | grep -q libgnat-14.so; then
  if ! command -v alr >/dev/null 2>&1; then
    echo "alr is not on PATH. Install Alire, then: alr toolchain --select gnat_native=14.2.1"
    exit 1
  fi
  alr -n toolchain --select gnat_native=14.2.1 >/dev/null
  so=$(find "$HOME/.local/share/alire/toolchains" -name 'libgnat-14.so' | head -1)
  if [ -z "$so" ]; then
    echo "libgnat-14.so was not found after selecting the GNAT 14 toolchain"
    exit 1
  fi
  cp "$so" lib/
fi
inc=$(find "$HOME/.local/share/alire/toolchains" -type d -path '*gnat_native_14*/adainclude' | head -1)
if [ -z "$inc" ]; then
  echo "GNAT 14 adainclude was not found. Set GNAT14_ADAINCLUDE when building."
else
  rm -rf adainclude
  cp -a "$inc" adainclude
fi
rm -rf usr/lib64
echo "Toolchain ready in $PWD"
