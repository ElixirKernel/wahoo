#!/bin/bash

####################################################################
## This kernel build script will export proper paths to toolchain ##
## and correct ARCH for device. Modify these values to fit your   ##
##             environment and run it before building.            ##
####################################################################

#Clang switch (true or false), default GCC
CLANG_CROSSCOMPILE=false

BUILD_KERNEL_DIR=$(readlink -f .);
BUILD_KERNEL_OUT="${BUILD_KERNEL_DIR}/../wahoo_kernel_out"
BUILD_KERNEL_OUT_DIR="${BUILD_KERNEL_OUT}/KERNEL_OBJ"
BOOT_DIR="arch/arm64/boot"
DTS_DIR="arch/arm64/boot/dts/qcom"
CONFIG_DIR="arch/arm64/configs"
AK2_DIR="${BUILD_KERNEL_DIR}/../AnyKernel2"

if [[ "${CLANG_CROSSCOMPILE}" == "true" ]]; then
export PATH=~/Android/Toolchains/dragontc-9.0/bin:${PATH}
export CLANG_CROSS_COMPILE="clang"
export KBUILD_COMPILER_STRING=$(${CLANG_CROSS_COMPILE} --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
export PATH=~/Android/Toolchains/aarch64-linux-gnu-8.2/bin:${PATH}
export BUILD_CROSS_COMPILE_ARCH64="aarch64-linux-gnu-"
export PATH=~/Android/Toolchains/arm-linux-androideabi-4.9/bin:${PATH}
export BUILD_CROSS_COMPILE_ARM32="arm-linux-androideabi-"
else
export PATH=~/Android/Toolchains/aarch64-linux-gnu-8.2/bin:${PATH}
export BUILD_CROSS_COMPILE_ARCH64="aarch64-linux-gnu-"
export PATH=~/Android/Toolchains/arm-linux-androideabi-4.9/bin:${PATH}
export BUILD_CROSS_COMPILE_ARM32="arm-linux-androideabi-"
fi
export BUILD_JOB_NUMBER=$(grep processor /proc/cpuinfo|wc -l)

KERNEL_DEFCONFIG="elixir_wahoo_defconfig"
KERNEL_IMG_NAME="Image.lz4-dtb"
KERNEL_IMG="${BUILD_KERNEL_OUT}/${KERNEL_IMG_NAME}"

# Bash Colors
red='\033[01;31m'
yellow='\033[1;93m'
cyan='\033[1;96m'
restore='\033[0m'

# check if "CCACHE" is installed
if [[ ! -e /usr/bin/ccache ]]; then
   echo "You must install 'ccache' to continue";
   sudo apt-get install ccache;
fi;

FUNCTION_RESET_GIT_BRANCH()
{
       echo -e "${red}"
       echo "==================================="
       echo " START : FUNCTION RESET GIT BRANCH "
       echo "==================================="
       echo -e "${restore}"

parse_git_branch() {
       git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e "s/* \(.*\)/\1/";
       }
       BRANCH=$(parse_git_branch);

	while true; do
	    echo -e "${yellow}"
	    read -rp "Reset current local branch to gitHub repo? (y/n)" yn;
	    echo -e "${restore}"
	    case $yn in
	y|Y )
	    git reset --hard origin/"${BRANCH}" && git clean -fd;
	    echo -e "${yellow}"
	    echo "Local branch reset to ${BRANCH}";
	    echo -e "${restore}"
	    break;
	    ;;
	n|N )
	    echo -e "${yellow}" "Local branch not reset""${restore}";
	    break;
	    ;;
	  * )
	    echo -e "${yellow}" "Please answer yes or no""${restore}";
	    ;;
	    esac;
	 done;

	  echo -e "${red}"
	  echo "==================================="
	  echo "  END: FUNCTION RESET GIT BRANCH   "
	  echo "==================================="
	  echo -e "${restore}"
}

