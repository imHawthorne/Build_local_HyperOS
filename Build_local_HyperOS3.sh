#!/bin/bash

# ======================== 函数定义：通用工具 ========================
error_exit() {
    echo -e "\n 错误：$1"
    exit 1
}

check_file_exists() {
    if [ ! -f "$1" ]; then
        error_exit "文件不存在：$1"
    fi
}

create_dir() {
    if [ ! -d "$1" ]; then
        echo -e " 创建目录：$1"
        mkdir -p "$1" || error_exit "无法创建目录 $1"
    fi
}


# ======================== 主流程：处理 Stock 包 ========================
process_stock_package() {
    echo -e "\n===== 开始处理 Stock 固件包 ====="
    
    # 1. 获取用户输入：ZIP 文件路径（保留默认值，方便快速测试）
    read -p "请输入 Stock ZIP 文件路径（默认：./downloads/nuwa-ota_full-OS2.0.215.0.VMBCNXM-user-15.0-03badd90e8.zip）: " STOCK_ZIP
    STOCK_ZIP=${STOCK_ZIP:-"./downloads/nuwa-ota_full-OS2.0.215.0.VMBCNXM-user-15.0-03badd90e8.zip"}
    check_file_exists "$STOCK_ZIP"

    # 2. 获取用户输入：提取目录（**移除默认值，强制手动输入**）
    read -p "请输入 Stock 提取目录（不可留空）: " STOCK_EXTRACT_DIR
    [ -z "$STOCK_EXTRACT_DIR" ] && error_exit "提取目录不可为空，请重新运行并输入有效路径"
    create_dir "$STOCK_EXTRACT_DIR"

    # 3. 解压 payload.bin
    echo -e "\n 正在从 Stock ZIP 提取 payload..."
    ./tools/binary/payload_extract -i "$STOCK_ZIP" -t zip -o "$STOCK_EXTRACT_DIR" -x \
        || error_exit "payload_extract 失败（Stock 包）"

    # 4. 提取镜像文件
    STOCK_IMAGES=(
        "odm.img" "product.img" "system.img" "system_ext.img" 
        "system_dlkm.img" "vendor.img" "vendor_dlkm.img"
    )
    echo -e "\n Stock 镜像列表：${STOCK_IMAGES[*]}"
    for image in "${STOCK_IMAGES[@]}"; do
        IMAGE_PATH="$STOCK_EXTRACT_DIR/$image"
        check_file_exists "$IMAGE_PATH"
        
        echo -e "\n 提取 $image..."
        ./tools/binary/extract.erofs -i "$IMAGE_PATH" -o "$STOCK_EXTRACT_DIR" -x \
            || error_exit "提取 $image 失败（Stock 包）"
    done

    # 5. 清理原始镜像文件
    echo -e "\n 清理 Stock 原始镜像文件..."
    rm -f "${STOCK_IMAGES[@]/#/$STOCK_EXTRACT_DIR/}"
}


# ======================== 主流程：处理 Migration 包 ========================
process_migration_package() {
    echo -e "\n\n===== 开始处理 Migration 固件包 ====="
    
    # 1. 获取用户输入：ZIP 文件路径（保留默认值）
    read -p "请输入 Migration ZIP 文件路径（默认：./downloads/popsicle-ota_full-OS3.0.9.0.WPBCNXM-user-16.0-cd841de17d.zip）: " MIGRATION_ZIP
    MIGRATION_ZIP=${MIGRATION_ZIP:-"./downloads/popsicle-ota_full-OS3.0.9.0.WPBCNXM-user-16.0-cd841de17d.zip"}
    check_file_exists "$MIGRATION_ZIP"

    # 2. 获取用户输入：提取目录（**移除默认值，强制手动输入**）
    read -p "请输入 Migration 提取目录（不可留空）: " MIGRATION_EXTRACT_DIR
    [ -z "$MIGRATION_EXTRACT_DIR" ] && error_exit "提取目录不可为空，请重新运行并输入有效路径"
    create_dir "$MIGRATION_EXTRACT_DIR"

    # 3. 解压 payload.bin 指定 image
    echo -e "\n 正在从 Migration ZIP 提取 payload 指定 image..."
    ./tools/binary/payload_extract -i "$MIGRATION_ZIP" -t zip -o "$MIGRATION_EXTRACT_DIR" -X product,system,system_ext,mi_ext -T0 \
        || error_exit "payload_extract 失败（Migration 包）"

    # 4. 提取镜像文件
    MIGRATION_IMAGES=("mi_ext.img" "product.img" "system.img" "system_ext.img")
    echo -e "\n Migration 镜像列表：${MIGRATION_IMAGES[*]}"
    for image in "${MIGRATION_IMAGES[@]}"; do
        IMAGE_PATH="$MIGRATION_EXTRACT_DIR/$image"
        check_file_exists "$IMAGE_PATH"
        
        echo -e "\n 提取 $image..."
        ./tools/binary/extract.erofs -i "$IMAGE_PATH" -o "$MIGRATION_EXTRACT_DIR" -x \
            || error_exit "提取 $image 失败（Migration 包）"
    done
}

# ======================== 入口执行 ========================
echo -e "===== 镜像提取工具 ====="

# 检查依赖工具
check_file_exists "./tools/binary/payload_extract"
check_file_exists "./tools/binary/extract.erofs"

# 处理固件包
process_stock_package
process_migration_package

echo -e "\n\n 所有操作完成！提取结果："
echo -e " Stock 包内容：$STOCK_EXTRACT_DIR"
echo -e " Migration 包内容：$MIGRATION_EXTRACT_DIR"


# ======================== 禁用 AVB 2.0 校验 ========================

echo -e "\n\n===== 禁用 AVB 2.0 校验 ====="

# 要删除的内容
PATTERN1=",avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey:/avb/t-gsi.avbpubkey"
PATTERN2="avb=vbmeta_system,"
PATTERN3="avb=vbmeta,"

# 转义特殊字符
PATTERN1=$(printf '%s\n' "$PATTERN1" | sed 's/[\/&]/\\&/g')
PATTERN2=$(printf '%s\n' "$PATTERN2" | sed 's/[\/&]/\\&/g')
PATTERN3=$(printf '%s\n' "$PATTERN3" | sed 's/[\/&]/\\&/g')

# 检查环境变量是否定义
if [ -z "$STOCK_EXTRACT_DIR" ]; then
    echo "错误：未设置环境变量 STOCK_EXTRACT_DIR"
    echo "请先执行：export STOCK_EXTRACT_DIR=/path/to/你的解压目录"
    exit 1
fi

# 定义目标文件路径
FSTAB_PATH="$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"

# 修改 fstab.qcom 文件
if [ -f "$FSTAB_PATH" ]; then
    echo "正在修改 $FSTAB_PATH..."

    # 使用 sed 删除指定内容
    sed -i "s#$PATTERN1##g" "$FSTAB_PATH"
    sed -i "s#$PATTERN2##g" "$FSTAB_PATH"
    sed -i "s#$PATTERN3##g" "$FSTAB_PATH"

    echo "修改完成！"
else
    echo "未找到文件：$FSTAB_PATH"
    exit 1
fi

echo -e "\n\n===== 禁用 vendor_boot 的 AVB 2.0校验 & 添加狂暴引擎支持 ====="

# 处理vendor_boot
mkdir vendor_boot
cp -f "$STOCK_EXTRACT_DIR/vendor_boot.img" ./vendor_boot
cp -f ./tools/binary/magiskboot ./vendor_boot
cp -f ./common_files/perfmgr.ko ./vendor_boot

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
mv -f ./perfmgr.ko ./ramdisk/lib/modules/

