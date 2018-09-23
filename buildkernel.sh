#!/bin/bash

####################################################################
## This kernel build script will export proper paths to toolchain ##
## and correct ARCH for device. Modify these values to fit your   ##
##             environment and run it before building.            ##
####################################################################

KERNEL_VER=V1.6

BUILD_KERNEL_DIR=$(pwd)
BUILD_KERNEL_OUT=$BUILD_KERNEL_DIR/../wahoo_kernel_out
BUILD_KERNEL_OUT_DIR=$BUILD_KERNEL_OUT/KERNEL_OBJ
BOOT_DIR=arch/arm64/boot
DTS_DIR=arch/arm64/boot/dts/qcom
CONFIG_DIR=arch/arm64/configs
AK2_DIR=$BUILD_KERNEL_DIR/../AnyKernel2

export CLANG_CROSS_COMPILE=~/Android/Toolchains/clang-7.0/bin/clang
export BUILD_CROSS_COMPILE_ARCH64=~/Android/Toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
export BUILD_CROSS_COMPILE_ARM32=~/Android/Toolchains/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
export KBUILD_COMPILER_STRING=$(${CLANG_CROSS_COMPILE} --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
export BUILD_JOB_NUMBER=`grep processor /proc/cpuinfo|wc -l`

KERNEL_DEFCONFIG=elixir_wahoo_defconfig
KERNEL_IMG_NAME=Image.lz4-dtb
KERNEL_IMG=$BUILD_KERNEL_OUT/$KERNEL_IMG_NAME

# Bash Colors
green='\033[1;92m'
red='\033[1;91m'
blue='\033[0;94m'
yellow='\033[1;93m'
cyan='\033[1;96m'
white='\033[1;97m'
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
	         CC=$CLANG_CROSS_COMPILE $KERNEL_DEFCONFIG || exit -1

	cp $BUILD_KERNEL_OUT_DIR/.config $BUILD_KERNEL_DIR/$CONFIG_DIR/$KERNEL_DEFCONFIG

	echo -e "${yellow}"
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
            CC="ccache $CLANG_CROSS_COMPILE" \
            HOSTCC="ccache $CLANG_CROSS_COMPILE" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=$BUILD_CROSS_COMPILE_ARM32 \
            CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 || exit -1

else
	make -C $BUILD_KERNEL_DIR O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER ARCH=arm64 \
            CC="$CLANG_CROSS_COMPILE" \
            HOSTCC="$CLANG_CROSS_COMPILE" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=$BUILD_CROSS_COMPILE_ARM32 \
            CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 || exit -1
fi

    echo -e "${yellow}"
    echo "Made Kernel image: $KERNEL_IMG"
    echo -e "${restore}"
    echo -e "${red}"
    echo "================================="
    echo "  END   : FUNCTION_BUILD_KERNEL  "
    echo "================================="
    echo -e "${restore}"
}

FUNCTION_MAKE_ZIP()
{
        echo -e "${blink_red}"
        echo "============================"
        echo " START : FUNCTION MAKE ZIPS "
        echo "============================"
        echo -e "${restore}"
        echo -e "${cyan}"
        echo "make boot zip = "Elixir-Wahoo-Kernel-$KERNEL_VER-`date +[%m-%d-%y-%H%M%S]` ""
        echo -e "${restore}"

    cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/$KERNEL_IMG_NAME $KERNEL_IMG
    cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/Image.lz4 $AK2_DIR/kernel
    cp $BUILD_KERNEL_OUT_DIR/$BOOT_DIR/dtbo.img $AK2_DIR
    cp $BUILD_KERNEL_OUT_DIR/$DTS_DIR/msm8998-v2.1-soc.dtb $AK2_DIR/dtbs

    cd $AK2_DIR
    zip -r9 Elixir-wahoo-Kernel-$KERNEL_VER-`date +[%m-%d-%y-%H%M%S]`.zip * -x .git README.md *placeholder
    mv Elixir-wahoo-Kernel-*.zip $BUILD_KERNEL_OUT

	echo -e "${yellow}"
	echo "=========================="
	echo "  END: FUNCTION MAKE ZIPS "
	echo "=========================="
	echo -e "${restore}"
}

(
    START_TIME=`date +%s`
    FUNCTION_GENERATE_DEFCONFIG
    FUNCTION_BUILD_KERNEL
    FUNCTION_MAKE_ZIP

    END_TIME=`date +%s`

    let "ELAPSED_TIME=$END_TIME-$START_TIME"
    echo -e "${cyan}"
    echo "Total compile time is $ELAPSED_TIME seconds"
    echo -e "${restore}"
) 2>&1
