#!/bin/bash

# 更改时区为 Asia/Shanghai
echo "更改时区为 Asia/Shanghai..."
sudo timedatectl set-timezone Asia/Shanghai

# 要更改权限的文件列表
echo "为自动构建需要运行的binary设置权限..."
files=(
    "./tools/binary/zstd"
    "./tools/binary/payload-dumper-go"
    "./tools/binary/extract.erofs"
    "./tools/binary/vbmeta-disable-verification"
    "./tools/binary/mkfs.erofs"
    "./tools/binary/lpmake"
    "./tools/binary/imgextractorLinux"
)

# 循环更改每个文件的权限
for file in "${files[@]}"; do
    sudo chmod 777 "$file"
done

# 解压指定的 ZIP 文件
STOCK_ZIP_FILE="./downloads/fuxi-ota_full-OS2.0.203.0.VMCCNXM-user-15.0-c635d55d5c.zip"
STOCK_PAYLOAD_DIR="./Stock Package/payload.bin"
STOCK_EXTRACT_DIR="./Stock Package"

if [ -f "$STOCK_ZIP_FILE" ]; then
    echo "解压 $STOCK_ZIP_FILE..."
    mkdir -p "$STOCK_EXTRACT_DIR"
    pv "$STOCK_ZIP_FILE" | bsdtar -xvf - -C "$STOCK_EXTRACT_DIR"
else
    echo "未找到 ZIP 文件：$STOCK_ZIP_FILE"
    exit 1
fi

# 解压payload.bin文件
echo "解压移植包的payload.bin"
./tools/binary/payload-dumper-go -o "$STOCK_EXTRACT_DIR" "$STOCK_PAYLOAD_DIR"

# 提取镜像文件内容
images=(
    "odm.img"
    "product.img"
    "system.img"
    "system_ext.img"
    "system_dlkm.img"
    "vendor.img"
    "vendor_dlkm.img"
)

# 循环处理每个镜像文件
for image in "${images[@]}"; do
    echo "提取 $image..."
    ./tools/binary/extract.erofs -i "$STOCK_EXTRACT_DIR/$image" -o "$STOCK_EXTRACT_DIR" -x
done

echo "所有镜像文件已提取完成！"

# 解压移植包的 ZIP 文件
MIGRATION_ZIP_FILE="./downloads/xuanyuan-ota_full-OS2.0.212.0.VOACNXM-user-15.0-5395f5a1d0.zip"
MIGRATION_PAYLOAD_DIR="./Migration Package/payload.bin"
MIGRATION_EXTRACT_DIR="./Migration Package"

if [ -f "$MIGRATION_ZIP_FILE" ]; then
    echo "解压 $MIGRATION_ZIP_FILE..."
    mkdir -p "$MIGRATION_EXTRACT_DIR"
    pv "$MIGRATION_ZIP_FILE" | bsdtar -xvf - -C "$MIGRATION_EXTRACT_DIR"
else
    echo "未找到 ZIP 文件：$MIGRATION_ZIP_FILE"
    exit 1
fi

# 解压payload.bin文件
echo "解压移植包的payload.bin"
./tools/binary/payload-dumper-go -o "$MIGRATION_EXTRACT_DIR" "$MIGRATION_PAYLOAD_DIR"

# 提取镜像文件内容
images=(
    "mi_ext.img"
    "product.img"
    "system.img"
    "system_ext.img"
)

# 循环处理每个镜像文件
for image in "${images[@]}"; do
    echo "提取 $image..."
    ./tools/binary/extract.erofs -i "$MIGRATION_EXTRACT_DIR/$image" -o "$MIGRATION_EXTRACT_DIR" -x
done

echo "所有镜像文件已提取完成！"

# 删除原包的super分区镜像文件
rm -rf "$STOCK_EXTRACT_DIR/mi_ext.img" \
       "$STOCK_EXTRACT_DIR/odm.img" \
       "$STOCK_EXTRACT_DIR/product.img" \
       "$STOCK_EXTRACT_DIR/system.img" \
       "$STOCK_EXTRACT_DIR/system_ext.img" \
       "$STOCK_EXTRACT_DIR/system_dlkm.img" \
       "$STOCK_EXTRACT_DIR/vendor.img" \
       "$STOCK_EXTRACT_DIR/vendor_dlkm.img"

# 禁用 vbmeta, vbmeta_system 校验
echo "禁用avb2.0校验"

# 要删除的内容
PATTERN1=",avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey:/avb/t-gsi.avbpubkey"
PATTERN2="avb=vbmeta_system,"
PATTERN3="avb=vbmeta,"

# 转义特殊字符
PATTERN1=$(printf '%s\n' "$PATTERN1" | sed 's/[\/&]/\\&/g')
PATTERN2=$(printf '%s\n' "$PATTERN2" | sed 's/[\/&]/\\&/g')
PATTERN3=$(printf '%s\n' "$PATTERN3" | sed 's/[\/&]/\\&/g')