# 插入modules.dep部分
sed -i '/\/lib\/modules\/msm_gpi.ko:/a \/lib\/modules\/perfmgr.ko: \/lib\/modules\/qcom-dcvs.ko \/lib\/modules\/dcvs_fp.ko \/lib\/modules\/qcom_rpmh.ko \/lib\/modules\/cmd-db.ko \/lib\/modules\/qcom_ipc_logging.ko \/lib\/modules\/minidump.ko \/lib\/modules\/smem.ko \/lib\/modules\/gh_rm_drv.ko \/lib\/modules\/gh_dbl.ko \/lib\/modules\/gh_msgq.ko \/lib\/modules\/gh_arm_drv.ko' ./ramdisk/lib/modules/modules.dep

# 插入modules.load.recovery部分
sed -i '/migt\.ko/a perfmgr.ko' ./ramdisk/lib/modules/modules.load.recovery

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
nocompflag="-n"

mkdir out
./magiskboot repack $nocompflag vendor_boot.img ./out/vendor_boot.img

cd ..
cp -f ./vendor_boot/out/vendor_boot.img "$STOCK_EXTRACT_DIR"/vendor_boot.img
rm -rf ./vendor_boot

# 禁用 Xiaomi 的全局 vulkan 渲染
echo -e "\n\n===== 禁用 Xiaomi 的全局 vulkan 渲染 ====="
sed -i 's/persist.sys.enhance_vkpipelinecache.enable=true/# persist.sys.enhance_vkpipelinecache.enable=true/g' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 添加底包的"device_features"文件
echo "\n\n===== 添加底包的"device_features"文件 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"
cp -rf "$STOCK_EXTRACT_DIR/product/etc/device_features/" "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"

# 屏蔽系统更新检测
echo "\n\n===== 屏蔽系统更新检测 ====="
sed -i 's/<bool name="support_ota_validate">true<\/bool>/<bool name="support_ota_validate">false<\/bool>/' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/nuwa.xml"

# 解锁 Widevine L1 指纹支付证书在线更新
echo "\n\n===== 解锁 widevine L1 指纹支付证书在线更新 ====="
sed -i 's/<integer name="support_widevine_l1">1<\/integer>/<integer name="support_widevine_l1">2<\/integer>/' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/nuwa.xml"

# 添加来自于"Xiaomi 15 Ultra"的修改版相机 6.0.000250.0
echo "\n\n===== 添加来自于"Xiaomi 15 Ultra"的修改版相机 6.0.000250.0 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/priv-app/MiuiCamera/"
7z x ./common_files/MiuiCamera.7z -o"$MIGRATION_EXTRACT_DIR/product/priv-app/MiuiCamera"

# 替换底包的"MiuiCit"应用
echo "\n\n===== 替换底包的"MiuiCit"应用 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/MiuiCit/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/MiuiCit/" "$MIGRATION_EXTRACT_DIR/product/app/MiuiCit/"

# 替换底包的"小爱翻译"应用
echo "\n\n===== 替换底包的"小爱翻译"应用 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/AiasstVision/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/AiasstVision/" "$MIGRATION_EXTRACT_DIR/product/app/AiasstVision/"

# 修复"注释感知"功能不工作
echo "\n\n===== 修复"注释感知"功能不工作 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/MiAONServiceW/"
cp -rf "$STOCK_EXTRACT_DIR/product/app/MiAONService/" "$MIGRATION_EXTRACT_DIR/product/app/MiAONService/"

# 恢复官方的特有壁纸
echo "\n\n===== 恢复官方的特有壁纸 ====="
SRC_BASE="$STOCK_EXTRACT_DIR/product/media/wallpaper"
DST_BASE="$MIGRATION_EXTRACT_DIR/product/media/wallpaper"

cp -rf "${SRC_BASE}/wallpaper_group/06_GlassyLight/" "${DST_BASE}/wallpaper_group/06_GlassyLight/"
cp -rf "${SRC_BASE}/wallpaper_group/07_ShadowGeometry/" "${DST_BASE}/wallpaper_group/07_ShadowGeometry/"

# 修复"NFC"功能不工作
echo "\n\n===== 修复"NFC"功能不工作 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/pangu/system/app/XMNfcNci"
7z x ./common_files/NQNfcNci.7z -o"$MIGRATION_EXTRACT_DIR/product/pangu/system/app/"

# 修复开机动画分辨率
echo "\n===== 修复开机动画分辨率 ====="
cp -f "$STOCK_EXTRACT_DIR"/product/media/bootanimation.zip "$MIGRATION_EXTRACT_DIR"/product/media

# 修复基带不工作
echo "\n\n===== 修复基带未知 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/app/LyraSdkApp"
7z x ./common_files/LyraSdkApp.7z -o"$MIGRATION_EXTRACT_DIR/product/app/LyraSdkApp/" -y

# 去除国区谷歌商店限制
echo "\n\n===== 去除国区谷歌商店限制 ====="
sed -i -e '/<feature name="cn.google.services" \/>/d' \
    -e '/<feature name="com.google.android.feature.services_updater" \/>/d' "$MIGRATION_EXTRACT_DIR"/product/etc/permissions/cn.google.services.xml

# 解锁新版息屏显示样式
echo "\n\n===== 解锁新版息屏显示样式 ====="
sed -i '/<bool name="is_aod_need_grayscale">false<\/bool>/a \
    <!--whether the device supports aod fullscreen mode--> \
    <bool name="support_aod_fullscreen">true</bool> \
    <!-- The fps of aon_screen_off--> \
    <integer name="aon_screen_off_fps">0</integer>' "$MIGRATION_EXTRACT_DIR"/product/etc/device_features/nuwa.xml
sed -i ''"$(sed -n '/ro.vendor.display.primary_idle_refresh_rate/=' "$STOCK_EXTRACT_DIR/odm/etc/build.prop")"'a ro.vendor.mi_sf.aod_mode_ddic_refresh_rate=1' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 解锁节律护眼模
echo "\n\n=====解锁节律护眼支持 ====="
sed -i '/<bool name="config_sunlight_mode_available">true<\/bool>/a \
    <!-- default rhythmic eyecare mode --> \
    <integer name="default_eyecare_mode">2</integer>' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/nuwa.xml"

# 解锁24-30-40隐藏屏幕刷新率
echo "\n\n===== 解锁24-30-40hz隐藏刷新率支持 ====="
sed -i '/<integer-array name="fpsList">/,/<\/integer-array>/{
    /<item>60<\/item>/a\
        <item>40</item>\
        <item>30</item>\
        <item>24</item>
}' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/nuwa.xml"

# 解锁狂暴引擎
echo "\n\n===== 解锁"狂暴引擎"第二部分 ====="
sed -i '/<!-- BSP BEGIN -->/a \
    <!-- Whether support WildBoost --> \
    <bool name="support_wild_boost">true</bool> \
    <!-- Whether support WildBoost in Battery & Performance --> \
    <bool name="support_wild_boost_bat_perf">true</bool>' "$MIGRATION_EXTRACT_DIR/product/etc/device_features/nuwa.xml"

# 插入狂暴引擎需要的依赖
cp -f ./common_files/perfmgr.ko "$STOCK_EXTRACT_DIR/vendor_dlkm/lib/modules/"
sed -i '/\/vendor\/lib\/modules\/msm_gpi\.ko:/a \/vendor\/lib\/modules\/perfmgr.ko:' "$STOCK_EXTRACT_DIR/vendor_dlkm/lib/modules/modules.dep"
sed -i '/migt\.ko/a perfmgr.ko' "$STOCK_EXTRACT_DIR/vendor_dlkm/lib/modules/modules.load"