FUNCTION_CLEAN()
{
       echo -e "${red}"
       echo "==================================="
       echo " START : FUNCTION CLEAN            "
       echo "==================================="
       echo -e "${restore}"

    # clean kernel source code
	while true; do
		echo -e "${yellow}";
		read -rp "Make clean source? (y/n)" yn;
		echo -e "${restore}"
		case $yn in
	y|Y )
	    make O="${BUILD_KERNEL_OUT_DIR}" clean;
	    make O="${BUILD_KERNEL_OUT_DIR}" distclean;
	    make O="${BUILD_KERNEL_OUT_DIR}" mrproper;
	    rm -rf "${KERNEL_IMG}" "${BUILD_KERNEL_OUT_DIR}/${BOOT_DIR}/Image"
	    rm -rf "${BUILD_KERNEL_OUT_DIR}/${BOOT_DIR}/dts"
	    rm -rf "${BUILD_KERNEL_DIR}/build.log"
	    echo -e "${yellow}" "Source cleaned""${restore}";
	    break;
	    ;;
	n|N )
	    echo -e "${yellow}" "Source not cleaned""${restore}";
	    break;
	    ;;
	  * )
	    echo -e "${yellow}" "Please answer yes or no""${restore}";
	    ;;
	   esac;
    done;
    # clear ccache & stat
	while true; do
	    echo -e "${yellow}";
	    read -rp "Clear ccache but keeping the config file? (y/n)" yn;
	    echo -e "${restore}"
	    case $yn in
	y|Y )
	    ccache -C -z;
	    break;
	    ;;
	n|N )
	    echo -e "${yellow}" "ccache not cleared""${restore}";
	    break;
	    ;;
	* )
	    echo -e "${yellow}" "Please answer yes or no""${restore}";
	    ;;
	 esac;
   done;
   echo -e "${red}"
   echo "==================================="
   echo "  END: FUNCTION CLEAN"             
   echo "==================================="
   echo -e "${restore}"
}

FUNCTION_GENERATE_DEFCONFIG()
{
        echo -e "${red}"
        echo "======================================="
        echo " START : FUNCTION GENERATE DEFCONFIG   "
        echo "======================================="
        echo -e "${restore}"
        echo -e "${cyan}"
        echo "build config" ="${KERNEL_DEFCONFIG}"
        echo -e "${restore}"

if [[ -n "${CLANG_CROSS_COMPILE}" ]]
then
	make -C "${BUILD_KERNEL_DIR}" O="${BUILD_KERNEL_OUT_DIR}" -j"${BUILD_JOB_NUMBER}" ARCH=arm64 \
	         CC="${CLANG_CROSS_COMPILE}" "${KERNEL_DEFCONFIG}" || exit -1
else
	make -C "${BUILD_KERNEL_DIR}" O="${BUILD_KERNEL_OUT_DIR}" -j"${BUILD_JOB_NUMBER}" ARCH=arm64 \
	         CROSS_COMPILE="${BUILD_CROSS_COMPILE_ARCH64}" "${KERNEL_DEFCONFIG}" || exit -1
fi
	cp "${BUILD_KERNEL_OUT_DIR}"/.config "${BUILD_KERNEL_DIR}/${CONFIG_DIR}/${KERNEL_DEFCONFIG}"

	echo -e "${red}"
	echo "==================================="
	echo "  END: FUNCTION GENERATE DEFCONFIG "
	echo "==================================="
	echo -e "${restore}"
}

FUNCTION_BUILD_KERNEL()
{
	echo -e "${red}"
	echo "================================="
	echo "  START : FUNCTION_BUILD_KERNEL  "
	echo "================================="
	echo -e "${restore}"

if [[ -n "${CLANG_CROSS_COMPILE}" ]]
then
	make -C "${BUILD_KERNEL_DIR}" O="${BUILD_KERNEL_OUT_DIR}" -j"${BUILD_JOB_NUMBER}" ARCH=arm64 \
            CC="ccache ${CLANG_CROSS_COMPILE}" \
            HOSTCC="ccache ${CLANG_CROSS_COMPILE}" \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32="${BUILD_CROSS_COMPILE_ARM32}" \
            CROSS_COMPILE="${BUILD_CROSS_COMPILE_ARCH64}" || exit -1

else
	make -C "${BUILD_KERNEL_DIR}" O="${BUILD_KERNEL_OUT_DIR}" -j"${BUILD_JOB_NUMBER}" ARCH=arm64 \
            CROSS_COMPILE_ARM32="${BUILD_CROSS_COMPILE_ARM32}" \
            CROSS_COMPILE="${BUILD_CROSS_COMPILE_ARCH64}" \
            CC="ccache "${BUILD_CROSS_COMPILE_ARCH64}"gcc" \
            CPP="ccache "${BUILD_CROSS_COMPILE_ARCH64}"gcc -E" || exit -1
fi

    echo -e "${yellow}"
    echo "Made Kernel image: ${KERNEL_IMG}"
    echo -e "${restore}"
    echo -e "${red}"
    echo "================================="
    echo "  END   : FUNCTION_BUILD_KERNEL  "
    echo "================================="
    echo -e "${restore}"
}