# 修改 fstab.qcom 文件
if [ -f "$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom" ]; then
    echo "正在修改 $STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom..."

    # 使用 sed 删除指定内容
    sed -i "s#$PATTERN1##g" "$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"
    sed -i "s#$PATTERN2##g" "$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"
    sed -i "s#$PATTERN3##g" "$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"

    echo "修改完成！"
else
    echo "未找到文件：$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"
    exit 1
fi

# 处理vendor_boot
mkdir vendor_boot
cp -f "$STOCK_EXTRACT_DIR/vendor_boot.img" ./vendor_boot
cp -f ./tools/binary/magiskboot ./vendor_boot
cp -f ./device_files/xiaomi_sm8550_files/perfmgr.ko ./vendor_boot

cd vendor_boot
./magiskboot unpack -h ./vendor_boot.img
comp=$(./magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
mv -f -f ramdisk.cpio ramdisk.cpio.$comp
./magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
mkdir -p ramdisk
chmod 755 ramdisk
cd ramdisk
EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1

# 去除vendor_boot的avb校验
PATTERN1=",avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey:/avb/t-gsi.avbpubkey"
PATTERN2="avb=vbmeta_system,"
PATTERN3="avb=vbmeta,"

# 转义特殊字符
PATTERN1=$(printf '%s\n' "$PATTERN1" | sed 's/[\/&]/\\&/g')
PATTERN2=$(printf '%s\n' "$PATTERN2" | sed 's/[\/&]/\\&/g')
PATTERN3=$(printf '%s\n' "$PATTERN3" | sed 's/[\/&]/\\&/g')

# 修改 fstab.qcom 文件
sed -i "s#$PATTERN1##g" ./first_stage_ramdisk/fstab.qcom
sed -i "s#$PATTERN2##g" ./first_stage_ramdisk/fstab.qcom
sed -i "s#$PATTERN3##g" ./first_stage_ramdisk/fstab.qcom

cd ..

cd ./ramdisk
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk-new.cpio
cd ..

./magiskboot compress=$comp ramdisk-new.cpio 2>&1
if [ $? != 0 ] && $comp --help 2>/dev/null; then
  $comp -9c ramdisk-new.cpio > ramdisk.cpio.$comp
fi
rm -rf ramdisk.cpio.lz4_legacy ramdisk.cpio

ramdisk=$(ls ramdisk-new.cpio* 2>/dev/null | tail -n1)
cp -f $ramdisk ramdisk.cpio

rm -rf ramdisk-new.cpio.lz4
nocompflag="-n";;

mkdir out
./magiskboot repack $nocompflag vendor_boot.img ./out/vendor_boot.img

cd ..
cp -f ./vendor_boot/out/vendor_boot.img ./"Stock Package"/vendor_boot.img
rm -rf ./vendor_boot

echo "添加mi_block的Twrp Recovery"

# 定义源文件和目标目录
SOURCE_FILE="./tools/recovery/[REC]3.7.1_12-Mi13_v9.0_A15-fuxi-skkk.img"
STOCK_EXTRACT_DIR="./Stock Package"
DESTINATION_FILE="$STOCK_EXTRACT_DIR/recovery.img"

# 复制并重命名文件
cp "$SOURCE_FILE" "$DESTINATION_FILE"

# 检查复制是否成功
if [ $? -eq 0 ]; then
    echo "文件已成功复制并重命名为 recovery.img"
else
    echo "复制文件时发生错误"
fi

echo "为自定义刷机脚本做准备"
DESTINATION_DIR="$STOCK_EXTRACT_DIR/firmware"

# 创建firmware文件夹
mkdir -p "$STOCK_EXTRACT_DIR"/firmware

# 移动所有.img文件
mv "$STOCK_EXTRACT_DIR"/*.img "$DESTINATION_DIR"

# 检查移动操作是否成功
if [ $? -eq 0 ]; then
    echo "所有 .img 文件已成功移动到 $DESTINATION_DIR"
else
    echo "移动文件时发生错误"
fi

# 添加机型文件
echo "添加机型文件"
rm -rf "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"
cp -rf "$STOCK_EXTRACT_DIR/product/etc/device_features/" "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"

# 屏蔽系统更新
echo "屏蔽系统更新"
sed -i 's/<bool name="support_ota_validate">true<\/bool>/<bool name="support_ota_validate">false<\/bool>/' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/fuxi.xml"

# 解锁Widevine L1证书在线更新
echo "解锁widevine L1证书在线更新"
sed -i 's/<integer name="support_widevine_l1">1<\/integer>/<integer name="support_widevine_l1">2<\/integer>/' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/fuxi.xml"

# 修复自带相机
echo "修复自带相机闪退"
rm -rf "$MIGRATION_EXTRACT_DIR/product/priv-app/MiuiCamera/"
7z x ./device_files/xiaomi_sm8550_files/MiuiCamera.7z -o"$MIGRATION_EXTRACT_DIR/product/priv-app/MiuiCamera"

# 替换MiuiCit
echo "替换MiuiCit"
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/MiuiCit/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/MiuiCit/" "$MIGRATION_EXTRACT_DIR/product/app/MiuiCit/"

# 替换小爱翻译
echo "小爱翻译"
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/AiasstVision/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/AiasstVision/" "$MIGRATION_EXTRACT_DIR/product/app/AiasstVision/"

# 修复MiAONService
echo "修复MiAONService"
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/MiAONServiceV/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/MiAONService/" "$MIGRATION_EXTRACT_DIR/product/app/MiAONService/"

# 恢复官方壁纸
echo "恢复官方壁纸"
rm "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_BG.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_BK.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_BN.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_PK.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_PU.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_WG.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_WH.jpg \
   "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper/wallpaper_YB.jpg 

cp -f "$STOCK_EXTRACT_DIR"/product/media/wallpaper/wallpaper13.jpg "$MIGRATION_EXTRACT_DIR"/product/media/wallpaper
cp -f "$STOCK_EXTRACT_DIR"/product/media/wallpaper/wallpaper13.jpg "$MIGRATION_EXTRACT_DIR"/product/media/theme/default/lock_wallpaper
cp -rf "$STOCK_EXTRACT_DIR/product/media/wallpaper/wallpaper_group/06_GlassyLight/" "$MIGRATION_EXTRACT_DIR/product/media/wallpaper/wallpaper_group/06_GlassyLight/"
cp -rf "$STOCK_EXTRACT_DIR/product/media/wallpaper/wallpaper_group/07_ShadowGeometry/" "$MIGRATION_EXTRACT_DIR/product/media/wallpaper/wallpaper_group/07_ShadowGeometry/"

# 修复NFC
echo "修复NFC"
cp -rf "$STOCK_EXTRACT_DIR/product/pangu/system/app/NQNfcNci" "$MIGRATION_EXTRACT_DIR/product/pangu/system/app/NQNfcNci"

# 去除国区谷歌商店限制
echo "去除国区谷歌商店限制"
sed -i -e '/<feature name="cn.google.services" \/>/d' \
    -e '/<feature name="com.google.android.feature.services_updater" \/>/d' "$MIGRATION_EXTRACT_DIR"/product/etc/permissions/cn.google.services.xml

# 解锁全屏aod
# echo "解锁全屏aod"
# sed -i '/<bool name="is_aod_need_grayscale">false<\/bool>/a \
#     <!--whether the device supports aod fullscreen mode--> \
#     <bool name="support_aod_fullscreen">true</bool> \
#     <!-- The fps of aon_screen_off--> \
#     <integer name="aon_screen_off_fps">0</integer>' "$MIGRATION_EXTRACT_DIR"/product/etc/device_features/fuxi.xml
# sed -i ''"$(sed -n '/ro.vendor.display.primary_idle_refresh_rate/=' "$STOCK_EXTRACT_DIR/odm/etc/build.prop")"'a ro.vendor.mi_sf.aod_mode_ddic_refresh_rate=1' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 解锁节律护眼模式
echo "解锁节律护眼支持"
sed -i '/<bool name="config_sunlight_mode_available">true<\/bool>/a \
    <!-- default rhythmic eyecare mode --> \
    <integer name="default_eyecare_mode">2</integer>' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/fuxi.xml"

# 解锁24-30-40隐藏屏幕刷新率
# echo "解锁24-30-40hz隐藏刷新率支持"
# sed -i '/<integer-array name="fpsList">/,/<\/integer-array>/{
#     /<item>60<\/item>/a\
#         <item>40</item>\
#         <item>30</item>\
#         <item>24</item>
# }' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/fuxi.xml"

# 解锁无网通信 By ZnCl2
echo "解锁无网通信"
sed -i '/<!-- BSP BEGIN -->/a \
    <!-- whether support virtual call--> \
    <string name="support_virtual_call">fuxi</string>' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/fuxi.xml"

# 解锁控制中心透明效果
echo "解锁控制中心透明效果"
cp -f ./device_files/xiaomi_sm8550_files/EastXiaomiSystemUIOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay

# 禁用无效的卫星通信入口
echo "禁用无效的卫星通信入口"
cp -f ./device_files/xiaomi_sm8550_files/EastRemoveSatelliteOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay

# 解锁高级材质
echo "解锁高级材质"
sed -i 's/persist.sys.background_blur_supported=[^*]*/persist.sys.background_blur_supported=true/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.sys.background_blur_status_default=[^*]*/persist.sys.background_blur_status_default=true/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.sys.advanced_visual_release=[^*]*/persist.sys.advanced_visual_release=3/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 修复开机动画
echo "修复开机动画
cp -f "$STOCK_EXTRACT_DIR"/product/media/bootanimation.zip "$MIGRATION_EXTRACT_DIR"/product/media

# 添加屏幕配置文件
echo "添加屏幕配置文件
rm -rf "$MIGRATION_EXTRACT_DIR"/product/etc/displayconfig
cp -rf "$STOCK_EXTRACT_DIR"/product/etc/displayconfig "$MIGRATION_EXTRACT_DIR"/product/etc

# 分辨率修复
echo "分辨率修复"
sed -i 's/ro.sf.lcd_density=[^*]*/ro.sf.lcd_density=440/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=440/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 禁用不可卸载v2 Prop
echo "禁用不可卸载v2 Prop"
sed -i 's/ro.miui.support.system.app.uninstall.v2=true/# ro.miui.support.system.app.uninstall.v2=true/g' "$MIGRATION_EXTRACT_DIR"/mi_ext/etc/build.prop

# 清除套壳应用和无用文件
echo "清除套壳应用和无用文件"
directories=(
    "$MIGRATION_EXTRACT_DIR/product/firmware"
    "$MIGRATION_EXTRACT_DIR/product/data-app/MIUIThemeStore"
    "$MIGRATION_EXTRACT_DIR/product/data-app/MIUISecurityManager"
)

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        echo "正在删除目录: $dir"
        rm -rf "$dir"
    else
        echo "目录不存在: $dir"
    fi
done
echo "指定的目录已删除！"

# 精简data-app推广应用
echo "精简data-app的垃圾预装应用"
for files in BaiduIME iFlytekIME MIGalleryLockscreen MIService MIUIEmail MIUIHuanji MiuiScanner OS2VipAccount SmartHome XMRemoteController MiRadio MiShop MIUIGameCenter MIUINewHome_Removable MIUIVideo MIUIYoupin Health MIUIDuokanReader
do
  appsui=$(find "$MIGRATION_EXTRACT_DIR"/product/data-app/ -type d -iname "*${files}*")
  if [ ! -z "$appsui" ]; then
    echo "得到精简目录: $appsui"
    rm -rf "$appsui"
  else
    echo "没有找到匹配的目录: $files"
  fi
done

# 将内置浏览器改为可卸载应用
echo "将内置浏览器改为可卸载应用"
mv "$MIGRATION_EXTRACT_DIR"/product/priv-app/MIUIBrowser "$MIGRATION_EXTRACT_DIR"/product/data-app/MIUIBrowser

# 添加apex支持
echo "添加apex vndk支持"
pv device_files/common_files/apex.zip | bsdtar -xvf - -C "$MIGRATION_EXTRACT_DIR/system_ext/apex"

# 修复开机出现提示设备内部错误
echo "修复开机出现提示设备内部错误"
sed -i "/<\/manifest>/i \    <vendor-ndk>\n        <version>30<\/version>\n    <\/vendor-ndk>\n    <vendor-ndk>\n        <version>31<\/version>\n    <\/vendor-ndk>\n    <vendor-ndk>\n        <version>32<\/version>\n    <\/vendor-ndk>\n    <vendor-ndk>\n        <version>33<\/version>\n    <\/vendor-ndk>" "$MIGRATION_EXTRACT_DIR"/system_ext/etc/vintf/manifest.xml

# 修复cust挂载
echo "修复cust挂载"
sed -i -e 's/^\(ro\.miui\.cust_erofs\)/# \1/' \
        -e 's/^\(ro\.miui\.preinstall_to_data\)/# \1/' \
        -e 's/^\(ro\.miui\.cust_img_path\)/# \1/' \
        -e 's/^\(ro\.miui\.product_to_cust\)/# \1/' \
        -e 's/^\(ro\.miui\.cust_erofs\)/# \1/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 禁用tango转译器
echo "禁用tango转译器"
sed -i -e 's/^\(tango\.enabled\)/# \1/' \
        -e 's/^\(tango\.debug\)/# \1/' \
        -e 's/^\(tango\.pretrans\.max_size\)/# \1/' \
        -e 's/^\(tango\.pretrans_on_install\)/# \1/' \
        -e 's/^\(tango\.pretrans\.debug\)/# \1/' \
        -e 's/^\(tango\.pretrans\.lib\)/# \1/' \
        -e 's/^\(tango\.pretrans\.apk\)/# \1/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop

# 解锁MiuiCamera HLG支持 By ZnCl2
echo "解锁MiuiCamera HLG支持"
sed -i '$a \
# Enable MiuiCamera HLG Support by ZnCl2 \
persist.camera.settings.hlg=true' "$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"

# 替换Overlay
echo "替换Overlay"
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/DevicesAndroidOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/DevicesOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/MiuiFrameworkResOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/SettingsRroDeviceHideStatusBarOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/SettingsRroDeviceTypeOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay
# mv -f "$STOCK_EXTRACT_DIR"/product/overlay/MiuiCameraOverlayLeicaed "$MIGRATION_EXTRACT_DIR"/product/overlay
mv -f "$STOCK_EXTRACT_DIR"/product/overlay/MiuiFrameworkTelephonyResOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay

# 去除无用的屏幕刘海切换
# echo "去除无效的屏幕刘海切换"
# mkdir -p ./mod/SettingsRroDeviceTypeOverlay
# mv "$MIGRATION_EXTRACT_DIR"/product/overlay/SettingsRroDeviceTypeOverlay.apk ./mod
# APKEditor="java -jar ./tools/jar/APKEditor.jar"
# $APKEditor d -f -i ./mod/SettingsRroDeviceTypeOverlay.apk -o ./mod/SettingsRroDeviceTypeOverlay 2>&1 1>&/dev/null
# sed -i '/<bool name="config_show_softap_wifi6">true<\/bool>/a \
#   <bool name="config_device_support_force_black">false</bool>' ./mod/SettingsRroDeviceTypeOverlay/resources/package_1/res/values/bools.xml
# sed -i '/<public id="0x7f010000" type="bool" name="config_global_support_slm" \/>/a \
#   <public id="0x7f010002" type="bool" name="config_device_support_force_black" \/> ' ./mod/SettingsRroDeviceTypeOverlay/resources/package_1/res/values/public.xml
# APKEditor="java -jar ./tools/jar/APKEditor.jar"
# $APKEditor b -f -i ./mod/SettingsRroDeviceTypeOverlay -o ./mod/SettingsRroDeviceTypeOverlay_modified.apk 2>&1 1>&/dev/null
# sudo mv ./mod/SettingsRroDeviceTypeOverlay_modified.apk "$MIGRATION_EXTRACT_DIR"/product/overlay/SettingsRroDeviceTypeOverlay.apk
# sudo rm -rf ./mod

# 恢复静止刷新率下限为1Hz
# echo "恢复静止刷新率下限为1Hz"
# sed -i 's/ro.vendor.display.primary_idle_refresh_rate=[^*]*/ro.vendor.display.primary_idle_refresh_rate=60,1:492/' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 更新Vulkan 1.4 By ZnCl2
# echo "解锁Vulkan 1.4"
# pv device_files/xiaomi_sm8550_files/Vulkan1.4-for-fuxi.zip | bsdtar -xvf - -C "$STOCK_EXTRACT_DIR/vendor"

# 添加MiBeam支持
cp -rf ./device_files/common_files/android.hardware.nfc.beam.xml "$STOCK_EXTRACT_DIR/odm/etc/permissions"
sed -i ''"$(sed -n '/ro.vendor.nfc.dispatch_optim/=' "$STOCK_EXTRACT_DIR/odm/etc/build.prop")"'a ro.vendor.nfc.mibeam=1' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 解锁新版nfc读写勿扰2.0
echo "解锁新版nfc读写勿扰2.0"
sed -i 's/ro.vendor.nfc.dispatch_optim=[^*]*/ro.vendor.nfc.dispatch_optim=2/' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 移植lhdc自适应采样率
echo "移植lhdc自适应采样率"
sed -i 's/bluetooth.profile.hap.client.enabled=[^*]*/bluetooth.profile.hap.client.enabled=true/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i ''"$(sed -n '/ro.miui.has_gmscore/=' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop)"'a persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# ZRAM 1:1调整
echo "zram 1:1调整"
mkdir -p ./tmp
sudo mv "$MIGRATION_EXTRACT_DIR"/system_ext/etc/perfinit_bdsize_zram.conf ./tmp/
jq '.zram += [{"product_name": ["umi", "cmi", "cas", "apollo", "thyme", "alioth", "munch", "venus", "mars", "star", "odin", "fuxi", "fuxi", "ishtar"], "zram_size": {"6": 6144, "8": 8192, "12": 12288, "16": 16384}}]' ./tmp/perfinit_bdsize_zram.conf >./tmp/perfinit_bdsize_zram_out.conf
sudo mv ./tmp/perfinit_bdsize_zram_out.conf "$MIGRATION_EXTRACT_DIR"/system_ext/etc/perfinit_bdsize_zram.conf
sudo rm -rf ./tmp

# 启用dm设备映射控制器
echo "启用dm设备映射控制器"
sed -i '/persist.miui.extm.daily_flush_count_adj=1/a persist.miui.extm.dm_opt.enable=true' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 添加性能等级支持
echo "添加性能等级支持"
sed -i 's/^ro.vendor.media_performance_class=35/# &/' "$MIGRATION_EXTRACT_DIR/product/etc/build.prop"
sed -i 's/^ro.odm.build.media_performance_class=35/# &/' "$MIGRATION_EXTRACT_DIR/product/etc/build.prop"
sed -i '/ro\.odm\.build\.version\.sdk=33/a ro.odm.build.media_performance_class=33' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 优化核心分配
echo "优化核心分配"
sed -i 's/ro.miui.affinity.sfui=[^*]*/ro.miui.affinity.sfui=0-2/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/ro.miui.affinity.sfre=[^*]*/ro.miui.affinity.sfre=0-2/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.sys.dexpreload.other_cores=[^*]*/persist.sys.dexpreload.other_cores=0-2/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.sys.dexpreload.cpu_cores=[^*]*/persist.sys.dexpreload.cpu_cores=0-7/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.sys.dexpreload.big_prime_cores=[^*]*/persist.sys.dexpreload.big_prime_cores=3-7/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i '$a \
# East added for Xiaomi HyperOS Core allocation \
persist.vendor.display.miui.composer_boost=3-7 \
persist.sys.miui_animator_sched.big_prime_cores=3-7 \
persist.sys.miui_animator_sched.sched_threads=2 \
persist.sys.miui_animator_sched.bigcores=3-7' "$MIGRATION_EXTRACT_DIR/product/etc/build.prop"


# 常规修改
echo "常规修改"
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)
sudo sed -i 's/ro.build.user=.*/ro.build.user=Curious/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.build.host=.*/ro.build.host=Curious_AutoBuildBot/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.system.build.date=.*/ro.system.build.date='"$build_time"'/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.system.build.date.utc=.*/ro.system.build.date.utc='"$build_utc"'/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.build.date=.*/ro.build.date='"$build_time"'/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.build.date.utc=.*/ro.build.date.utc='"$build_utc"'/' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sudo sed -i 's/ro.system_dlkm.build.date=.*/ro.system_dlkm.build.date='"$build_time"'/' "$STOCK_EXTRACT_DIR"/system_dlkm/etc/build.prop
sudo sed -i 's/ro.system_dlkm.build.date.utc=.*/ro.system_dlkm.build.date.utc='"$build_utc"'/' "$STOCK_EXTRACT_DIR"/system_dlkm/etc/build.prop
sudo sed -i 's/ro.vendor.build.date=.*/ro.vendor.build.date='"$build_time"'/' "$STOCK_EXTRACT_DIR"/vendor/build.prop
sudo sed -i 's/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc='"$build_utc"'/' "$STOCK_EXTRACT_DIR"/vendor/build.prop
sudo sed -i 's/ro.vendor_dlkm.build.date=.*/ro.vendor_dlkm.build.date='"$build_time"'/' "$STOCK_EXTRACT_DIR"/vendor_dlkm/etc/build.prop
sudo sed -i 's/ro.vendor_dlkm.build.date.utc=.*/ro.vendor_dlkm.build.date.utc='"$build_utc"'/' "$STOCK_EXTRACT_DIR"/vendor_dlkm/etc/build.prop
sudo sed -i 's/ro.system_ext.build.date=.*/ro.system_ext.build.date='"$build_time"'/' "$MIGRATION_EXTRACT_DIR"/system_ext/etc/build.prop
sudo sed -i 's/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc='"$build_utc"'/' "$MIGRATION_EXTRACT_DIR"/system_ext/etc/build.prop
sudo sed -i 's/ro.product.build.date=.*/ro.product.build.date='"$build_time"'/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sudo sed -i 's/ro.product.build.date.utc=.*/ro.product.build.date.utc='"$build_utc"'/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sudo sed -i 's/ro.odm.build.date=.*/ro.odm.build.date='"$build_time"'/' "$STOCK_EXTRACT_DIR"/odm/etc/build.prop
sudo sed -i 's/ro.odm.build.date.utc=.*/ro.odm.build.date.utc='"$build_utc"'/' "$STOCK_EXTRACT_DIR"/odm/etc/build.prop