# magiskboot hexpatch处理部分
MAGISKBOOT="./tools/binary/magiskboot"
TARGET_DIR="$MIGRATION_EXTRACT_DIR/system_ext"
LIB_FILES=(
    "lib/libmigui.so"       # 32位库文件
    "lib64/libmigui.so"     # 64位库文件
)
# 替换规则：原始十六进制字符串 → 目标十六进制字符串（按顺序对应）
REPLACEMENTS=(
    "726F2E70726F647563742E646576696365 726F2E656173746D6F642E646576696365"
    "726F2E70726F647563742E70726F647563742E6E616D65 726F2E656173746D6F642E70726F647563742E6E616D65"
)

# 循环处理每个库文件和替换规则
for lib in "${LIB_FILES[@]}"; do
    lib_path="${TARGET_DIR}/${lib}"
    echo "Processing ${lib_path}..."  # 可选：打印当前处理的文件，方便调试
    for rule in "${REPLACEMENTS[@]}"; do
        # 拆分规则为原始字符串和目标字符串（按空格分割）
        orig_hex=$(echo "$rule" | cut -d' ' -f1)
        target_hex=$(echo "$rule" | cut -d' ' -f2)
        # 执行hexpatch命令
        "${MAGISKBOOT}" hexpatch "${lib_path}" "${orig_hex}" "${target_hex}"
    done
done

sed -i '$a \
# Eastmod FEAS Model \
ro.eastmod.device=vermeer \
ro.eastmod.product.name=vermeer' "$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"

cp -f ./common_files/default_cloud.json "$STOCK_EXTRACT_DIR/odm/etc/"

# 添加屏幕配置文件
echo "\n\n===== 添加屏幕配置文件 ====="
rm -rf "$MIGRATION_EXTRACT_DIR"/product/etc/displayconfig
cp -rf "$STOCK_EXTRACT_DIR"/product/etc/displayconfig "$MIGRATION_EXTRACT_DIR"/product/etc

# 修复分辨率大小
echo "\n\n===== 修复分辨率大小 ====="
sed -i 's/ro.sf.lcd_density=[^*]*/ro.sf.lcd_density=600/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/ro.sf.lcd_sec_density=[^*]*/ro.sf.lcd_sec_density=600/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop
sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=600/' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 禁用不可卸载 2.0
echo "\n\n===== 禁用不可卸载 2.0 ====="
sed -i 's/ro.miui.support.system.app.uninstall.v2=true/# ro.miui.support.system.app.uninstall.v2=true/g' "$MIGRATION_EXTRACT_DIR"/mi_ext/etc/build.prop

# ==============================================
# 需删除的套壳应用目录列表（每行一个路径，便于检查和增删）
TARGET_DIRS=(
    "${MIGRATION_EXTRACT_DIR}/product/app/BSGameCenter"
    "${MIGRATION_EXTRACT_DIR}/product/app/subscreencenter"
    "${MIGRATION_EXTRACT_DIR}/product/data-app/MIUIThemeStore"
    "${MIGRATION_EXTRACT_DIR}/product/data-app/MIUISecurityManager"
    "${MIGRATION_EXTRACT_DIR}/product/data-app/VoiceAssistProxy"
    "${MIGRATION_EXTRACT_DIR}/product/media/bootanimation-back.zip"
    "${MIGRATION_EXTRACT_DIR}/product/media/rearscreen"
)

# ==============================================
# 执行区：批量删除目录并输出清晰日志
# ==============================================
echo -e "\n\n===== 清除套壳应用 & 无用组件 ====="  # 使用-e支持换行符转义，输出更整洁

# 检查环境变量是否存在（避免路径解析为空）
if [ -z "${MIGRATION_EXTRACT_DIR}" ]; then
    echo "错误：环境变量 MIGRATION_EXTRACT_DIR 未设置！"
    exit 1  # 关键变量缺失时终止执行，避免误删
fi

# 遍历目录列表，逐个处理
for dir_path in "${TARGET_DIRS[@]}"; do
    if [ -d "${dir_path}" ]; then  # 确认目录存在且为有效目录
        echo "→ 删除成功：${dir_path}"
        rm -rf "${dir_path}"  # 强制删除（-rf避免交互确认，适合脚本自动化）
    else
        echo "→ 跳过（不存在）：${dir_path}"  # 统一前缀，日志更易读
    fi
done

# 精简小米的一些垃圾推广应用
APPS_TO_REMOVE=(
    "BaiduIME"          "iFlytekIME"        "MIGalleryLockscreen"
    "MIService"         "MIUIEmail"         "MIUIHuanji"
    "MiuiScanner"       "OS2VipAccount"     "SmartHome"
    "XMRemoteController" "MiRadio"          "MiShop"
    "MIUIGameCenter"    "MIUINewHome_Removable" "MIUIVideo"
    "MIUIYoupin"        "Health"            "MIUIDuokanReader"
)
# 搜索根目录（仅定义一次，后续修改更方便）
SEARCH_ROOT="${MIGRATION_EXTRACT_DIR}/product/data-app/"

# ==============================================
# 执行区：批量处理应用精简
# ==============================================
echo -e "\n\n===== 精简小米推广应用 ====="  # 使用-e支持换行符转义

# 检查搜索目录是否存在（避免find命令报错）
if [ ! -d "${SEARCH_ROOT}" ]; then
    echo "错误：搜索目录不存在 → ${SEARCH_ROOT}"
    exit 1  # 目录不存在时终止执行，避免无效循环
fi

# 遍历应用列表，逐个处理
for app_keyword in "${APPS_TO_REMOVE[@]}"; do
    # 使用find精确搜索目录（-maxdepth 1限制仅搜索一级子目录，提升效率）
    app_dir=$(find "${SEARCH_ROOT}" -maxdepth 1 -type d -iname "*${app_keyword}*")
    
    if [ -n "${app_dir}" ]; then  # 目录存在且非空
        echo "→ 精简成功：${app_dir}"
        rm -rf "${app_dir}"  # 强制删除目录（-rf避免交互确认）
    else
        echo "→ 未找到：${app_keyword}"  # 统一前缀，输出更整洁
    fi
done

echo -e "\n===== 应用精简完成 ====="  # 输出结束标识

# 将内置浏览器改为可卸载应用
echo "\n\n===== 将内置浏览器改为可卸载应用 ====="
mv "$MIGRATION_EXTRACT_DIR"/product/priv-app/MIUIBrowser "$MIGRATION_EXTRACT_DIR"/product/data-app/MIUIBrowser

# 添加 apex vndk 支持
echo "\n\n===== 添加"apex vndk33"支持 ====="
cp -f ./common_files/com.android.vndk.v33.apex "$MIGRATION_EXTRACT_DIR"/system_ext/apex

# 修复开机出现提示设备内部错误
echo "\n\n===== 修复开机出现提示设备内部错误 ====="
sed -i "/<\/manifest>/i \    <vendor-ndk>\n        <version>33<\/version>\n    <\/vendor-ndk>" "$MIGRATION_EXTRACT_DIR"/system_ext/etc/vintf/manifest.xml

# 禁用cust的erofs文件系统支持
BUILD_PROP_PATH="${MIGRATION_EXTRACT_DIR}/product/etc/build.prop"

# 需注释的属性列表（每行一个，支持正则表达式，避免重复）
PROPERTIES_TO_COMMENT=(
    "ro\.miui\.cust_erofs"
    "ro\.miui\.preinstall_to_data"
    "ro\.miui\.cust_img_path"
    "ro\.miui\.product_to_cust"
)

# ==============================================
# 执行区：检查依赖并批量注释属性
# ==============================================
echo -e "\n\n===== 禁用cust的erofs文件系统支持 ====="

# 检查关键依赖是否满足
if [ -z "${MIGRATION_EXTRACT_DIR}" ]; then
    echo "错误：环境变量 MIGRATION_EXTRACT_DIR 未设置！"
    exit 1  # 终止执行，避免路径错误
fi

