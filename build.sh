#!/bin/bash
set -x

tg_sendDocument() {
    curl "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
    -F chat_id="-$TG_CHAT_ID_GROUP" -F document=@"$1" -F caption="$2" &> /dev/null
}

tg_sendMessage() {
    curl "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -F chat_id="-$TG_CHAT_ID_GROUP" -F text="$1" -F parse_mode="Markdown" &> /dev/null
}

kmake() {
	MAKEOPTS="$MAKEOPTS -j$(nproc) O=out ARCH=arm64 CROSS_COMPILE=$CROSS/$PRE_64- CROSS_COMPILE_ARM32=$CROSSCOMPAT/$PRE_32- CROSS_COMPILE_COMPAT=$CROSSCOMPAT/$PRE_32-"
	env PATH="$CROSS:$CROSSCOMPAT:$PATH" make $MAKEOPTS CC="$CCACHE${CROSS}/$CC_CHOICE" "$@"
}

kzip() {
	[ ! -d out/ak3 ] && git clone --depth=1 https://github.com/osm0sis/AnyKernel3 out/ak3
	echo -e "
	# AnyKernel3 Ramdisk Mod Script
	# osm0sis @ xda-developers
	properties() { '
	kernel.string=$BLDHST
	device.name1=$DEVICE
	do.devicecheck=1
	do.modules=0
	do.systemless=0
	do.cleanup=1
	do.cleanuponabort=0
	'; }
	block=/dev/block/bootdevice/by-name/boot;
	is_slot_device=0;
	ramdisk_compression=auto;
	patch_vbmeta_flag=auto;
	. tools/ak3-core.sh;
	set_perm_recursive 0 0 755 644 \$ramdisk/*;
	set_perm_recursive 0 0 750 750 \$ramdisk/init* \$ramdisk/sbin;
	dump_boot;
	if [ -d \$ramdisk/overlay ]; then
		rm -rf \$ramdisk/overlay;
	fi;
	write_boot;
	" > out/ak3/anykernel.sh && sed -i "s/\t//g;1d" out/ak3/anykernel.sh
	[ -f out/arch/arm64/boot/Image ] && cp out/arch/arm64/boot/Image out/ak3
	[ -f out/arch/arm64/boot/dtb.img ] && cp out/arch/arm64/boot/dtb.img out/ak3/dtb
	[ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img out/ak3
	mkdir -p out/ak3/vendor_ramdisk out/ak3/vendor_patch
	ZIP_PREFIX_KVER=$(grep Linux out/.config | cut -f 3 -d " ")
	ZIP_POSTFIX_DATE=$(date +%d-%h-%Y-%R:%S | sed "s/:/./g")
	ZIP_PREFIX_STR="$BLDHST-$DEVICE"
	ZIP_ORGES_BUILD_TYPE=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
	ZIP_FMT=${ZIP_PREFIX_STR}_"${ZIP_PREFIX_KVER}"_"${ZIP_ORGES_BUILD_TYPE}"_"${ZIP_POSTFIX_DATE}"
	if [[ $* =~ "out" ]]; then
		( cd out && zip -q -0 "${ZIP_FMT}".zip . )
	else
		( cd out/ak3 && zip -r9 ../"${ZIP_FMT}".zip . -x '*.git*' )
	fi
	if [[ $* =~ "upload" ]]; then
		(
			cd out || exit
			[[ $* =~ "tel" ]] && tg_sendDocument "${ZIP_FMT}.zip" "$(md5sum "${ZIP_FMT}.zip" | grep -oE "[0-9a-f]{32}")"
			[[ $* =~ "osh" ]] && curl -sF f[]=@"${ZIP_FMT}".zip "https://oshi.at" | tee upload.log && tg_sendMessage "$(cat upload.log)"
			[[ $* =~ "bas" ]] && curl -sT "${ZIP_FMT}".zip "https://bashupload.com" | tee upload.log && tg_sendMessage "$(grep wget upload.log | cut -c6-)"
			[[ $* =~ "tmp" ]] && curl -sF files[]=@"${ZIP_FMT}".zip "https://tmp.ninja/upload.php?output=text" | tee upload.log && tg_sendMessage "$(cat upload.log)"
			[[ $* =~ "pix" ]] && echo "https://pixeldrain.com/u/$(curl -sF file=@"${ZIP_FMT}".zip "https://pixeldrain.com/api/file" | grep -Po '(?<="id":")[^"]*')" | tee upload.log && tg_sendMessage "$(cat upload.log)"
			rm upload.log
		)
	fi
}

ZIP_ORGES_BUILD_TYPE=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
tg_sendMessage "Build Started on Branch: ${ZIP_ORGES_BUILD_TYPE}"

BLDHST="mochi" && DEVICE="vayu"
if [[ $* =~ "gcc" ]]; then
	IS_GCC=1
	DOCKER_64=/usr/gcc64 && DOCKER_32=/usr/gcc32
	LOCAL_64=~/.local/gcc64 && LOCAL_32=~/.local/gcc32
	PRE_64="aarch64-elf" && PRE_32="arm-eabi"
	if [[ $* =~ "host" ]]; then
		DOCKER_64=/usr && DOCKER_32=/usr
		PRE_64="aarch64-linux-gnu" && PRE_32="arm-linux-gnueabi"
	fi
	CC_CHOICE="$PRE_64-gcc"
fi
if [[ $* =~ "cla" ]]; then
	IS_GCC=0
	DOCKER_64=/usr/clang && DOCKER_32=/usr/clang
	LOCAL_64=~/.local/clang && LOCAL_32=~/.local/clang
	PRE_64="aarch64-linux-gnu" && PRE_32="arm-linux-gnueabi"
	CC_CHOICE=clang
fi

DEFCONFIG="vayu_defconfig"
export KBUILD_BUILD_USER="$BLDHST"
export KBUILD_BUILD_HOST="$BLDHST"

[[ $(which ccache) ]] && CCACHE="$(which ccache) "
[ -d $DOCKER_64 ] && CROSS=$DOCKER_64/bin || CROSS=$LOCAL_64/bin
[ -d $DOCKER_32 ] && CROSSCOMPAT=$DOCKER_32/bin || CROSSCOMPAT=$LOCAL_32/bin

if [ $IS_GCC -eq 1 ]; then
	echo -e "$($CROSS/$PRE_64-gcc -v)\n$($CROSSCOMPAT/$PRE_32-gcc -v)"
else
	echo -e "$($CROSS/$CC_CHOICE -v)"
fi

[[ $* =~ "zip" ]] && kzip "$*" && exit

kmake $DEFCONFIG

[[ $* =~ "llv" ]] && MAKEOPTS="$MAKEOPTS LD=ld.lld AR=llvm-ar NM=llvm-nm STRIP=llvm-strip OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf"
[[ $* =~ "reg" ]] && cp out/.config arch/arm64/configs/$DEFCONFIG && exit
[[ $* =~ "lld" ]] && MAKEOPTS="$MAKEOPTS LD=ld.lld"
if [[ $* =~ "gcc" ]]; then
	[[ $* =~ "lto" ]] && echo "CONFIG_LTO_GCC=y" >> out/.config
	[[ $* =~ "gra" ]] && echo "CONFIG_GCC_GRAPHITE=y" >> out/.config
fi
if [[ $* =~ "cla" ]]; then
	[[ $* =~ "lto" ]] && echo -e "CONFIG_LTO_CLANG=y\nCONFIG_THINLTO=n" >> out/.config
	[[ $* =~ "thi" ]] && echo "CONFIG_THINLTO=y" >> out/.config
	echo "CONFIG_CFI_CLANG=n" >> out/.config
fi

[[ $* =~ "nofort" ]] && echo "CONFIG_FORTIFY_SOURCE=n" >> out/.config

if [[ ${CI} ]]; then
	if [[ $* =~ "cidebug" ]]; then
		touch out/build.log
		kmake
		echo $KSU_GIT_VERSION
	else
		kmake &> out/build.log
		echo $KSU_GIT_VERSION
	fi
	if [ ! -f out/arch/arm64/boot/Image ]; then
		tg_sendDocument "out/build.log" "Build failed" && exit
	else
		tg_sendDocument "out/build.log" "Build done"
		kzip "$*"
	fi
else
	MAKE_CMDS=$(echo "$*" | grep -oE "mk_.*\$" | sed "s/mk_//g;s/\\$//g")
	if [[ ${#MAKE_CMDS} -gt 0 ]]; then
		kmake "$MAKE_CMDS"
	else
		kmake
	fi
fi