# 自定义版本号
echo "自定义版本号"
sed -i 's/ro.mi.os.version.incremental=[^*]*/ro.mi.os.version.incremental=OS2.0.212.0.VMCCNXM/' "$MIGRATION_EXTRACT_DIR"/mi_ext/etc/build.prop
sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=fuxi/' "$MIGRATION_EXTRACT_DIR"/mi_ext/etc/build.prop
sed -i 's/xuanyuan/fuxi/g' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/OS2.0.212.0.VOACNXM/OS2.0.212.0.VMCCNXM/g' "$MIGRATION_EXTRACT_DIR"/mi_ext/etc/build.prop
sed -i 's/OS2.0.212.0.VOACNXM/OS2.0.212.0.VMCCNXM/g' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/OS2.0.212.0.VOACNXM/OS2.0.212.0.VMCCNXM/g' "$MIGRATION_EXTRACT_DIR"/system/system/build.prop
sed -i 's/OS2.0.212.0.VOACNXM/OS2.0.212.0.VMCCNXM/g' "$MIGRATION_EXTRACT_DIR"/system_ext/etc/build.prop
sed -i 's/OS2.0.203.0.VMCCNXM/OS2.0.212.0.VMCCNXM/g' "$STOCK_EXTRACT_DIR"/system_dlkm/etc/build.prop
sed -i 's/OS2.0.203.0.VMCCNXM/OS2.0.212.0.VMCCNXM/g' "$STOCK_EXTRACT_DIR"/vendor_dlkm/etc/build.prop
sed -i 's/OS2.0.203.0.VMCCNXM/OS2.0.212.0.VMCCNXM/g' "$STOCK_EXTRACT_DIR"/vendor/build.prop
sed -i 's/OS2.0.203.0.VMCCNXM/OS2.0.212.0.VMCCNXM/g' "$STOCK_EXTRACT_DIR"/odm/etc/build.prop