if [ ! -f "${BUILD_PROP_PATH}" ]; then
    echo "错误：目标文件不存在 → ${BUILD_PROP_PATH}"
    exit 1  # 文件不存在时终止，避免无效操作
fi

# 遍历属性列表，逐个添加注释（#）
for prop_pattern in "${PROPERTIES_TO_COMMENT[@]}"; do
    # 使用sed注释以目标属性开头的行（仅匹配行首，避免误改）
    # -i.bak：保留备份文件（防止意外修改后无法恢复）
    sed -i.bak -E "s/^(${prop_pattern})/# \1/" "${BUILD_PROP_PATH}"
    
    # 检查是否实际修改了文件（对比备份文件）
    if ! diff -q "${BUILD_PROP_PATH}" "${BUILD_PROP_PATH}.bak" >/dev/null; then
        echo "→ 已注释：${prop_pattern}"
    else
        echo "→ 跳过（未找到）：${prop_pattern}"
    fi
    
    # 删除临时备份文件（如需保留备份可注释此行）
    rm -f "${BUILD_PROP_PATH}.bak"
done

echo -e "\n===== erofs文件系统支持禁用完成 ====="

# 禁用tango转译器
# 目标文件路径（变量化，便于修改和复用）
TARGET_FILE="${MIGRATION_EXTRACT_DIR}/system/system/build.prop"

# 需注释的tango相关属性列表（去重+集中管理）
TANGO_PROPERTIES=(
    "tango\.enabled"
    "tango\.debug"
    "tango\.pretrans\.max_size"
    "tango\.pretrans_on_install"
    "tango\.pretrans\.debug"
    "tango\.pretrans\.lib"
    "tango\.pretrans\.apk"
)

# ==============================================
# 执行区：安全检查+批量注释
# ==============================================
echo -e "\n\n===== 禁用tango转译器 ====="

# 检查环境变量是否设置
if [ -z "${MIGRATION_EXTRACT_DIR}" ]; then
    echo "错误：环境变量 MIGRATION_EXTRACT_DIR 未设置！"
    exit 1
fi

# 检查目标文件是否存在
if [ ! -f "${TARGET_FILE}" ]; then
    echo "错误：目标文件不存在 → ${TARGET_FILE}"
    exit 1
fi

# 遍历属性列表，逐个注释并输出状态
for prop in "${TANGO_PROPERTIES[@]}"; do
    # 使用sed注释以目标属性开头的行（仅匹配行首，避免误改）
    # -i.bak：生成备份文件（防止意外修改后无法恢复）
    sed -i.bak -E "s/^(${prop})/# \1/" "${TARGET_FILE}"
    
    # 检查是否实际修改（对比备份文件）
    if ! diff -q "${TARGET_FILE}" "${TARGET_FILE}.bak" >/dev/null; then
        echo "→ 已注释：${prop}"
    else
        echo "→ 跳过（未找到）：${prop}"
    fi
    
    # 删除临时备份（如需保留备份可注释此行）
    rm -f "${TARGET_FILE}.bak"
done

echo -e "\n===== tango转译器禁用完成 ====="

# 解锁MiuiCamera HLG支持
echo "\n\n===== 解锁MiuiCamera HLG支持 ====="
sed -i '$a \
# Enable MiuiCamera HLG Support \
persist.camera.settings.hlg=true' "$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"

# 解锁LHDC自适应采样率
echo "\n\n===== 解锁LHDC自适应采样率 ====="
sed -i '/^persist.vendor.bt.aac_vbr_frm_ctl.enabled=true/a persist.vendor.bt.a2dp.samplerate.supported=true' "$STOCK_EXTRACT_DIR/vendor/build.prop"

# 修复蓝牙耳机沉浸声
echo "\n\n===== 修复蓝牙耳机沉浸声 ====="
sed -i '/^ro\.audio\.spatializer_enabled=true/a ro\.audio\.stereo_spatialization_enabled=true' "$STOCK_EXTRACT_DIR/vendor/build.prop"

# 解锁控制中心透明效果 & 修复小米超级岛
echo "\n\n===== 解锁控制中心透明效果 & 该死的小米超级岛 ====="
cp -f ./common_files/EastXiaomiSystemUIOverlay.apk "$MIGRATION_EXTRACT_DIR"/product/overlay

# 替换底包的Overlay
echo "\n\n===== 替换底包的Overlay ====="
APKS=(
    "DevicesAndroidOverlay.apk"
    "DevicesOverlay.apk"
    "MiuiFrameworkResOverlay.apk"
    "SettingsRroDeviceHideStatusBarOverlay.apk"
    "SettingsRroDeviceTypeOverlay.apk"
    "MiuiFrameworkTelephonyResOverlay.apk"
)

for apk in "${APKS[@]}"; do
    mv -f "${STOCK_EXTRACT_DIR}/product/overlay/${apk}" "${MIGRATION_EXTRACT_DIR}/product/overlay/"
done

APKS1=(
    "AospFrameworkResOverlay.apk"
    "AospWifiResOverlay.apk"
)
for apk1 in "${APKS1[@]}"; do
    cp -f "./common_files/${apk1}" "${MIGRATION_EXTRACT_DIR}/product/overlay/"
done

# 去除无用的屏幕刘海切换
MOD_DIR="./mod"
OVERLAY_NAME="SettingsRroDeviceTypeOverlay"
OVERLAY_APK="${OVERLAY_NAME}.apk"
APK_EDITOR="java -jar ./tools/jar/APKEditor.jar"
TARGET_APK_PATH="${MIGRATION_EXTRACT_DIR}/product/overlay/${OVERLAY_APK}"
BOOLS_XML="${MOD_DIR}/${OVERLAY_NAME}/resources/package_1/res/values/bools.xml"
PUBLIC_XML="${MOD_DIR}/${OVERLAY_NAME}/resources/package_1/res/values/public.xml"

# ==============================================
# 执行区：分步处理APK文件
# ==============================================
echo -e "\n===== 开始处理屏幕刘海配置 ====="

# 1. 环境检查
if [ ! -f "${TARGET_APK_PATH}" ]; then
    echo "错误：目标APK不存在 → ${TARGET_APK_PATH}"
    exit 1
fi
if [ ! -f "$(echo "${APK_EDITOR}" | awk '{print $3}')" ]; then
    echo "错误：APKEditor.jar不存在，请检查工具路径！"
    exit 1
fi

# 2. 创建工作目录并移动APK
echo "→ 准备工作目录..."
mkdir -p "${MOD_DIR}"
mv -f "${TARGET_APK_PATH}" "${MOD_DIR}/" || { echo "移动APK失败！"; exit 1; }

# 3. 反编译APK（静默模式）
echo "→ 反编译APK..."
${APK_EDITOR} d -f -i "${MOD_DIR}/${OVERLAY_APK}" -o "${MOD_DIR}/${OVERLAY_NAME}" 2>&1 1>/dev/null || {
    echo "反编译失败！"
    exit 1
}

# 4. 修改bools.xml（添加禁用配置）
echo "→ 修改bools.xml..."
if grep -q 'config_show_softap_wifi6' "${BOOLS_XML}"; then
    # 在目标行后插入禁用配置
    sed -i '/<bool name="config_show_softap_wifi6">true<\/bool>/a \
  <bool name="config_device_support_force_black">false</bool>' "${BOOLS_XML}"
else
    echo "警告：未找到插入点，直接追加禁用配置..."
    sed -i '$a \
  <bool name="config_device_support_force_black">false</bool>' "${BOOLS_XML}"
fi

# 5. 动态生成public.xml的ID（核心优化点）
echo "→ 动态生成资源ID..."
# 提取现有bool类型ID的最大值（格式：0x7f01xxxx）
max_id=$(grep -E 'type="bool" name=' "${PUBLIC_XML}" | \
         sed -n 's/.*id="0x\([0-9a-f]\+\)".*/\1/p' | \
         sort -nr | head -1)

