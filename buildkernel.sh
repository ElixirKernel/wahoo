#!/bin/bash

####################################################################
## This kernel build script will export proper paths to toolchain ##
## and correct ARCH for device. Modify these values to fit your   ##
##             environment and run it before building.            ##
####################################################################

BUILD_KERNEL_DIR=$(pwd)
BUILD_KERNEL_OUT=$BUILD_KERNEL_DIR/../wahoo_kernel_out
BUILD_KERNEL_OUT_DIR=$BUILD_KERNEL_OUT/KERNEL_OBJ
BOOT_DIR=/arch/arm64/boot
DTS_DIR=/arch/arm64/boot/dts/qcom
CONFIG_DIR=arch/arm64/configs

CLANG_TOOLCHAIN=~/Android/Toolchains/dragontc-8.0/bin/clang
BUILD_CROSS_COMPILE_ARCH64=~/Android/Toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
BUILD_CROSS_COMPILE_ARM32=~/Android/Toolchains/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
BUILD_JOB_NUMBER=`grep processor /proc/cpuinfo|wc -l`
KBUILD_COMPILER_STRING=$(${CLANG_TOOLCHAIN} --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

KERNEL_DEFCONFIG=elixir_wahoo_defconfig
KERNEL_IMG_NAME=Image.lz4-dtb
KERNEL_IMG=$BUILD_KERNEL_OUT/$KERNEL_IMG_NAME

# Bash Color
green='\033[01;32m'
red='\033[01;31m'
blue='\033[0;104m'
blink_red='\033[05;31m'
restore='\033[0m'

FUNCTION_GENERATE_DEFCONFIG()
{
	    echo -e "${blink_red}"
        echo "==================================="
        echo " START : FUNC GENERATE DEFCONFIG   "
        echo "==================================="
        echo "build config="$KERNEL_DEFCONFIG ""
        echo -e "${restore}"

	make -C $BUILD_KERNEL_DIR O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER ARCH=arm64 \
			CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 \
			$KERNEL_DEFCONFIG || exit -1

	cp $BUILD_KERNEL_OUT_DIR/.config $BUILD_KERNEL_DIR/$CONFIG_DIR/$KERNEL_DEFCONFIG

	echo -e "${red}"
	echo "==================================="
	echo "  END: FUNCTION GENERATE DEFCONFIG "
	echo "==================================="
	echo -e "${restore}"
}

FUNCTION_BUILD_KERNEL()
{
	echo -e "${blink_red}"
	echo "================================="
	echo "  START : FUNCTION_BUILD_KERNEL  "
	echo "================================="
	echo -e "${restore}"
	
    rm $KERNEL_IMG $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/Image
	rm -rf $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/dts

if [ "$USE_CCACHE" ]
then
	make -C $BUILD_KERNEL_DIR O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER ARCH=arm64 \
            CC="ccache $CLANG_TOOLCHAIN" \
            HOSTCC="ccache $CLANG_TOOLCHAIN" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=$BUILD_CROSS_COMPILE_ARM32 \
            CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 || exit -1

else
	make -C $BUILD_KERNEL_DIR O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER ARCH=arm64 \
            CC="$CLANG_TOOLCHAIN" \
            HOSTCC="$CLANG_TOOLCHAIN" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=$BUILD_CROSS_COMPILE_ARM32 \
            CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 || exit -1
fi

	cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/$KERNEL_IMG_NAME $KERNEL_IMG
	cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/Image.lz4 $BUILD_KERNEL_OUT
	cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/dtbo.img $BUILD_KERNEL_OUT
	cp $BUILD_KERNEL_OUT_DIR/$DTS_DIR/msm8998-v2.1-soc.dtb $BUILD_KERNEL_OUT
    
    echo -e "${blink_red}"
    echo "Made Kernel image: $KERNEL_IMG"
    echo -e "${restore}"
    echo -e "${red}"
	echo "================================="
	echo "  END   : FUNCTION_BUILD_KERNEL  "
	echo "================================="
	echo -e "${restore}"
}

(
    START_TIME=`date +%s`
    FUNCTION_GENERATE_DEFCONFIG
    FUNCTION_BUILD_KERNEL

    END_TIME=`date +%s`

    let "ELAPSED_TIME=$END_TIME-$START_TIME"
    echo "Total compile time is $ELAPSED_TIME seconds"
) 2>&1