# 解压刷机脚本
unzip -o -q ./tools/flashscript/flashtools.zip -d ./output
mv "$STOCK_EXTRACT_DIR"/firmware ./output/firmware
cp -f ./device_files/common_files/cust.img ./output/firmware

# 修改刷机脚本
sed -i 's/nuwa/fuxi/g' ./output/FlashWindows.bat
sed -i 's/nuwa/fuxi/g' ./output/META-INF/com/google/android/update-binary

# 修补添加文件的上下文
python3 ./tools/python/fspatch.py "$STOCK_EXTRACT_DIR"/odm "$STOCK_EXTRACT_DIR"/config/odm_fs_config
python3 ./tools/python/fspatch.py "$STOCK_EXTRACT_DIR"/vendor "$STOCK_EXTRACT_DIR"/config/vendor_fs_config
python3 ./tools/python/fspatch.py "$STOCK_EXTRACT_DIR"/vendor_dlkm "$STOCK_EXTRACT_DIR"/config/vendor_dlkm_fs_config
python3 ./tools/python/fspatch.py "$STOCK_EXTRACT_DIR"/system_dlkm "$STOCK_EXTRACT_DIR"/config/system_dlkm_fs_config
python3 ./tools/python/contextpatch.py "$STOCK_EXTRACT_DIR"/odm "$STOCK_EXTRACT_DIR"/config/odm_file_contexts
python3 ./tools/python/contextpatch.py "$STOCK_EXTRACT_DIR"/vendor "$STOCK_EXTRACT_DIR"/config/vendor_file_contexts
python3 ./tools/python/contextpatch.py "$STOCK_EXTRACT_DIR"/vendor_dlkm "$STOCK_EXTRACT_DIR"/config/vendor_dlkm_file_contexts
python3 ./tools/python/contextpatch.py "$STOCK_EXTRACT_DIR"/system_dlkm "$STOCK_EXTRACT_DIR"/config/system_dlkm_file_contexts
python3 ./tools/python/fspatch.py "$MIGRATION_EXTRACT_DIR"/mi_ext "$MIGRATION_EXTRACT_DIR"/config/mi_ext_fs_config
python3 ./tools/python/fspatch.py "$MIGRATION_EXTRACT_DIR"/product "$MIGRATION_EXTRACT_DIR"/config/product_fs_config
python3 ./tools/python/fspatch.py "$MIGRATION_EXTRACT_DIR"/system "$MIGRATION_EXTRACT_DIR"/config/system_fs_config
python3 ./tools/python/fspatch.py "$MIGRATION_EXTRACT_DIR"/system_ext "$MIGRATION_EXTRACT_DIR"/config/system_ext_fs_config
python3 ./tools/python/contextpatch.py "$MIGRATION_EXTRACT_DIR"/mi_ext "$MIGRATION_EXTRACT_DIR"/config/mi_ext_file_contexts
python3 ./tools/python/contextpatch.py "$MIGRATION_EXTRACT_DIR"/product "$MIGRATION_EXTRACT_DIR"/config/product_file_contexts
python3 ./tools/python/contextpatch.py "$MIGRATION_EXTRACT_DIR"/system "$MIGRATION_EXTRACT_DIR"/config/system_file_contexts
python3 ./tools/python/contextpatch.py "$MIGRATION_EXTRACT_DIR"/system_ext "$MIGRATION_EXTRACT_DIR"/config/system_ext_file_contexts