if [ -z "${max_id}" ]; then
    # 无现有bool ID时，使用基础ID（0x7f010000）
    new_id="7f010000"
else
    # 新ID = 最大ID + 1（十六进制计算）
    new_id=$(printf "%.8x" $((16#${max_id} + 1)))
fi

# 插入新的public声明（保留原格式对齐）
if grep -q 'config_global_support_slm' "${PUBLIC_XML}"; then
    sed -i "/<public id=\"0x7f010000\" type=\"bool\" name=\"config_global_support_slm\" \/>/a \
  <public id=\"0x${new_id}\" type=\"bool\" name=\"config_device_support_force_black\" \/> " "${PUBLIC_XML}"
else
    echo "警告：未找到SLM配置，追加新ID到public.xml末尾..."
    sed -i '$a \
  <public id="0x${new_id}" type="bool" name="config_device_support_force_black" \/> ' "${PUBLIC_XML}"
fi
echo "→ 生成的新资源ID：0x${new_id}"

# 6. 重新编译APK
echo "→ 重新编译APK..."
${APK_EDITOR} b -f -i "${MOD_DIR}/${OVERLAY_NAME}" -o "${MOD_DIR}/${OVERLAY_NAME}_modified.apk" 2>&1 1>/dev/null || {
    echo "编译失败！"
    exit 1
}

# 7. 替换原文件并清理
echo "→ 替换目标文件..."
sudo mv -f "${MOD_DIR}/${OVERLAY_NAME}_modified.apk" "${TARGET_APK_PATH}" || {
    echo "替换APK失败！"
    exit 1
}
sudo rm -rf "${MOD_DIR}"

echo -e "\n===== 屏幕刘海配置处理完成 ====="

# 修复息屏显示
MOD_NAME="DevicesAndroidOverlay"
MOD_DIR="./mod"
OVERLAY_APK="${MOD_NAME}.apk"
TARGET_APK_PATH="${MIGRATION_EXTRACT_DIR}/product/overlay/${OVERLAY_APK}"
APK_EDITOR="java -jar ./tools/jar/APKEditor.jar"
STRINGS_XML="${MOD_DIR}/${MOD_NAME}/resources/package_1/res/values/strings.xml"
OLD_DOZE_COMPONENT='com.android.systemui/com.android.systemui.doze.DozeService'
NEW_DOZE_COMPONENT='com.android.systemui/com.android.keyguard.doze.MiuiDozeService'

# ==============================================
# 执行区：分步处理逻辑
# ==============================================
echo -e "\n===== 开始修复息屏显示 ====="

# 1. 环境预检查（关键依赖验证）
echo "→ 检查环境依赖..."
[ -z "${MIGRATION_EXTRACT_DIR}" ] && { echo "错误：MIGRATION_EXTRACT_DIR变量未定义！"; exit 1; }
[ ! -f "${TARGET_APK_PATH}" ] && { echo "错误：目标APK不存在 → ${TARGET_APK_PATH}"; exit 1; }
[ ! -f "$(echo "${APK_EDITOR}" | awk '{print $3}')" ] && { echo "错误：APKEditor.jar不存在！"; exit 1; }

# 2. 准备工作目录
echo "→ 初始化工作目录..."
mkdir -p "${MOD_DIR}" || { echo "创建目录失败！"; exit 1; }
cp -f "${TARGET_APK_PATH}" "${MOD_DIR}/" || { echo "复制APK失败！"; exit 1; }

# 3. 反编译APK（带错误捕获）
echo "→ 反编译APK文件..."
if ! ${APK_EDITOR} d -f -i "${MOD_DIR}/${OVERLAY_APK}" -o "${MOD_DIR}/${MOD_NAME}" 2>/dev/null; then
    echo "错误：反编译APK失败！"
    exit 1
fi

# 4. 修改strings.xml（精准替换）
echo "→ 修改息屏服务配置..."
sed -i "s#${OLD_DOZE_COMPONENT}#${NEW_DOZE_COMPONENT}#g" "${STRINGS_XML}"


# 5. 重新编译APK
echo "→ 重新编译修改后的APK..."
if ! ${APK_EDITOR} b -f -i "${MOD_DIR}/${MOD_NAME}" -o "${MOD_DIR}/${MOD_NAME}_modified.apk" 2>/dev/null; then
    echo "错误：APK编译失败！"
    exit 1
fi

# 6. 替换目标文件并清理
echo "→ 应用修改并清理..."
sudo cp -f "${MOD_DIR}/${MOD_NAME}_modified.apk" "${TARGET_APK_PATH}" || { echo "替换APK失败！"; exit 1; }
sudo rm -rf "${MOD_DIR}"  # 强制清理临时文件

echo -e "\n===== 息屏显示修复完成 ====="

# 恢复静止刷新率下限为1Hz
echo "\n\n===== 恢复静止刷新率下限为1Hz ====="
# 检查STOCK_EXTRACT_DIR变量是否定义
if [ -z "$STOCK_EXTRACT_DIR" ]; then
  echo "错误：STOCK_EXTRACT_DIR变量未定义，请先设置该变量"
  exit 1
fi

# 目标文件路径
TARGET_FILE="$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 检查目标文件是否存在
if [ ! -f "$TARGET_FILE" ]; then
  echo "错误：目标文件不存在 → $TARGET_FILE"
  exit 1
fi

# 根据STOCK_EXTRACT_DIR值执行不同替换
case "$STOCK_EXTRACT_DIR" in
  *nuwa*)  # 匹配包含"nuwa"的路径（如/xxx/nuwa/xxx）
    echo "检测到STOCK_EXTRACT_DIR包含nuwa，执行替换：60,1:492"
    sed -i.bak 's/ro.vendor.display.primary_idle_refresh_rate=[^*]*/ro.vendor.display.primary_idle_refresh_rate=60,1:492/' "$TARGET_FILE"
    ;;
  *ishtar*)  # 匹配包含"ishtar"的路径
    echo "检测到STOCK_EXTRACT_DIR包含ishtar，执行替换：60,1:528"
    sed -i.bak 's/ro.vendor.display.primary_idle_refresh_rate=[^*]*/ro.vendor.display.primary_idle_refresh_rate=60,1:528/' "$TARGET_FILE"
    ;;
  *)  # 不匹配时提示
    echo "警告：STOCK_EXTRACT_DIR既不是nuwa也不是ishtar，未执行替换"
    exit 0  # 非错误，仅退出
    ;;
esac

# 验证替换结果
if grep -q "ro.vendor.display.primary_idle_refresh_rate=" "$TARGET_FILE"; then
  echo "替换完成，当前值："
  grep "ro.vendor.display.primary_idle_refresh_rate=" "$TARGET_FILE"
  # 可选：确认无误后删除备份文件（取消注释下行）
  rm -f "${TARGET_FILE}.bak"
else
  echo "替换失败！已恢复原文件"
  mv -f "${TARGET_FILE}.bak" "$TARGET_FILE"
  exit 1
fi

# 启用vulkan渲染
sed -i 's/ro.hwui.use_vulkan=.*/debug.renderengine.vulkan=true\ndebug.hwui.renderer=skiavk\nro.hwui.use_vulkan=true\ndebug.renderengine.backend=skiavkthreaded\ndebug.stagefright.renderengine.backend=threaded/' "./$STOCK_EXTRACT_DIR/vendor/build.prop"

# 添加uwb支持
echo "添加uwb支持"
cp -rf ./common_files/android.hardware.uwb.xml "$STOCK_EXTRACT_DIR/odm/etc/permissions"

