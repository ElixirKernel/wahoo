#!/bin/bash

####################################################################
## This kernel build script will export proper paths to toolchain ##
## and correct ARCH for device. Modify these values to fit your   ##
##             environment and run it before building.            ##
####################################################################

BUILD_KERNEL_DIR=$(pwd)
BUILD_KERNEL_OUT=$BUILD_KERNEL_DIR/../wahoo_kernel_out
BUILD_KERNEL_OUT_DIR=$BUILD_KERNEL_OUT/KERNEL_OBJ

CLANG_TOOLCHAIN=~/Android/Toolchains/dragontc-8.0/bin/clang
BUILD_CROSS_COMPILE_ARCH64=~/Android/Toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
BUILD_CROSS_COMPILE_ARM32=~/Android/Toolchains/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
BUILD_JOB_NUMBER=`grep processor /proc/cpuinfo|wc -l`

KBUILD_COMPILER_STRING=$(${CLANG_TOOLCHAIN} --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

KERNEL_DEFCONFIG=elixir_wahoo_defconfig

KERNEL_IMG_NAME=Image.lz4-dtb
KERNEL_IMG=$BUILD_KERNEL_OUT/$KERNEL_IMG_NAME

FUNCTION_GENERATE_DEFCONFIG()
{
	echo ""
        echo "==================================="
        echo " START : FUNC GENERATE DEFCONFIG   "
        echo "==================================="
        echo "build config="$KERNEL_DEFCONFIG ""
        echo ""

	make -C $BUILD_KERNEL_DIR O=$BUILD_KERNEL_OUT_DIR -j$BUILD_JOB_NUMBER ARCH=arm64 \
			CROSS_COMPILE=$BUILD_CROSS_COMPILE_ARCH64 \
			$KERNEL_DEFCONFIG || exit -1

	cp $BUILD_KERNEL_OUT_DIR/.config $BUILD_KERNEL_DIR/arch/arm64/configs/$KERNEL_DEFCONFIG

	echo ""
	echo "==================================="
	echo "  END: FUNCTION GENERATE DEFCONFIG "
	echo "==================================="
	echo ""
}

FUNCTION_BUILD_KERNEL()
{
	echo ""
	echo "================================="
	echo "  START : FUNCTION_BUILD_KERNEL  "
	echo "================================="
	echo ""
	rm $KERNEL_IMG $BUILD_KERNEL_OUT_DIR/arch/arm64/boot/Image
	rm -rf $BUILD_KERNEL_OUT_DIR/arch/arm64/boot/dts

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

	cp $BUILD_KERNEL_OUT_DIR/arch/arm64/boot/$KERNEL_IMG_NAME $KERNEL_IMG
	echo "Made Kernel image: $KERNEL_IMG"
	echo "================================="
	echo "  END   : FUNCTION_BUILD_KERNEL  "
	echo "================================="
	echo ""
}

(
    START_TIME=`date +%s`
    FUNCTION_GENERATE_DEFCONFIG
    FUNCTION_BUILD_KERNEL

    END_TIME=`date +%s`

    let "ELAPSED_TIME=$END_TIME-$START_TIME"
    echo "Total compile time is $ELAPSED_TIME seconds"
) 2>&1