# 打包img文件
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /odm --fs-config-file "$STOCK_EXTRACT_DIR"/config/odm_fs_config --file-contexts "$STOCK_EXTRACT_DIR"/config/odm_file_contexts "$STOCK_EXTRACT_DIR"/odm.img "$STOCK_EXTRACT_DIR"/odm
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /vendor --fs-config-file "$STOCK_EXTRACT_DIR"/config/vendor_fs_config --file-contexts "$STOCK_EXTRACT_DIR"/config/vendor_file_contexts "$STOCK_EXTRACT_DIR"/vendor.img "$STOCK_EXTRACT_DIR"/vendor
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /vendor_dlkm --fs-config-file "$STOCK_EXTRACT_DIR"/config/vendor_dlkm_fs_config --file-contexts "$STOCK_EXTRACT_DIR"/config/vendor_dlkm_file_contexts "$STOCK_EXTRACT_DIR"/vendor_dlkm.img "$STOCK_EXTRACT_DIR"/vendor_dlkm
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /system_dlkm --fs-config-file "$STOCK_EXTRACT_DIR"/config/system_dlkm_fs_config --file-contexts "$STOCK_EXTRACT_DIR"/config/system_dlkm_file_contexts "$STOCK_EXTRACT_DIR"/system_dlkm.img "$STOCK_EXTRACT_DIR"/system_dlkm
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /mi_ext --fs-config-file "$MIGRATION_EXTRACT_DIR"/config/mi_ext_fs_config --file-contexts "$MIGRATION_EXTRACT_DIR"/config/mi_ext_file_contexts "$MIGRATION_EXTRACT_DIR"/mi_ext.img "$MIGRATION_EXTRACT_DIR"/mi_ext
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /product --fs-config-file "$MIGRATION_EXTRACT_DIR"/config/product_fs_config --file-contexts "$MIGRATION_EXTRACT_DIR"/config/product_file_contexts "$MIGRATION_EXTRACT_DIR"/product.img "$MIGRATION_EXTRACT_DIR"/product
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /system --fs-config-file "$MIGRATION_EXTRACT_DIR"/config/system_fs_config --file-contexts "$MIGRATION_EXTRACT_DIR"/config/system_file_contexts "$MIGRATION_EXTRACT_DIR"/system.img "$MIGRATION_EXTRACT_DIR"/system
./tools/binary/mkfs.erofs -zlz4hc,9 -T 1230768000 --quiet --mount-point /system_ext --fs-config-file "$MIGRATION_EXTRACT_DIR"/config/system_ext_fs_config --file-contexts "$MIGRATION_EXTRACT_DIR"/config/system_ext_file_contexts "$MIGRATION_EXTRACT_DIR"/system_ext.img "$MIGRATION_EXTRACT_DIR"/system_ext