# 修复小米的贴贴分享
sed -i ''"$(sed -n '/ro.vendor.nfc.dispatch_optim/=' "$STOCK_EXTRACT_DIR/odm/etc/build.prop")"'a ro.vendor.nfc.mitouch=1' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 解锁新版nfc读写勿扰2.0
echo "解锁新版nfc读写勿扰2.0"
sed -i 's/ro.vendor.nfc.dispatch_optim=[^*]*/ro.vendor.nfc.dispatch_optim=2/' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# 启用 APTX Adaptive 2.2 支持
echo "启用 APTX Adaptive 2.2 支持"
sed -i '/^persist.vendor.qcom.bluetooth.aptxadaptiver2_1_support=true/a persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$STOCK_EXTRACT_DIR/vendor/build.prop"

# 跳过Bluetooth LEAudio Whitelist
echo "跳过Bluetooth LEAudio Whitelist"
sed -i '/^persist.bluetooth.a2dp_offload.cap=sbc-aac-aptx-aptxhd-ldac-lhdc/a persist.bluetooth.enable_dual_mode_audio=true' "$STOCK_EXTRACT_DIR/vendor/build.prop"

# 解锁扬声器清理
echo "解锁扬声器清理"
sed -i '/^ro.vendor.touchfeature.type=183/a ro.vendor.audio.clean_speaker=true' "$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# ZRAM 1:1调整
echo "zram 1:1调整"
mkdir -p ./tmp
sudo mv "$MIGRATION_EXTRACT_DIR"/system_ext/etc/perfinit_bdsize_zram.conf ./tmp/
jq '.zram += [{"product_name": ["umi", "cmi", "cas", "apollo", "thyme", "alioth", "munch", "venus", "mars", "star", "odin", "fuxi", "nuwa", "ishtar"], "zram_size": {"6": 6144, "8": 8192, "12": 12288, "16": 16384, "24": 24567}}]' ./tmp/perfinit_bdsize_zram.conf >./tmp/perfinit_bdsize_zram_out.conf
sudo mv ./tmp/perfinit_bdsize_zram_out.conf "$MIGRATION_EXTRACT_DIR"/system_ext/etc/perfinit_bdsize_zram.conf
sudo rm -rf ./tmp

# 启用dm设备映射控制器
echo "启用dm设备映射控制器"
sed -i '/persist.sys.stability.swapEnable=true/a persist.miui.extm.dm_opt.enable=true' "$MIGRATION_EXTRACT_DIR"/product/etc/build.prop

# 添加性能等级支持
PRODUCT_BUILD_PROP="$MIGRATION_EXTRACT_DIR/product/etc/build.prop"
ODM_BUILD_PROP="$STOCK_EXTRACT_DIR/odm/etc/build.prop"

# ==============================================
# 步骤1：批量注释 product/build.prop 中的性能等级配置
# ==============================================
if [ -f "$PRODUCT_BUILD_PROP" ]; then
  echo "→ 处理文件：$PRODUCT_BUILD_PROP"
  
  # 批量匹配并注释目标行（使用数组存储规则）
  target_patterns=(
    "ro.vendor.media_performance_class=35"
    "ro.odm.build.media_performance_class=35"
  )
  
  for pattern in "${target_patterns[@]}"; do
    if grep -q "^$pattern" "$PRODUCT_BUILD_PROP"; then
      sudo sed -i "s/^$pattern/# &/" "$PRODUCT_BUILD_PROP"
      echo "  已注释：$pattern"
    else
      echo "  未找到，跳过：$pattern"
    fi
  done
else
  echo " 警告：文件不存在 → $PRODUCT_BUILD_PROP"
fi

# ==============================================
# 步骤2：在 odm/build.prop 中添加新配置
# ==============================================
if [ -f "$ODM_BUILD_PROP" ]; then
  echo -e "\n→ 处理文件：$ODM_BUILD_PROP"
  target_line="ro.odm.build.version.sdk=33"
  new_config="ro.odm.build.media_performance_class=33"
  
  # 检查目标行是否存在，避免重复添加
  if grep -q "^$target_line" "$ODM_BUILD_PROP"; then
    if ! grep -q "^$new_config" "$ODM_BUILD_PROP"; then
      sudo sed -i "/^$target_line/a $new_config" "$ODM_BUILD_PROP"
      echo "  已添加：$new_config（在 $target_line 下方）"
    else
      echo "  配置已存在，跳过：$new_config"
    fi
  else
    echo " 警告：未找到目标行 → $target_line"
  fi
else
  echo " 警告：文件不存在 → $ODM_BUILD_PROP"
fi

echo -e "\n 配置修改完成"

# 优化核心分配
TARGET_FILE="$MIGRATION_EXTRACT_DIR/product/etc/build.prop"
# 替换规则数组：[原key]=目标值
declare -A REPLACE_RULES=(
  ["dalvik.vm.boot-dex2oat-cpu-set"]="0,1,2,3,4,5,6,7"
  ["dalvik.vm.background-dex2oat-cpu-set"]="0,1,2,3,4,5,6,7"
  ["ro.miui.affinity.sfui"]="3-6"
  ["ro.miui.affinity.sfre"]="3-6"
  ["persist.sys.dexpreload.other_cores"]="0-2"
  ["persist.sys.dexpreload.cpu_cores"]="0-7"
  ["persist.sys.dexpreload.big_prime_cores"]="3-6"
)

# ==============================================
# 主逻辑：检查文件+批量替换+结果反馈
# ==============================================
echo "=== 开始优化核心分配配置 ==="

# 检查目标文件是否存在
if [ ! -f "$TARGET_FILE" ]; then
  echo " 错误：文件不存在 → $TARGET_FILE"
  exit 1
fi

# 备份原文件（防止误操作）
BACKUP_FILE="${TARGET_FILE}.bak"
cp -a "$TARGET_FILE" "$BACKUP_FILE" && echo " 已创建备份 → $BACKUP_FILE"

# 遍历替换规则，执行sed修改
for key in "${!REPLACE_RULES[@]}"; do
  value="${REPLACE_RULES[$key]}"
  # 使用sed精确匹配key并替换值（保留原格式，仅更新等号后内容）
  if sed -i "s/^${key}=[^*]*/${key}=${value}/" "$TARGET_FILE"; then
    echo " 更新成功：${key}=${value}"
  else
    echo " 更新失败：${key}（可能原key不存在）"
  fi
done

# ==============================================
# 验证结果：显示修改后的关键配置
# ==============================================
echo -e "\n=== 修改后配置验证 ==="
for key in "${!REPLACE_RULES[@]}"; do
  grep "^${key}=" "$TARGET_FILE" || echo " 未找到配置：${key}"
done

echo -e "\n=== 核心分配优化完成 ==="
echo "提示：若需恢复原始配置，可执行 → cp -a $BACKUP_FILE $TARGET_FILE"

sed -i '$a \
# Wanderlust added for Xiaomi HyperOS Core allocation \
persist.vendor.display.miui.composer_boost=3-7 \
persist.sys.miui_animator_sched.big_prime_cores=7 \
persist.sys.miui_animator_sched.sched_threads=2 \
persist.sys.miui_animator_sched.bigcores=3-6' "$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"

# 常规修改
# 1. 待修改的属性规则（格式："文件路径:属性名"）
declare -A BUILD_PROP_RULES=(
  ["${MIGRATION_EXTRACT_DIR}/system/system/build.prop"]="ro.build.user ro.system.build.date ro.system.build.date.utc ro.build.date ro.build.date.utc"
  ["${STOCK_EXTRACT_DIR}/system_dlkm/etc/build.prop"]="ro.system_dlkm.build.date ro.system_dlkm.build.date.utc"
  ["${STOCK_EXTRACT_DIR}/vendor/build.prop"]="ro.vendor.build.date ro.vendor.build.date.utc"
  ["${STOCK_EXTRACT_DIR}/vendor_dlkm/etc/build.prop"]="ro.vendor_dlkm.build.date ro.vendor_dlkm.build.date.utc"
  ["${MIGRATION_EXTRACT_DIR}/system_ext/etc/build.prop"]="ro.system_ext.build.date ro.system_ext.build.date.utc"
  ["${MIGRATION_EXTRACT_DIR}/product/etc/build.prop"]="ro.product.build.date ro.product.build.date.utc"
  ["${STOCK_EXTRACT_DIR}/odm/etc/build.prop"]="ro.odm.build.date ro.odm.build.date.utc"
)