FUNCTION_MAKE_ZIP()
{
        echo -e "${red}"
        echo "============================"
        echo " START : FUNCTION MAKE ZIPS "
        echo "============================"
        echo -e "${restore}"

if [[ -s ~/KERNELver ]]; then
        echo -e "${red}" make boot zip = "Wahoo-$(cat ~/KERNELver)-$(date +[%m-%d-%y-%H%M%S])""${restore}"
else
        echo -e "${red}" make boot zip = "Wahoo-$(grep 'ElixirKernel-*v' "${BUILD_KERNEL_OUT_DIR}"/.config | sed 's/.*".//g' | sed 's/-S.*//g')-$(date +[%m-%d-%y-%H%M%S])""${restore}"
fi;
# check if "AnyKernel2" is there
if [[ ! -e /"${AK2_DIR}" ]]; then
   echo "You must add 'AnyKernel2' to continue";
   git clone https://github.com/CMRemix/AnyKernel2 -b wahoo;
   mv AnyKernel2 ..;
fi;
    cp "${BUILD_KERNEL_OUT_DIR}/${BOOT_DIR}/${KERNEL_IMG_NAME}" "${KERNEL_IMG}"
    cp "${BUILD_KERNEL_OUT_DIR}/${BOOT_DIR}/Image.lz4" "${AK2_DIR}/kernel"
    cp "${BUILD_KERNEL_OUT_DIR}/${BOOT_DIR}/dtbo.img" "${AK2_DIR}"
    cp "${BUILD_KERNEL_OUT_DIR}/${DTS_DIR}/msm8998-v2.1-soc.dtb" "${AK2_DIR}/dtbs"

if [[ -s ~/KERNELver ]]; then
    export KERNEL_VER=$(cat ~/KERNELver)
else
    export KERNEL_VER="$(grep 'ElixirKernel-*v' "${BUILD_KERNEL_OUT_DIR}"/.config | sed 's/.*".//g' | sed 's/-S.*//g')"
fi
    cd "${AK2_DIR}" || exit
    zip -r9 Wahoo-"${KERNEL_VER}"-$(date +[%m-%d-%y-%H%M%S]).zip * -x .git README.md *placeholder
    mv Wahoo-*.zip "${BUILD_KERNEL_OUT}"

	echo -e "${yellow}"
	echo "=========================="
	echo "  END: FUNCTION MAKE ZIPS "
	echo "=========================="
	echo -e "${restore}"
}

FUNCTION_GENERATE_CHANGELOG()
{
	echo -e "${red}"
	echo "======================================="
	echo " START : FUNCTION GENERATE CHANGELOG   "
	echo "======================================="
	echo -e "${restore}"

	    while true; do
		echo -e "${cyan}";
		read -rp "Generate Changelog? (y/n)" yn;
		echo -e "${restore}"
		case $yn in
		   y|Y )
            # Exports Changelog
            cd "${BUILD_KERNEL_DIR}" || exit
            export Changelog=Changelog.txt
            if [[ -f "${Changelog}" ]];
            then
            rm -f "${Changelog}"
            fi
            touch "${Changelog}"
            # Print something to build output
            echo -e "${yellow}""Generating changelog...""${restore}"
            for i in $(seq 5);
            do
            export After_Date="$(date --date="$i days ago" +%m-%d-%Y)"
            k=$(expr "$i" - 1)
            export Until_Date="$(date --date="$k days ago" +%m-%d-%Y)"
            # Line with after --- until was too long for a small ListView
	        echo '====================' >> "${Changelog}";
	        echo "   ""${Until_Date}"     >> "${Changelog}";
	        echo '====================' >> "${Changelog}";
	        echo >> "${Changelog}";
	        # Cycle through every repo to find commits between 2 dates
	        git log --oneline --after="{$After_Date}" --until="{$Until_Date}" >> "${Changelog}"
	        echo >> "${Changelog}";
	        done
	        sed -i 's/project/   */g' "${Changelog}"
	        echo -e ""
	        echo -e "${cyan}" "Changelog Generated""${restore}";
	        break;
	        ;;
	    n|N )
	        echo -e "${yellow}""Changelog Not Generate""${restore}";
	        break;
	        ;;
	     * )
	       echo -e "${yellow}" "Please Answer yes or no""${restore}";
	       ;;
	   esac;
	done;
	echo -e "${yellow}"
	echo "==================================="
	echo "  END: FUNCTION GENERATE CHANGELOG "
	echo "==================================="
	echo -e "${restore}"
}

(
    START_TIME=$(date +%s)
    FUNCTION_RESET_GIT_BRANCH
    FUNCTION_CLEAN
    FUNCTION_GENERATE_DEFCONFIG
    FUNCTION_BUILD_KERNEL
    FUNCTION_MAKE_ZIP
    FUNCTION_GENERATE_CHANGELOG

    END_TIME=$(date +%s)
    let "ELAPSED_TIME=${END_TIME}-${START_TIME}"
    echo -e "${cyan}"
    echo "Total compile time is ${ELAPSED_TIME} seconds"
    echo -e "${restore}"
) 2>&1 | tee -a ./build.log;
