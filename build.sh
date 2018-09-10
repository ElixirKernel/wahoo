#!/bin/bash

#############################################################
## This build script will export proper paths to toolchain ##
## and correct ARCH for device. Modify these values to fit ##
## your environment and run it before building.            ##
#############################################################

make O=out clean && make mrproper
make O=out ARCH=arm64 elixir_wahoo_defconfig

make -j$(nproc --all) O=out \
                      ARCH=arm64 \
                      CC=~/Android/Toolchains/clang-7.0/bin/clang \
                      CLANG_TRIPLE=aarch64-linux-gnu- \
                      CROSS_COMPILE_ARM32=~/Android/Toolchains/arm-linux-androideabi-4.9/bin/arm-linux-androideabi- \
                      CROSS_COMPILE=~/Android/Toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