# 2. 固定配置
NEW_BUILD_USER="Wanderlust"
BUILD_TIME=$(date)                  # 本地时间（如：Sat Sep 27 20:07:00 CST 2025）
BUILD_UTC=$(date -d "$BUILD_TIME" +%s)  # UTC时间戳（如：1753704420）

# ==============================================
# 执行区：批量处理逻辑
# ==============================================
echo -e "\n===== 开始执行常规修改 ====="

# 1. 环境预检查
if [ -z "${MIGRATION_EXTRACT_DIR}" ] || [ -z "${STOCK_EXTRACT_DIR}" ]; then
  echo "错误：环境变量 MIGRATION_EXTRACT_DIR 或 STOCK_EXTRACT_DIR 未定义！"
  exit 1
fi

# 2. 批量处理所有build.prop文件
for prop_file in "${!BUILD_PROP_RULES[@]}"; do
  # 跳过不存在的文件（避免错误）
  if [ ! -f "$prop_file" ]; then
    echo "警告：文件不存在，跳过 → $prop_file"
    continue
  fi

  echo -e "\n→ 处理文件：$prop_file"
  target_props=(${BUILD_PROP_RULES[$prop_file]})  # 拆分属性列表

  # 遍历当前文件的所有目标属性
  for prop in "${target_props[@]}"; do
    # 根据属性名设置值（区分user属性和date属性）
    if [ "$prop" = "ro.build.user" ]; then
      new_value="$NEW_BUILD_USER"
    elif [[ "$prop" == *.utc ]]; then
      new_value="$BUILD_UTC"
    else
      new_value="$BUILD_TIME"
    fi

    # 执行替换（仅修改已存在的属性）
    if grep -q "^$prop=" "$prop_file"; then
      sudo sed -i "s/^$prop=.*/$prop=$new_value/" "$prop_file"
      echo "   修改成功：$prop=$new_value"
    else
      echo "   未找到属性，跳过：$prop"
    fi
  done
done

echo -e "\n===== 常规修改执行完成 ====="

# 自定义版本号
OLD_VERSION1="OS3.0.9.0.WPBCNXM"
OLD_VERSION2="OS2.0.215.0.VMBCNXM"
NEW_VERSION="OS3.0.250928.0.WMBCNXM"
DEVICE_NAME_OLD="$MIGRATION_EXTRACT_DIR"
DEVICE_NAME_NEW="$STOCK_EXTRACT_DIR"