# 打包super
mi_ext_size=$(stat --format="%s" "$MIGRATION_EXTRACT_DIR"/mi_ext.img)
odm_size=$(stat --format="%s" "$STOCK_EXTRACT_DIR"/odm.img)
product_size=$(stat --format="%s" "$MIGRATION_EXTRACT_DIR"/product.img)
system_size=$(stat --format="%s" "$MIGRATION_EXTRACT_DIR"/system.img)
system_ext_size=$(stat --format="%s" "$MIGRATION_EXTRACT_DIR"/system_ext.img)
vendor_size=$(stat --format="%s" "$STOCK_EXTRACT_DIR"/vendor.img)
vendor_dlkm_size=$(stat --format="%s" "$STOCK_EXTRACT_DIR"/vendor_dlkm.img)
system_dlkm_size=$(stat --format="%s" "$STOCK_EXTRACT_DIR"/system_dlkm.img)
    ./tools/binary/lpmake --device super:9663676416 --virtual-ab \
        --metadata-size 65536 --super-name super --block-size 4096 --metadata-slots 3 \
        --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$STOCK_EXTRACT_DIR"/odm.img \
        --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$MIGRATION_EXTRACT_DIR"/product.img \
        --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$MIGRATION_EXTRACT_DIR"/mi_ext.img \
        --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$MIGRATION_EXTRACT_DIR"/system.img \
        --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$MIGRATION_EXTRACT_DIR"/system_ext.img \
        --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$STOCK_EXTRACT_DIR"/vendor.img \
        --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$STOCK_EXTRACT_DIR"/vendor_dlkm.img \
        --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$STOCK_EXTRACT_DIR"/system_dlkm.img \
        --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b \
        --partition product_b:readonly:0:qti_dynamic_partitions_b \
        --partition system_b:readonly:0:qti_dynamic_partitions_b \
        --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
        --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b \
        --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b \
        --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
        --partition odm_b:readonly:0:qti_dynamic_partitions_b \
        --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 -F --output ./output/super.img

# 二次打包Super.img
./tools/binary/zstd -9 -f ./output/super.img -o ./output/super.zst --rm

# 打包zip文件
7z a ./zip/fuxi-ota_full-OS2.0.212.0.VMCCNXM-user-15.0.zip ./output/*
MD5_HASH=$(md5sum "./zip/fuxi-ota_full-OS2.0.212.0.VMCCNXM-user-15.0.zip" | awk '{ print $1 }' | cut -c 1-10)
mv "./zip/fuxi-ota_full-OS2.0.212.0.VMCCNXM-user-15.0.zip" "./zip/fuxi-ota_full-OS2.0.212.0.VMCCNXM-user-15.0-$MD5_HASH.zip"

rm -rf "Migration Package" "Stock Package" output