# 替换任务数组：[文件路径]="操作1;操作2;..."（每个操作格式：key=value 或 old_str|new_str）
declare -A TASKS=(
  ["$MIGRATION_EXTRACT_DIR/mi_ext/etc/build.prop"]="ro.mi.os.version.incremental=$NEW_VERSION;ro.product.mod_device=$DEVICE_NAME_NEW;$OLD_VERSION1|$NEW_VERSION"
  ["$MIGRATION_EXTRACT_DIR/product/etc/build.prop"]="$DEVICE_NAME_OLD|$DEVICE_NAME_NEW;$OLD_VERSION1|$NEW_VERSION"
  ["$MIGRATION_EXTRACT_DIR/system/system/build.prop"]="$OLD_VERSION1|$NEW_VERSION"
  ["$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"]="$OLD_VERSION1|$NEW_VERSION"
  ["$STOCK_EXTRACT_DIR/system_dlkm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
  ["$STOCK_EXTRACT_DIR/vendor_dlkm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
  ["$STOCK_EXTRACT_DIR/vendor/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
  ["$STOCK_EXTRACT_DIR/odm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
)

# ==============================================
# 主逻辑：遍历任务并执行替换
# ==============================================
echo "=== 开始系统配置批量更新 ==="

for file in "${!TASKS[@]}"; do
  # 检查文件是否存在
  if [ ! -f "$file" ]; then
    echo " 跳过不存在的文件：$file"
    continue
  fi

  # 创建备份（仅首次处理时备份）
  backup_file="${file}.bak"
  if [ ! -f "$backup_file" ]; then
    cp -a "$file" "$backup_file" && echo " 已备份：$backup_file"
  fi

  # 解析当前文件的所有操作
  operations="${TASKS[$file]}"
  IFS=';' read -ra OP_ARR <<< "$operations"  # 按分号分割操作

  # 执行每个操作
  echo -e "\n 处理文件：$file"
  for op in "${OP_ARR[@]}"; do
    if [[ "$op" == *"="* ]]; then
      # 操作1：key=value（精确匹配key并替换值）
      key="${op%=*}"
      value="${op#*=}"
      if sed -i "s/^${key}=.*/${key}=${value}/" "$file"; then
        echo "   更新配置：$key=$value"
      else
        echo "   更新失败：$key（可能原key不存在）"
      fi
    elif [[ "$op" == *"|"* ]]; then
      # 操作2：old_str|new_str（全局替换字符串）
      old_str="${op%|*}"
      new_str="${op#*|}"
      if sed -i "s/${old_str}/${new_str}/g" "$file"; then
        echo "   替换字符串：${old_str} → ${new_str}"
      else
        echo "   替换失败：${old_str}"
      fi
    fi
  done
done

echo -e "\n=== 配置更新完成 ==="
echo "提示：若需恢复原始配置，可执行 → cp -a [文件名].bak [文件名]"

# 解压刷机脚本
mkdir -p "$STOCK_EXTRACT_DIR"/firmware
mv "$STOCK_EXTRACT_DIR"/*.img "$STOCK_EXTRACT_DIR"/firmware

echo "添加mi_block的Twrp Recovery"

# 定义源文件和目标目录
SOURCE_FILE="./tools/recovery/[REC]3.7.1_12-Mi13Pro_v9.0_A16-nuwa-skkk.img"
DESTINATION_FILE="$STOCK_EXTRACT_DIR/recovery.img"

# 复制并重命名文件
cp "$SOURCE_FILE" "$DESTINATION_FILE"

# 检查复制是否成功
if [ $? -eq 0 ]; then
    echo "文件已成功复制并重命名为 recovery.img"
else
    echo "复制文件时发生错误"
fi

unzip -o -q ./tools/flashscript/flashtools.zip -d ./output
mv "$STOCK_EXTRACT_DIR"/firmware ./output/firmware
cp -f ./common_files/cust.img ./output/firmware

# 修补添加文件的上下文
FSPATCH_TOOL="./tools/python/fspatch.py"
CONTEXTPATCH_TOOL="./tools/python/contextpatch.py"

# 定义待处理的分区列表（格式："分区名:根目录变量"）
PARTITIONS=(
  "odm:STOCK_EXTRACT_DIR"
  "vendor:STOCK_EXTRACT_DIR"
  "vendor_dlkm:STOCK_EXTRACT_DIR"
  "system_dlkm:STOCK_EXTRACT_DIR"
  "mi_ext:MIGRATION_EXTRACT_DIR"
  "product:MIGRATION_EXTRACT_DIR"
  "system:MIGRATION_EXTRACT_DIR"
  "system_ext:MIGRATION_EXTRACT_DIR"
)

# ==============================================
# 主逻辑：循环处理所有分区的补丁任务
# ==============================================
echo "=== 开始批量执行补丁脚本 ==="
total_tasks=$(( ${#PARTITIONS[@]} * 2 ))  # 每个分区2个任务（fs_config + file_contexts）
current_task=0

for item in "${PARTITIONS[@]}"; do
  # 解析分区名和根目录变量（如 "odm:STOCK_EXTRACT_DIR" → 分区名=odm，根目录变量=STOCK_EXTRACT_DIR）
  partition="${item%:*}"
  root_dir_var="${item#*:}"
  root_dir="${!root_dir_var}"  # 通过变量名动态获取根目录路径（间接引用）

  # 定义当前分区的配置文件路径
  fs_config_path="${root_dir}/config/${partition}_fs_config"
  context_path="${root_dir}/config/${partition}_file_contexts"
  target_dir="${root_dir}/${partition}"

  # 检查目标目录是否存在
  if [ ! -d "$target_dir" ]; then
    echo "  跳过不存在的目录：$target_dir"
    continue
  fi

  # 1. 执行 fspatch 任务
  current_task=$((current_task + 1))
  echo -e "\n[${current_task}/${total_tasks}] 处理 ${partition} 分区：fspatch"
  if python3 "$FSPATCH_TOOL" "$target_dir" "$fs_config_path"; then
    echo "  fspatch 完成：${partition}"
  else
    echo "  fspatch 失败：${partition}（请检查配置文件或目标目录）"
  fi

  # 2. 执行 contextpatch 任务
  current_task=$((current_task + 1))
  echo "[${current_task}/${total_tasks}] 处理 ${partition} 分区：contextpatch"
  if python3 "$CONTEXTPATCH_TOOL" "$target_dir" "$context_path"; then
    echo "  contextpatch 完成：${partition}"
  else
    echo "  contextpatch 失败：${partition}（请检查配置文件或目标目录）"
  fi
done

echo -e "\n=== 所有补丁任务处理完毕 ==="

# 打包img文件
MKFS_EROFS_TOOL="./tools/binary/mkfs.erofs"
COMMON_ARGS=(
  -zlz4hc,9                  # 压缩算法与级别
  -T 1230768000              # 时间戳
  --quiet                    # 静默模式
)

# 定义待处理的分区列表（格式："分区名:根目录变量:挂载点"）
PARTITIONS=(
  "odm:STOCK_EXTRACT_DIR:/odm"
  "vendor:STOCK_EXTRACT_DIR:/vendor"
  "vendor_dlkm:STOCK_EXTRACT_DIR:/vendor_dlkm"
  "system_dlkm:STOCK_EXTRACT_DIR:/system_dlkm"
  "mi_ext:MIGRATION_EXTRACT_DIR:/mi_ext"
  "product:MIGRATION_EXTRACT_DIR:/product"
  "system:MIGRATION_EXTRACT_DIR:/system"
  "system_ext:MIGRATION_EXTRACT_DIR:/system_ext"
)

# ==============================================
# 主逻辑：循环批量生成 EROFS 镜像
# ==============================================
echo "=== 开始批量生成 EROFS 镜像 ==="
total_tasks=${#PARTITIONS[@]}
current_task=0

for item in "${PARTITIONS[@]}"; do
  current_task=$((current_task + 1))
  
  # 解析分区信息（格式：分区名:根目录变量:挂载点）
  IFS=':' read -r partition root_dir_var mount_point <<< "$item"
  root_dir="${!root_dir_var}"  # 动态获取根目录路径（如 STOCK_EXTRACT_DIR 的值）

  # 定义当前分区的文件路径
  fs_config_path="${root_dir}/config/${partition}_fs_config"
  context_path="${root_dir}/config/${partition}_file_contexts"
  source_dir="${root_dir}/${partition}"
  output_img="${root_dir}/${partition}.img"

  # 检查必要文件/目录是否存在
  if [ ! -d "$source_dir" ]; then
    echo "  [${current_task}/${total_tasks}] 跳过 ${partition}：源目录不存在 → $source_dir"
    continue
  fi
  if [ ! -f "$fs_config_path" ] || [ ! -f "$context_path" ]; then
    echo "  [${current_task}/${total_tasks}] 跳过 ${partition}：配置文件缺失 → $fs_config_path 或 $context_path"
    continue
  fi

  # 执行 mkfs.erofs 命令（拼接通用参数与分区特有参数）
  echo -e "\n[${current_task}/${total_tasks}] 生成 ${partition} 镜像 → $output_img"
  if "$MKFS_EROFS_TOOL" \
      "${COMMON_ARGS[@]}" \
      --mount-point "$mount_point" \
      --fs-config-file "$fs_config_path" \
      --file-contexts "$context_path" \
      "$output_img" \
      "$source_dir"; then
    echo "   ${partition} 镜像生成成功"
  else
    echo "   ${partition} 镜像生成失败（错误码：$?）"
  fi
done

echo -e "\n=== 批量任务结束 ==="

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
OUTPUT_DIR="./output"           # 待压缩文件目录
ZIP_BASE_NAME="$STOCK_EXTRACT_DIR-ota_full-$NEW_VERSION-user-16.0"  # 基础文件名
ZIP_DIR="./zip"                 # 压缩包输出目录
MD5_LENGTH=10                   # MD5截取长度

# ==============================================
# 预检查：确保环境与文件就绪
# ==============================================
# 检查 output 目录是否存在且非空
if [ ! -d "$OUTPUT_DIR" ] || [ -z "$(ls -A "$OUTPUT_DIR")" ]; then
  echo "错误：目录不存在或为空 → $OUTPUT_DIR"
  exit 1
fi

# 检查 7z 命令是否可用
if ! command -v 7z &> /dev/null; then
  echo "错误：未找到 7z 命令，请先安装 p7zip-full"
  exit 1
fi

# 创建 zip 输出目录（若不存在）
mkdir -p "$ZIP_DIR" || { echo "错误：无法创建目录 → $ZIP_DIR"; exit 1; }

# ==============================================
# 生成压缩包：带进度显示与错误捕获
# ==============================================
echo "=== 开始压缩文件 ==="
zip_temp_path="${ZIP_DIR}/${ZIP_BASE_NAME}.zip"  # 临时压缩包路径（未加MD5）

# 使用 7z 压缩（-tzip：指定ZIP格式，-mx=6：平衡压缩率与速度，-bb1：显示压缩进度）
7z a -tzip -mx=6 -bb1 "$zip_temp_path" "$OUTPUT_DIR"/*

# 检查压缩是否成功
if [ $? -ne 0 ]; then
  echo "错误：压缩失败！临时文件已删除 → $zip_temp_path"
  rm -f "$zip_temp_path"  # 清理失败的临时文件
  exit 1
fi

# ==============================================
# 计算 MD5 并重命名压缩包
# ==============================================
echo "=== 计算 MD5 并生成最终文件名 ==="
# 截取 MD5 前 N 位（示例：1234567890abcdef → 1234567890）
md5_prefix=$(md5sum "$zip_temp_path" | awk '{print $1}' | cut -c 1-"$MD5_LENGTH")
final_zip_path="${ZIP_DIR}/${ZIP_BASE_NAME}-${md5_prefix}.zip"

# 重命名临时文件为最终文件名
mv "$zip_temp_path" "$final_zip_path" || { echo "错误：重命名失败！"; exit 1; }

# ==============================================
# 输出结果：显示成功信息与文件详情
# ==============================================
echo -e "\n=== 操作完成 ==="
echo "最终压缩包：$final_zip_path"
echo "文件大小：$(du -h "$final_zip_path" | awk '{print $1}')"
echo "MD5前缀：$md5_prefix（完整MD5：$(md5sum "$final_zip_path" | awk '{print $1}')）"

rm -rf "$MIGRATION_EXTRACT_DIR" "$STOCK_EXTRACT_DIR" output