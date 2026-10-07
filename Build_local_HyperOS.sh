#!/bin/bash

# ======================== 函数定义：通用工具 ========================
error_exit() {
    echo -e "\n错误：$1"
    exit 1
}

warn_skip() {
    echo -e "警告：$1，跳过"
}

check_file_exists() {
    [ ! -f "$1" ] && error_exit "文件不存在：$1"
}

create_dir() {
    if [ ! -d "$1" ]; then
        echo -e " 创建目录：$1"
        mkdir -p "$1" || error_exit "无法创建目录 $1"
    fi
}

# 设备型号检测（统一入口）
# 用法：detect_device → DEVICE_TYPE=fuxi/nuwa/ishtar/unknown
detect_device() {
    case "$STOCK_EXTRACT_DIR" in
        *fuxi*)  DEVICE_TYPE=fuxi ;;
        *nuwa*)  DEVICE_TYPE=nuwa ;;
        *ishtar*) DEVICE_TYPE=ishtar ;;
        *)       DEVICE_TYPE=unknown ;;
    esac
}

# 仅在设备匹配时执行，不匹配则跳过（不会 exit）
# 用法：require_device fuxi nuwa || return 0
require_device() {
    for d in "$@"; do
        [ "$DEVICE_TYPE" = "$d" ] && return 0
    done
    echo "当前设备 $DEVICE_TYPE 不匹配（需要 $*），跳过此步骤"
    return 1
}

# 检查关键变量是否已设置
check_env() {
    [ -z "$MIGRATION_EXTRACT_DIR" ] && error_exit "MIGRATION_EXTRACT_DIR 未设置"
    [ -z "$STOCK_EXTRACT_DIR" ]    && error_exit "STOCK_EXTRACT_DIR 未设置"
}

# device_features XML 路径（统一）
device_xml() {
    echo "$MIGRATION_EXTRACT_DIR/product/etc/device_features/${STOCK_EXTRACT_DIR##*/}.xml"
}

# 通用：选择 zip 固件包
# 参数：$1=标题  $2=提示语
# 返回：SELECTED_ZIP（绝对路径）
select_zip() {
    local title="$1" prompt="$2"
    DOWNLOADS_DIR="./downloads"
    [ ! -d "$DOWNLOADS_DIR" ] && error_exit "downloads 目录不存在，请先创建并放入固件包"

    local zip_list=()
    for f in "$DOWNLOADS_DIR"/*.zip; do
        [ -f "$f" ] && zip_list+=("$f")
    done
    [ ${#zip_list[@]} -eq 0 ] && error_exit "downloads 目录无 zip 固件包"

    echo -e "\n===== $title ====="
    local idx=0
    for f in "${zip_list[@]}"; do
        echo "  $((++idx)). ${f}"
    done

    local choice
    read -p "$prompt" choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#zip_list[@]} ]; then
        error_exit "无效序号，请重新运行"
    fi
    SELECTED_ZIP="${zip_list[$((choice-1))]}"
    echo -e "  已选：$SELECTED_ZIP"
}

# 通用：从 build.prop 注释属性列表
# 参数：$1=文件路径  $2..$n=属性正则
comment_props() {
    local file="$1"; shift
    [ ! -f "$file" ] && warn_skip "文件不存在 $file" && return 0

    for pattern in "$@"; do
        if sed -i.bak -E "s/^(${pattern})/# \1/" "$file"; then
            if ! diff -q "$file" "$file.bak" >/dev/null 2>&1; then
                echo "  已注释：$pattern"
            else
                echo "  未找到：$pattern"
            fi
        fi
        rm -f "$file.bak"
    done
}

# ======================== 主流程：处理 Stock 包 ========================
process_stock_package() {
    echo -e "\n===== 开始处理 Stock 固件包 ====="
    select_zip "可选固件包" "请输入固件包序号："
    STOCK_ZIP="$SELECTED_ZIP"

    # 自动生成提取目录：截取文件名 -ota 前面部分
    STOCK_FILENAME=$(basename "$STOCK_ZIP")
    STOCK_EXTRACT_DIR="${STOCK_FILENAME%-ota*}"
    [ -z "$STOCK_EXTRACT_DIR" ] && error_exit "文件名不含 -ota，无法生成提取目录"
    echo -e "  提取目录：$STOCK_EXTRACT_DIR"
    create_dir "$STOCK_EXTRACT_DIR"

    # 解压 payload.bin
    echo -e "\n 提取 Stock 包 payload..."
    ./tools/binary/payload_extract -i "$STOCK_ZIP" -t zip -o "$STOCK_EXTRACT_DIR" -x \
        || error_exit "payload_extract 失败（Stock 包）"

    # 提取各类镜像
    STOCK_IMAGES=(odm product system system_ext system_dlkm vendor vendor_dlkm mi_ext)
    echo -e "\n 待提取镜像：${STOCK_IMAGES[*]}"
    for image in "${STOCK_IMAGES[@]}"; do
        local img_path="$STOCK_EXTRACT_DIR/${image}.img"
        check_file_exists "$img_path"
        echo -e "\n 提取 ${image}.img..."
        ./tools/binary/extract.erofs -i "$img_path" -o "$STOCK_EXTRACT_DIR" -x \
            || error_exit "提取 ${image}.img 失败（Stock 包）"
    done

    # 清理原始镜像
    echo -e "\n 清理原始镜像文件..."
    for image in "${STOCK_IMAGES[@]}"; do
        rm -f "$STOCK_EXTRACT_DIR/${image}.img"
    done
}

# ======================== 主流程：处理 Migration 包 ========================
process_migration_package() {
    echo -e "\n===== 开始处理 Migration 固件包 ====="
    select_zip "可选 Migration 固件包" "请输入 Migration 固件包序号："
    MIGRATION_ZIP="$SELECTED_ZIP"

    # 自动生成提取目录
    MIGRATION_FILENAME=$(basename "$MIGRATION_ZIP")
    MIGRATION_EXTRACT_DIR="${MIGRATION_FILENAME%-ota*}"
    [ -z "$MIGRATION_EXTRACT_DIR" ] && error_exit "文件名不含 -ota，无法生成提取目录"
    echo -e "  提取目录：$MIGRATION_EXTRACT_DIR"
    create_dir "$MIGRATION_EXTRACT_DIR"

    # 解压 payload.bin 指定 image
    echo -e "\n 从 Migration ZIP 提取 payload 指定 image..."
    ./tools/binary/payload_extract -i "$MIGRATION_ZIP" -t zip -o "$MIGRATION_EXTRACT_DIR" -X product,system,system_ext,mi_ext,init_boot -T0 \
        || error_exit "payload_extract 失败（Migration 包）"

    # 提取镜像文件
    MIGRATION_IMAGES=(mi_ext product system system_ext)
    echo -e "\n Migration 镜像列表：${MIGRATION_IMAGES[*]}"
    for image in "${MIGRATION_IMAGES[@]}"; do
        local img_path="$MIGRATION_EXTRACT_DIR/${image}.img"
        check_file_exists "$img_path"
        echo -e "\n 提取 ${image}.img..."
        ./tools/binary/extract.erofs -i "$img_path" -o "$MIGRATION_EXTRACT_DIR" -x \
            || error_exit "提取 ${image}.img 失败（Migration 包）"
    done
}

# ======================== 入口执行 ========================
echo -e "===== 镜像提取工具 ====="
check_file_exists "./tools/binary/payload_extract"
check_file_exists "./tools/binary/extract.erofs"
check_file_exists "./tools/binary/magiskboot"
MAGISKBOOT="./tools/binary/magiskboot"
BUILD_ROOT="$PWD"

process_stock_package
process_migration_package

echo -e "\n===== 提取完成 ====="
echo "  Stock 包内容：$STOCK_EXTRACT_DIR"
echo "  Migration 包内容：$MIGRATION_EXTRACT_DIR"

check_env
detect_device
echo -e "\n 设备型号：$DEVICE_TYPE"

# ======================== 禁用 AVB 2.0 校验 ========================
echo -e "\n===== 禁用 AVB 2.0 校验 ====="
./tools/binary/magiskboot hexpatch "$STOCK_EXTRACT_DIR/vbmeta.img" \
    0000000000000000617662746F6F6C20 0000000100000000617662746F6F6C20

# ======================== 禁用 Xiaomi 全局 vulkan 渲染 ========================
echo -e "\n===== 禁用 Xiaomi 全局 vulkan 渲染 ====="
PRODUCT_PROP="$MIGRATION_EXTRACT_DIR/product/etc/build.prop"
[ -f "$PRODUCT_PROP" ] && sed -i 's/persist.sys.enhance_vkpipelinecache.enable=true/# persist.sys.enhance_vkpipelinecache.enable=true/g' "$PRODUCT_PROP"

# ======================== 添加底包的 device_features ========================
echo -e "\n===== 添加底包的 device_features 文件 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"
cp -rf "$STOCK_EXTRACT_DIR/product/etc/device_features/" "$MIGRATION_EXTRACT_DIR/product/etc/device_features/"
# 路径变更后重新计算
DEVICE_XML=$(device_xml)

# ======================== 修改 device_features XML 的通用函数 ========================
# 参数：$1=sed 表达式
patch_device_xml() {
    [ ! -f "$DEVICE_XML" ] && warn_skip "device_features XML 不存在" && return 0
    cp -f "$DEVICE_XML" "$DEVICE_XML.bak"
    sed -i "$1" "$DEVICE_XML"
    if diff -q "$DEVICE_XML" "$DEVICE_XML.bak" >/dev/null 2>&1; then
        echo "  未匹配（特性可能未生效）：$1"
    else
        echo "  已修改 device_features"
    fi
    rm -f "$DEVICE_XML.bak"
}

# ======================== 屏蔽系统更新检测 ========================
echo -e "\n===== 屏蔽系统更新检测 ====="
patch_device_xml 's/<bool name="support_ota_validate">true<\/bool>/<bool name="support_ota_validate">false<\/bool>/'

# ======================== 解锁 Widevine L1 ========================
echo -e "\n===== 解锁 Widevine L1 指纹支付证书在线更新 ====="
patch_device_xml 's/<integer name="support_widevine_l1">1<\/integer>/<integer name="support_widevine_l1">2<\/integer>/'

# ======================== 解锁息屏显示样式 ========================
echo -e "\n===== 解锁新版息屏显示样式 ====="
BUILD_PROP_ODM="$STOCK_EXTRACT_DIR/odm/etc/build.prop"

if [ -f "$DEVICE_XML" ]; then
    sed -i '/is_aod_need_grayscale/a\
    <!--whether the device supports aod fullscreen mode-->\
    <bool name="support_aod_fullscreen">true</bool>\
    <!-- The fps of aon_screen_off-->\
    <integer name="aon_screen_off_fps">0</integer>' "$DEVICE_XML"
    echo "  已解锁息屏显示样式"
else
    warn_skip "$DEVICE_XML 不存在"
fi

if [ -f "$BUILD_PROP_ODM" ]; then
    sed -i '/ro\.vendor\.display\.primary_idle_refresh_rate/a ro.vendor.mi_sf.aod_mode_ddic_refresh_rate=1' "$BUILD_PROP_ODM"
    echo "  已添加 aod_mode_ddic_refresh_rate 属性"
else
    warn_skip "$BUILD_PROP_ODM 不存在"
fi

# ======================== 解锁节律护眼 + 24/30/40Hz 刷新率 ========================
echo -e "\n===== 解锁节律护眼 + 24/30/40Hz 刷新率 ====="
if [ -f "$DEVICE_XML" ]; then
    sed -i '/config_sunlight_mode_available/a\
    <!-- default rhythmic eyecare mode -->\
    <integer name="default_eyecare_mode">2</integer>' "$DEVICE_XML"
    sed -i '/<integer-array name="fpsList">/,/<\/integer-array>/{
        /<item>60<\/item>/a\
            <item>40</item>\
            <item>30</item>\
            <item>24</item>
    }' "$DEVICE_XML"
    sed -i '/default_eyecare_mode/a\
    <!-- Whether rhythmic mode 2.0 supported by phone -->\
    <bool name="is_rhythmic_mode_v2_supported">true</bool>' "$DEVICE_XML"
    echo "  已完成：节律护眼 + 24/30/40Hz 刷新率"
else
    warn_skip "$DEVICE_XML 不存在"
fi

# ======================== 从 Stock 复制应用（批量） ========================
echo -e "\n===== 从 Stock 复制应用到 Migration ====="
STOCK_APPS=(
    "product/app/MiuiCit:product/app/MiuiCit"
    "product/app/AiasstVision:product/app/AiasstVision"
    "product/app/MiAONService:product/app/MiAONServiceW"
    "product/priv-app/MiuiCamera:product/priv-app/MiuiCamera"
)
for pair in "${STOCK_APPS[@]}"; do
    src="${pair%%:*}"
    dst="${pair##*:}"
    src_path="$STOCK_EXTRACT_DIR/$src"
    dst_path="$MIGRATION_EXTRACT_DIR/$dst"
    [ -d "$src_path" ] && { rm -rf "$dst_path"; cp -rf "$src_path" "$dst_path"; echo "  已复制：$src"; } \
        || warn_skip "$src_path 不存在"
done

# ======================== 恢复官方特有壁纸 ========================
echo -e "\n===== 恢复官方特有壁纸 ====="
if require_device fuxi nuwa; then
    SRC_WALLPAPERS="$STOCK_EXTRACT_DIR/product/media/wallpaper/wallpaper_group"
    DST_WALLPAPERS="$MIGRATION_EXTRACT_DIR/product/media/wallpaper/wallpaper_group"
    WALLPAPER_DIRS=(06_GlassyLight 07_ShadowGeometry)

    copied=()
    for dir in "${WALLPAPER_DIRS[@]}"; do
        if [ -d "$SRC_WALLPAPERS/$dir" ]; then
            mkdir -p "$DST_WALLPAPERS/$dir"
            cp -rf "$SRC_WALLPAPERS/$dir/." "$DST_WALLPAPERS/$dir/"
            copied+=("$dir")
        else
            warn_skip "源目录不存在 $dir"
        fi
    done
    [ ${#copied[@]} -gt 0 ] && echo "  壁纸恢复成功：${copied[*]}" || echo "  未复制任何壁纸"
fi

# ======================== 修复 NFC ========================
echo -e "\n===== 修复 NFC ====="
NFC_DST="$MIGRATION_EXTRACT_DIR/product/pangu/system/app"
case "$DEVICE_TYPE" in
    fuxi|nuwa) APP=NQNfcNci ;;
    ishtar)    APP=Nfc_st ;;
    *)         warn_skip "当前设备无 NFC 配置"; APP= ;;
esac

if [ -n "$APP" ]; then
    NFC_SRC="./common_files/$APP"
    if [ -d "$NFC_SRC" ]; then
        rm -rf "$NFC_DST/$APP"
        cp -rf "$NFC_SRC" "$NFC_DST/"
        echo "  $APP 复制完成"
    else
        warn_skip "$NFC_SRC 不存在"
    fi
fi

# ======================== 修复开机动画分辨率 ========================
echo -e "\n===== 修复开机动画分辨率 ====="
if [ -f "$STOCK_EXTRACT_DIR/product/media/bootanimation.zip" ]; then
    cp -f "$STOCK_EXTRACT_DIR/product/media/bootanimation.zip" "$MIGRATION_EXTRACT_DIR/product/media/"
else
    warn_skip "bootanimation.zip 不存在"
fi

# ======================== 修复基带 ========================
echo -e "\n===== 修复基带 ====="
if [ -d "$STOCK_EXTRACT_DIR/product/app/LyraSdkApp" ]; then
    rm -rf "$MIGRATION_EXTRACT_DIR/product/app/LyraSdkSpp"
    cp -rf "./common_files/LyraSdkSpp/" "$MIGRATION_EXTRACT_DIR/product/app/LyraSdkSpp/"
else
    warn_skip "LyraSdkApp 不存在"
fi

# ======================== 修复 AI 模型 ========================
echo -e "\n===== 修复 AI 模型 ====="
STOCK_AI_DIR="$STOCK_EXTRACT_DIR/mi_ext/product/ai"
MIGRATION_AI_DIR="$MIGRATION_EXTRACT_DIR/mi_ext/product/ai"
if [ -d "$STOCK_AI_DIR" ]; then
    mkdir -p "$MIGRATION_AI_DIR"
    rm -rf "$MIGRATION_AI_DIR"/*
    cp -rf "$STOCK_AI_DIR/." "$MIGRATION_AI_DIR/"
    echo "  AI 模型已替换为底包版本"
else
    warn_skip "$STOCK_AI_DIR 不存在"
fi

# ======================== 去除国区谷歌商店限制 ========================
echo -e "\n===== 去除国区谷歌商店限制 ====="
XML="$MIGRATION_EXTRACT_DIR/product/etc/permissions/cn.google.services.xml"
if [ -f "$XML" ]; then
    sed -i '/cn\.google\.services\|com\.google\.android\.feature\.services_updater/d' "$XML"
    echo "  已移除国区谷歌商店限制"
else
    warn_skip "$XML 不存在"
fi

# ======================== 添加屏幕配置 ========================
echo -e "\n===== 添加屏幕配置文件 ====="
rm -rf "$MIGRATION_EXTRACT_DIR/product/etc/displayconfig"
if [ -d "$STOCK_EXTRACT_DIR/product/etc/displayconfig" ]; then
    cp -rf "$STOCK_EXTRACT_DIR/product/etc/displayconfig" "$MIGRATION_EXTRACT_DIR/product/etc/"
else
    warn_skip "displayconfig 不存在"
fi

# ======================== 修复分辨率密度 ========================
echo -e "\n===== 修复分辨率密度 ====="
case "$DEVICE_TYPE" in
    nuwa|ishtar) density=600 ;;
    fuxi)        density=440 ;;
    *)           warn_skip "未识别设备，跳过分辨率修复"; density= ;;
esac

if [ -n "$density" ]; then
    for prop in ro.sf.lcd_density ro.sf.lcd_sec_density persist.miui.density_v2; do
        sed -i "s/^${prop}=[^ ]*/${prop}=${density}/" "$PRODUCT_PROP"
    done
    echo "  已设置密度为 $density"
fi

# ======================== 禁用不可卸载 2.0 ========================
echo -e "\n===== 禁用不可卸载 2.0 ====="
MI_EXT_PROP="$MIGRATION_EXTRACT_DIR/mi_ext/etc/build.prop"
comment_props "$MI_EXT_PROP" "ro\.miui\.support\.system\.app\.uninstall\.v2"

# ======================== 禁用自适应刷新率 Pro ========================
echo -e "\n===== 禁用自适应刷新率 Pro ====="
comment_props "$PRODUCT_PROP" "ro\.display\.enable_pwm_switch"

# ======================== 清除套壳应用 & 无用组件 ========================
echo -e "\n===== 清除套壳应用 & 无用组件 ====="
TARGET_DIRS=(
    "${MIGRATION_EXTRACT_DIR}/product/data-app/MIUIThemeStore"
    "${MIGRATION_EXTRACT_DIR}/product/data-app/MIUISecurityManager"
    "${MIGRATION_EXTRACT_DIR}/product/data-app/VoiceAssistProxy"
    "${MIGRATION_EXTRACT_DIR}/product/priv-app/MIUIBrowser"
)
for dir_path in "${TARGET_DIRS[@]}"; do
    if [ -e "$dir_path" ]; then
        echo "  删除：${dir_path}"
        rm -rf "$dir_path"
    else
        echo "  跳过（不存在）：${dir_path}"
    fi
done

MI_EXT_DIR="$MIGRATION_EXTRACT_DIR/mi_ext"
if [ -d "$MI_EXT_DIR" ]; then
    find "$MI_EXT_DIR" -type f -iname "*miui-uninstall*" -exec rm -f {} \;
    find "$MI_EXT_DIR" -type f -iname "*sec_overlay*" -exec rm -f {} \;
    echo "  已清理 mi_ext 下的 miui-uninstall 和 sec_overlay 文件"
fi

# ======================== 精简小米推广应用 ========================
echo -e "\n===== 精简小米推广应用 ====="
SEARCH_ROOT="${MIGRATION_EXTRACT_DIR}/product/data-app/"
APPS_TO_REMOVE=(
    BaiduIME iFlytekIME MIGalleryLockscreen
    MIUINewHome_Removable MIUIVideo MIUIYoupin
    MIUIDuokanReader TinyGame
)
if [ -d "$SEARCH_ROOT" ]; then
    for app in "${APPS_TO_REMOVE[@]}"; do
        app_dir=$(find "$SEARCH_ROOT" -maxdepth 1 -type d -iname "*${app}*" 2>/dev/null)
        if [ -n "$app_dir" ]; then
            echo "  精简：${app_dir}"
            rm -rf "$app_dir"
        fi
    done
else
    warn_skip "$SEARCH_ROOT 不存在"
fi

# ======================== 添加 apex vndk33 支持 ========================
echo -e "\n===== 添加 apex vndk33 支持 ====="
APEX_DIR="$MIGRATION_EXTRACT_DIR/system_ext/apex"
cp -f "$STOCK_EXTRACT_DIR/system_ext/apex/com.android.vndk.v33.apex" "$APEX_DIR/"

# ======================== 修复设备内部错误（vendor-ndk v33） ========================
echo -e "\n===== 修复设备内部错误（vendor-ndk v33） ====="
MANIFEST="$MIGRATION_EXTRACT_DIR/system_ext/etc/vintf/manifest.xml"
if [ -f "$MANIFEST" ]; then
    sed -i "/<\/manifest>/i \    <vendor-ndk>\n        <version>33<\/version>\n    <\/vendor-ndk>" "$MANIFEST"
else
    warn_skip "$MANIFEST 不存在"
fi

# ======================== 禁用 cust erofs ========================
echo -e "\n===== 禁用 cust erofs 文件系统支持 ====="
comment_props "$PRODUCT_PROP" \
    "ro\.miui\.cust_erofs" \
    "ro\.miui\.preinstall_to_data" \
    "ro\.miui\.cust_img_path" \
    "ro\.miui\.product_to_cust"

# ======================== 禁用 tango 转译器 ========================
echo -e "\n===== 禁用 tango 转译器 ====="
SYSTEM_PROP="$MIGRATION_EXTRACT_DIR/system/system/build.prop"
SYSTEM_EXT_PROP="$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"
comment_props "$SYSTEM_PROP" \
    "tango\.enabled" \
    "tango\.debug" \
    "tango\.pretrans\.max_size" \
    "tango\.pretrans_on_install" \
    "tango\.pretrans\.debug" \
    "tango\.pretrans\.lib" \
    "tango\.pretrans\.apk"

# ======================== vendor/build.prop 修改（批量追加） ========================
echo -e "\n===== 修改 vendor/build.prop ====="
VENDOR_PROP="$STOCK_EXTRACT_DIR/vendor/build.prop"
if [ -f "$VENDOR_PROP" ]; then
    # 启用 A2DP 采样率协商
    sed -i '/^persist.vendor.bt.aac_vbr_frm_ctl.enabled=true/a persist.vendor.bt.a2dp.samplerate.supported=true' "$VENDOR_PROP"
    # 启用 APTX Adaptive 2.2
    sed -i '/^persist.vendor.qcom.bluetooth.aptxadaptiver2_1_support=true/a persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$VENDOR_PROP"
    # 启用蓝牙双模音频（经典 + LE Audio）
    sed -i '/^persist.bluetooth.a2dp_offload.cap=sbc-aac-aptx-aptxhd-ldac-lhdc/a persist.bluetooth.enable_dual_mode_audio=true' "$VENDOR_PROP"
    # 启用 vulkan 渲染
    sed -i 's/ro.hwui.use_vulkan=.*/ro.hwui.use_vulkan=true/' "$VENDOR_PROP"
    echo "  vendor/build.prop 修改完成"
else
    warn_skip "$VENDOR_PROP 不存在"
fi

# ======================== odm/build.prop 修改 ========================
echo -e "\n===== 修改 odm/build.prop ====="
if [ -f "$BUILD_PROP_ODM" ]; then
    # 解锁扬声器清理
    sed -i '/^ro.vendor.touchfeature.type=183/a ro.vendor.audio.clean_speaker=true' "$BUILD_PROP_ODM"
    # 修复小米贴贴分享
    sed -i '/ro\.vendor\.nfc\.dispatch_optim/a ro.vendor.nfc.mitouch=1' "$BUILD_PROP_ODM"
    # 解锁新版 NFC 读写勿扰 2.0
    sed -i 's/ro.vendor.nfc.dispatch_optim=[^ ]*/ro.vendor.nfc.dispatch_optim=2/' "$BUILD_PROP_ODM"
    # 启用护眼模式 v4
    sed -i '/^ro\.vendor\.display\.set_fps_stat_timer_ms=250/i ro.vendor.display.optimize_eyecare_v4.enable=true' "$BUILD_PROP_ODM"

    # 恢复静止刷新率下限为 1Hz
    case "$DEVICE_TYPE" in
        nuwa)  idle_rate="60,1:492" ;;
        ishtar) idle_rate="60,1:528" ;;
        *)     idle_rate= ;;
    esac
    if [ -n "$idle_rate" ]; then
        sed -i "s/^ro\.vendor\.display\.primary_idle_refresh_rate=.*/ro.vendor.display.primary_idle_refresh_rate=${idle_rate}/" "$BUILD_PROP_ODM"
        echo "  已设置静止刷新率：$idle_rate"
    fi

    echo "  odm/build.prop 修改完成"
else
    warn_skip "$BUILD_PROP_ODM 不存在"
fi

# ======================== 添加 UWB 硬件特性声明 ========================
echo -e "\n===== 添加 UWB 硬件特性声明 ====="
mkdir -p "$STOCK_EXTRACT_DIR/odm/etc/permissions"
cp -f ./common_files/android.hardware.uwb.xml "$STOCK_EXTRACT_DIR/odm/etc/permissions/"

# ======================== 修复震动 ========================
echo -e "\n===== 修复震动 ====="
VIBRATOR_SRC="./common_files/FixVibrator"
# .rc 内服务路径固定为 /odm/bin/hw，因此 alias 装进 odm 分区
VIBRATOR_MANIFEST="$STOCK_EXTRACT_DIR/odm/etc/vintf/manifest/vendor.xiaomi.hardware.vibratorfeature.service.xml"
ODM_FS_CONFIG="$STOCK_EXTRACT_DIR/config/odm_fs_config"
ODM_FILE_CONTEXTS="$STOCK_EXTRACT_DIR/config/odm_file_contexts"

if [ -f "$VIBRATOR_SRC/vendor.vibrator-default-alias" ] && [ -f "$VIBRATOR_SRC/vendor.vibrator-default-alias.rc" ]; then
    # 允许 hal_vibrator_default 对自身域发起 binder 调用（odm 策略是 vendor sepolicy 的扩展，规则写 vendor cil）
    VENDOR_SEPOLICY_CIL="$STOCK_EXTRACT_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
    if [ -f "$VENDOR_SEPOLICY_CIL" ]; then
        echo "(allow hal_vibrator_default hal_vibrator_default (binder (call transfer)))" >> "$VENDOR_SEPOLICY_CIL"
    else
        warn_skip "$VENDOR_SEPOLICY_CIL 不存在"
    fi
    # 策略已更新，删除 vendor/odm 预编译 sepolicy
    find "$STOCK_EXTRACT_DIR/vendor" "$STOCK_EXTRACT_DIR/odm" -type f -name "*precompiled_sepolicy*" -delete
    # 复制 alias 服务文件（用 cp 保留 common_files 原件，便于重复打包）
    mkdir -p "$STOCK_EXTRACT_DIR/odm/bin/hw" "$STOCK_EXTRACT_DIR/odm/etc/init"
    cp -f "$VIBRATOR_SRC/vendor.vibrator-default-alias" "$STOCK_EXTRACT_DIR/odm/bin/hw/"
    cp -f "$VIBRATOR_SRC/vendor.vibrator-default-alias.rc" "$STOCK_EXTRACT_DIR/odm/etc/init/"
    # 在 vibratorfeature 服务的 VINTF 清单中追加 default 实例
    if [ -f "$VIBRATOR_MANIFEST" ]; then
        sed -Ei '/<fqname>[[:space:]]*IVibrator\/vibratorfeature[[:space:]]*<\/fqname>/a\        <fqname>IVibrator/default</fqname>' "$VIBRATOR_MANIFEST"
    else
        warn_skip "$VIBRATOR_MANIFEST 不存在"
    fi
    # 注册 fs_config 权限与 SELinux 上下文
    if [ -f "$ODM_FS_CONFIG" ] && [ -f "$ODM_FILE_CONTEXTS" ]; then
        echo "odm/bin/hw/vendor.vibrator-default-alias 0 2000 0755" >> "$ODM_FS_CONFIG"
        echo "/odm/bin/hw/vendor\.vibrator-default-alias u:object_r:hal_vibrator_default_exec:s0" >> "$ODM_FILE_CONTEXTS"
        echo "odm/etc/init/vendor.vibrator-default-alias.rc 0 0 0644" >> "$ODM_FS_CONFIG"
        echo "/odm/etc/init/vendor\.vibrator-default-alias\.rc u:object_r:vendor_configs_file:s0" >> "$ODM_FILE_CONTEXTS"
    else
        warn_skip "config 下缺少 odm_fs_config / odm_file_contexts"
    fi
    echo "  震动修复完成"
else
    warn_skip "$VIBRATOR_SRC 下缺少 alias 文件"
fi

# ======================== 解锁控制中心透明效果 ========================
echo -e "\n===== 解锁控制中心透明效果 ====="
OVERLAY_DIR="$MIGRATION_EXTRACT_DIR/product/overlay"
OVERLAY_APK="HawthorneXiaomiSystemUIOverlay.apk"

if [ -f "./common_files/$OVERLAY_APK" ]; then
    mkdir -p "$OVERLAY_DIR"
    cp -f "./common_files/$OVERLAY_APK" "$OVERLAY_DIR/"
    echo "  Overlay 文件已复制"
else
    warn_skip "./common_files/$OVERLAY_APK 不存在"
fi

# ======================== 修复支付宝 & 微信指纹支付 ========================
echo -e "\n===== 修复支付宝 & 微信指纹支付 ====="
for svc in IFAAService SoterService; do
    src="$STOCK_EXTRACT_DIR/product/app/$svc"
    dst="$MIGRATION_EXTRACT_DIR/product/app/$svc"
    if [ -d "$src" ]; then
        rm -rf "$dst"
        cp -rf "$src" "$dst"
        echo "  已复制：$svc"
    else
        warn_skip "$src 不存在"
    fi
done

# ======================== 替换底包 Overlay ========================
echo -e "\n===== 替换底包 Overlay ====="
OVERLAY_APKS=(
    AospFrameworkResOverlay AospWifiResOverlay DevicesAndroidOverlay
    DevicesOverlay MiuiFrameworkResOverlay SettingsRroDeviceHideStatusBarOverlay
    SettingsRroDeviceTypeOverlay MiuiFrameworkTelephonyResOverlay
    MiuiBtRRODeviceConfigOverlay SettingsRroDeviceConfigOverlay
)
STOCK_OVERLAY="$STOCK_EXTRACT_DIR/product/overlay"
for apk in "${OVERLAY_APKS[@]}"; do
    [ -f "$STOCK_OVERLAY/${apk}.apk" ] && mv -f "$STOCK_OVERLAY/${apk}.apk" "$OVERLAY_DIR/"
done
echo "  底包 Overlay 替换完成"

# ======================== 去除屏幕刘海切换 ========================
echo -e "\n===== 去除屏幕刘海切换 ====="
MOD_DIR="./mod"
OVERLAY_NAME="SettingsRroDeviceTypeOverlay"
OVERLAY_APK="${OVERLAY_NAME}.apk"
APK_EDITOR="java -jar ./tools/jar/APKEditor.jar"
TARGET_APK_PATH="$OVERLAY_DIR/${OVERLAY_APK}"
BOOLS_XML="${MOD_DIR}/${OVERLAY_NAME}/resources/package_1/res/values/bools.xml"
PUBLIC_XML="${MOD_DIR}/${OVERLAY_NAME}/resources/package_1/res/values/public.xml"

if [ ! -f "$TARGET_APK_PATH" ]; then
    warn_skip "目标 APK 不存在：$TARGET_APK_PATH"
elif ! [ -f "./tools/jar/APKEditor.jar" ]; then
    warn_skip "APKEditor.jar 不存在"
else
    mkdir -p "$MOD_DIR"
    mv -f "$TARGET_APK_PATH" "$MOD_DIR/" || error_exit "移动 APK 失败"

    ${APK_EDITOR} d -f -i "$MOD_DIR/$OVERLAY_APK" -o "$MOD_DIR/$OVERLAY_NAME" 2>&1 1>/dev/null \
        || error_exit "反编译失败"

    # 修改 bools.xml
    if grep -q 'config_show_softap_wifi6' "$BOOLS_XML" 2>/dev/null; then
        sed -i '/<bool name="config_show_softap_wifi6">true<\/bool>/a \
        <bool name="config_device_support_force_black">false</bool>' "$BOOLS_XML"
    else
        sed -i '$a \
        <bool name="config_device_support_force_black">false</bool>' "$BOOLS_XML"
    fi

    # 动态生成 public.xml 的 ID
    max_id=$(grep -E 'type="bool" name=' "$PUBLIC_XML" 2>/dev/null | \
             sed -n 's/.*id="0x\([0-9a-f]\+\)".*/\1/p' | sort -nr | head -1)
    [ -z "$max_id" ] && new_id="7f010000" || new_id=$(printf "%.8x" $((16#${max_id} + 1)))

    if grep -q 'config_global_support_slm' "$PUBLIC_XML" 2>/dev/null; then
        sed -i "/<public id=\"0x7f010000\" type=\"bool\" name=\"config_global_support_slm\" \/>/a \
        <public id=\"0x${new_id}\" type=\"bool\" name=\"config_device_support_force_black\" \/>" "$PUBLIC_XML"
    else
        sed -i "\$a \
        <public id=\"0x${new_id}\" type=\"bool\" name=\"config_device_support_force_black\" />" "$PUBLIC_XML"
    fi

    # 重新编译 + 替换
    ${APK_EDITOR} b -f -i "$MOD_DIR/$OVERLAY_NAME" -o "$MOD_DIR/${OVERLAY_NAME}_modified.apk" 2>&1 1>/dev/null \
        || error_exit "编译失败"
    mv -f "$MOD_DIR/${OVERLAY_NAME}_modified.apk" "$TARGET_APK_PATH"
    rm -rf "$MOD_DIR"
    echo "  屏幕刘海配置处理完成"
fi

# ======================== ZRAM 1:1 调整 ========================
echo -e "\n===== ZRAM 1:1 调整 ====="
ZRAM_CONF="$MIGRATION_EXTRACT_DIR/system_ext/etc/perfinit_bdsize_zram.conf"
if [ -f "$ZRAM_CONF" ] && command -v jq &>/dev/null; then
    mkdir -p ./tmp
    cp -f "$ZRAM_CONF" ./tmp/
    jq '.zram += [{"product_name": ["umi","cmi","cas","apollo","thyme","alioth","munch","venus","mars","star","odin","fuxi","nuwa","ishtar"], "zram_size": {"6": 6144, "8": 8192, "12": 12288, "16": 16384, "24": 24576}}]' ./tmp/perfinit_bdsize_zram.conf > ./tmp/perfinit_bdsize_zram_out.conf
    cp -f ./tmp/perfinit_bdsize_zram_out.conf "$ZRAM_CONF"
    rm -rf ./tmp
    echo "  ZRAM 配置完成"
else
    warn_skip "ZRAM 配置文件或 jq 不存在"
fi

# ======================== 添加性能等级支持 ========================
echo -e "\n===== 修改性能等级配置 ====="
comment_props "$PRODUCT_PROP" \
    "ro\.vendor\.media_performance_class=35" \
    "ro\.odm\.build\.media_performance_class=35"

if [ -f "$BUILD_PROP_ODM" ]; then
    if grep -q "^ro.odm.build.version.sdk=33" "$BUILD_PROP_ODM" && \
       ! grep -q "^ro.odm.build.media_performance_class=33" "$BUILD_PROP_ODM"; then
        sed -i '/^ro.odm.build.version.sdk=33/a ro.odm.build.media_performance_class=33' "$BUILD_PROP_ODM"
        echo "  已添加 media_performance_class=33"
    fi
fi

# ======================== 优化核心分配 ========================
echo -e "\n===== 优化核心分配 ====="
declare -A REPLACE_RULES=(
    ["persist.sys.dexpreload.other_cores"]="0-6"
    ["persist.sys.dexpreload.cpu_cores"]="0-7"
    ["persist.sys.dexpreload.big_prime_cores"]="7"
)

if [ -f "$PRODUCT_PROP" ]; then
    for key in "${!REPLACE_RULES[@]}"; do
        value="${REPLACE_RULES[$key]}"
        sed -i "s/^${key}=.*/${key}=${value}/" "$PRODUCT_PROP"
    done
    # 注释掉 affinity 配置
    sed -i 's/^\(ro\.miui\.affinity\.sfui=\)/# \1/' "$PRODUCT_PROP"
    sed -i 's/^\(ro\.miui\.affinity\.sfre=\)/# \1/' "$PRODUCT_PROP"
    echo "  核心分配优化完成"
else
    warn_skip "$PRODUCT_PROP 不存在"
fi

# 追加 HyperOS Core allocation
if [ -f "$SYSTEM_EXT_PROP" ]; then
    sed -i '$a \
# Hawthorne added for Xiaomi HyperOS Core allocation \
persist.vendor.display.miui.composer_boost=4-7 \
persist.sys.miui_animator_sched.big_prime_cores=3-7 \
persist.sys.miui_animator_sched.sched_threads=2 \
persist.sys.miui_animator_sched.bigcores=3-6' "$SYSTEM_EXT_PROP"
fi

# ======================== 常规修改（build date / user） ========================
echo -e "\n===== 常规修改（build date / user） ====="
NEW_BUILD_USER="Hawthorne"
BUILD_TIME=$(date)
BUILD_UTC=$(date +%s)

declare -A BUILD_PROP_RULES=(
    ["${MIGRATION_EXTRACT_DIR}/system/system/build.prop"]="ro.build.user ro.system.build.date ro.system.build.date.utc ro.build.date ro.build.date.utc"
    ["${STOCK_EXTRACT_DIR}/system_dlkm/etc/build.prop"]="ro.system_dlkm.build.date ro.system_dlkm.build.date.utc"
    ["${STOCK_EXTRACT_DIR}/vendor/build.prop"]="ro.vendor.build.date ro.vendor.build.date.utc"
    ["${STOCK_EXTRACT_DIR}/vendor_dlkm/etc/build.prop"]="ro.vendor_dlkm.build.date ro.vendor_dlkm.build.date.utc"
    ["${MIGRATION_EXTRACT_DIR}/system_ext/etc/build.prop"]="ro.system_ext.build.date ro.system_ext.build.date.utc"
    ["${MIGRATION_EXTRACT_DIR}/product/etc/build.prop"]="ro.product.build.date ro.product.build.date.utc"
    ["${STOCK_EXTRACT_DIR}/odm/etc/build.prop"]="ro.odm.build.date ro.odm.build.date.utc"
)

for prop_file in "${!BUILD_PROP_RULES[@]}"; do
    [ ! -f "$prop_file" ] && continue
    for prop in ${BUILD_PROP_RULES[$prop_file]}; do
        if [ "$prop" = "ro.build.user" ]; then
            new_value="$NEW_BUILD_USER"
        elif [[ "$prop" == *.utc ]]; then
            new_value="$BUILD_UTC"
        else
            new_value="$BUILD_TIME"
        fi
        if grep -q "^${prop}=" "$prop_file"; then
            sed -i "s/^${prop}=.*/${prop}=${new_value}/" "$prop_file"
        fi
    done
done
echo "  常规修改完成"

# ======================== 自定义版本号 ========================
echo -e "\n===== 自定义版本号 ====="
OLD_VERSION1_FILE="$MIGRATION_EXTRACT_DIR/mi_ext/etc/build.prop"
OLD_VERSION2_FILE="$STOCK_EXTRACT_DIR/mi_ext/etc/build.prop"

[ -f "$OLD_VERSION1_FILE" ] && OLD_VERSION1=$(grep "^ro.mi.os.version.incremental=" "$OLD_VERSION1_FILE" | cut -d'=' -f2) \
    || error_exit "无法获取 OLD_VERSION1"
[ -f "$OLD_VERSION2_FILE" ] && OLD_VERSION2=$(grep "^ro.mi.os.version.incremental=" "$OLD_VERSION2_FILE" | cut -d'=' -f2) \
    || error_exit "无法获取 OLD_VERSION2"

echo "  旧版本号（Migration）：$OLD_VERSION1"
echo "  旧版本号（Stock）：$OLD_VERSION2"

while true; do
    read -p "请输入新版本号（例如 OS3.0.251001.0.WMBCNXM）：" NEW_VERSION
    [ -n "$NEW_VERSION" ] && break
    echo "  版本号不能为空，请重新输入"
done
echo "  新版本号：$NEW_VERSION"

# 版本号替换任务
DEVICE_NAME_OLD="$MIGRATION_EXTRACT_DIR"
DEVICE_NAME_NEW="$STOCK_EXTRACT_DIR"

declare -A TASKS=(
    ["$MIGRATION_EXTRACT_DIR/mi_ext/etc/build.prop"]="ro.mi.os.version.incremental=$NEW_VERSION;ro.product.mod_device=$DEVICE_NAME_NEW;$OLD_VERSION1|$NEW_VERSION"
    ["$MIGRATION_EXTRACT_DIR/product/etc/build.prop"]="$DEVICE_NAME_OLD|$DEVICE_NAME_NEW;$OLD_VERSION1|$NEW_VERSION"
    ["$MIGRATION_EXTRACT_DIR/system/system/build.prop"]="$OLD_VERSION1|$NEW_VERSION"
    ["$MIGRATION_EXTRACT_DIR/system_ext/etc/build.prop"]="$OLD_VERSION1|$NEW_VERSION"
    ["$STOCK_EXTRACT_DIR/system_dlkm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
    ["$STOCK_EXTRACT_DIR/vendor_dlkm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
    ["$STOCK_EXTRACT_DIR/vendor/odm_dlkm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
    ["$STOCK_EXTRACT_DIR/vendor/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
    ["$STOCK_EXTRACT_DIR/odm/etc/build.prop"]="$OLD_VERSION2|$NEW_VERSION"
)

echo -e "\n===== 开始系统配置批量更新 ====="
for file in "${!TASKS[@]}"; do
    [ ! -f "$file" ] && continue

    operations="${TASKS[$file]}"
    IFS=';' read -ra OP_ARR <<< "$operations"

    for op in "${OP_ARR[@]}"; do
        if [[ "$op" == *"="* ]]; then
            key="${op%=*}"; value="${op#*=}"
            sed -i "s/^${key}=.*/${key}=${value}/" "$file"
        elif [[ "$op" == *"|"* ]]; then
            old_str="${op%|*}"; new_str="${op#*|}"
            sed -i "s/${old_str}/${new_str}/g" "$file"
        fi
    done
done
echo "  配置更新完成"

# ======================== 清理底包 mi_ext ========================
echo -e "\n===== 清理底包 mi_ext ====="
rm -rf "$STOCK_EXTRACT_DIR/mi_ext"
echo "  已清理底包 mi_ext（AI 模型与版本号均已取用）"

# ======================== snapshot 修复 ========================
echo -e "\n===== snapshot 修复 ====="

if ! command -v cpio &>/dev/null; then
    warn_skip "未安装 cpio，跳过 snapshot 修复"
elif [ ! -f "$STOCK_EXTRACT_DIR/init_boot.img" ]; then
    warn_skip "底包 init_boot.img 不存在，跳过 snapshot 修复"
elif [ ! -f "$MIGRATION_EXTRACT_DIR/init_boot.img" ]; then
    warn_skip "移植包 init_boot.img 不存在，跳过 snapshot 修复"
else
    rm -rf ./init_boot_bottom ./init_boot_target
    mkdir -p ./init_boot_bottom ./init_boot_target
    cp -f "$STOCK_EXTRACT_DIR/init_boot.img" ./init_boot_bottom/
    cp -f "$MAGISKBOOT" ./init_boot_bottom/
    cp -f "$MIGRATION_EXTRACT_DIR/init_boot.img" ./init_boot_target/
    cp -f "$MAGISKBOOT" ./init_boot_target/

    # 解包底包 init_boot ramdisk
    cd ./init_boot_bottom
    ./magiskboot unpack -h ./init_boot.img
    comp=$(./magiskboot decompress ./ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
    if [ "$comp" ]; then
        mv -f ./ramdisk.cpio ./ramdisk.cpio.$comp
        ./magiskboot decompress ./ramdisk.cpio.$comp ./ramdisk.cpio
        if [ $? != 0 ] && $comp --help 2>/dev/null; then
            $comp -dc ./ramdisk.cpio.$comp > ./ramdisk.cpio
        fi
    fi
    mkdir -p ramdisk
    chmod 755 ramdisk
    cd ramdisk
    EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i
    bottom_comp="$comp"

    # 解包移植包 init_boot ramdisk
    cd "$BUILD_ROOT/init_boot_target"
    ./magiskboot unpack -h ./init_boot.img
    target_comp=$(./magiskboot decompress ./ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
    if [ "$target_comp" ]; then
        mv -f ./ramdisk.cpio ./ramdisk.cpio.$target_comp
        ./magiskboot decompress ./ramdisk.cpio.$target_comp ./ramdisk.cpio
        if [ $? != 0 ] && $target_comp --help 2>/dev/null; then
            $target_comp -dc ./ramdisk.cpio.$target_comp > ./ramdisk.cpio
        fi
    fi
    mkdir -p ramdisk
    chmod 755 ramdisk
    cd ramdisk
    EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i

    # 用移植包的 system/bin 覆盖底包 init_boot ramdisk 中的对应目录
    if [ ! -d "$BUILD_ROOT/init_boot_bottom/ramdisk/system" ] || [ ! -d "$BUILD_ROOT/init_boot_target/ramdisk/system/bin" ]; then
        warn_skip "init_boot ramdisk 解包异常，保留原底包 init_boot"
    else
        cp -af "$BUILD_ROOT/init_boot_target/ramdisk/system/bin" "$BUILD_ROOT/init_boot_bottom/ramdisk/system"

        # 重新打包底包 init_boot（回写提取目录，随 firmware 目录进最终包）
        cd "$BUILD_ROOT/init_boot_bottom/ramdisk"
        find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
        cd "$BUILD_ROOT/init_boot_bottom"
        if [ "$bottom_comp" ]; then
            ./magiskboot compress=$bottom_comp ./ramdisk_new.cpio
            if [ $? != 0 ] && $bottom_comp --help 2>/dev/null; then
                $bottom_comp -9c ./ramdisk_new.cpio > ./ramdisk.cpio.$bottom_comp
            fi
        fi
        new_ramdisk=$(ls ./ramdisk_new.cpio* 2>/dev/null | tail -n1)
        if [ "$new_ramdisk" ]; then
            cp -f "$new_ramdisk" ./ramdisk.cpio
            nocompflag=
            case $bottom_comp in
                cpio) nocompflag="-n" ;;
            esac
            ./magiskboot repack $nocompflag ./init_boot.img "$BUILD_ROOT/$STOCK_EXTRACT_DIR/init_boot.img"
            echo "  snapshot 修复完成"
        else
            warn_skip "ramdisk 重新打包失败，保留原底包 init_boot"
        fi
    fi

    # 清理临时目录与移植包 init_boot
    cd "$BUILD_ROOT"
    rm -rf ./init_boot_bottom ./init_boot_target "$MIGRATION_EXTRACT_DIR/init_boot.img"
fi

# ======================== mi_product 挂载修复 ========================
echo -e "\n===== mi_product 挂载修复 ====="
STOCK_FSTAB="$STOCK_EXTRACT_DIR/vendor/etc/fstab.qcom"

# 从移植包提取 mi_product 分区镜像（HyperOS 4 新增分区，后面原样并入 super.img）
if ./tools/binary/payload_extract -i "$MIGRATION_ZIP" -t zip -o "$MIGRATION_EXTRACT_DIR" -X mi_product -T0 -s; then
    echo "  已提取 mi_product.img"
else
    warn_skip "移植包无 mi_product 分区"
fi

if ! command -v cpio &>/dev/null; then
    warn_skip "未安装 cpio，跳过 mi_product 挂载修复"
elif [ ! -f "$STOCK_FSTAB" ]; then
    warn_skip "底包 fstab.qcom 不存在，跳过 mi_product 挂载修复"
elif [ ! -f "$STOCK_EXTRACT_DIR/vendor_boot.img" ]; then
    warn_skip "底包 vendor_boot.img 不存在，跳过 mi_product 挂载修复"
else
    # 修补 fstab.qcom：克隆 mi_ext 条目为 mi_product，插入到 mi_ext 行之后
    cp -f "$STOCK_FSTAB" ./fstab.qcom
    origin_line=$(grep -n "^/mnt/vendor/mi_ext.*/mi_ext.*erofs" ./fstab.qcom | tail -1 | cut -d: -f1)
    grep -E "^(mi_ext |/mnt/vendor/mi_ext +/mi_ext )" ./fstab.qcom | sed 's/mi_ext/mi_product/g' > ./mi_product_block.txt

    if [ -z "$origin_line" ]; then
        warn_skip "fstab.qcom 中未找到 mi_ext erofs 挂载行，跳过 mi_product 挂载修复"
    else
        sed -i "${origin_line}r ./mi_product_block.txt" ./fstab.qcom
        rm -f ./mi_product_block.txt

        # 修补底包 vendor_boot
        rm -rf ./vendor_boot
        mkdir -p ./vendor_boot
        cp -f "$STOCK_EXTRACT_DIR/vendor_boot.img" ./vendor_boot/vendor_boot.img
        cp -f "$MAGISKBOOT" ./vendor_boot/

        cd ./vendor_boot
        ./magiskboot unpack -h ./vendor_boot.img
        # 兼容不同 magiskboot 构建：新版布局输出 vendor_ramdisk/ramdisk.cpio，旧版直接输出 ramdisk.cpio
        if [ -f ./vendor_ramdisk/ramdisk.cpio ]; then
            RAMDISK_DIR="./vendor_ramdisk"
        else
            RAMDISK_DIR="."
        fi
        comp=$(./magiskboot decompress "$RAMDISK_DIR/ramdisk.cpio" 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
        if [ "$comp" ]; then
            mv -f "$RAMDISK_DIR/ramdisk.cpio" "$RAMDISK_DIR/ramdisk.cpio.$comp"
            ./magiskboot decompress "$RAMDISK_DIR/ramdisk.cpio.$comp" "$RAMDISK_DIR/ramdisk.cpio"
            if [ $? != 0 ] && $comp --help 2>/dev/null; then
                $comp -dc "$RAMDISK_DIR/ramdisk.cpio.$comp" > "$RAMDISK_DIR/ramdisk.cpio"
            fi
        fi
        mkdir -p ramdisk
        chmod 755 ramdisk
        cd ramdisk
        EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F "../$RAMDISK_DIR/ramdisk.cpio" -i

        # 写入修补后的 fstab 到 first_stage_ramdisk
        if [ ! -d "$BUILD_ROOT/vendor_boot/ramdisk/first_stage_ramdisk" ]; then
            warn_skip "vendor_boot ramdisk 无 first_stage_ramdisk，保留原底包 vendor_boot"
        else
            cp -af "$BUILD_ROOT/fstab.qcom" "$BUILD_ROOT/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom"

            cd "$BUILD_ROOT/vendor_boot/ramdisk"
            find | sed 1d | cpio -H newc -R 0:0 -o -F "../$RAMDISK_DIR/ramdisk_new.cpio"
            cd "$BUILD_ROOT/vendor_boot"
            if [ "$comp" ]; then
                ./magiskboot compress=$comp "$RAMDISK_DIR/ramdisk_new.cpio"
                if [ $? != 0 ] && $comp --help 2>/dev/null; then
                    $comp -9c "$RAMDISK_DIR/ramdisk_new.cpio" > "$RAMDISK_DIR/ramdisk.cpio.$comp"
                fi
            fi
            new_ramdisk=$(ls "$RAMDISK_DIR"/ramdisk_new.cpio* 2>/dev/null | tail -n1)
            if [ "$new_ramdisk" ]; then
                cp -f "$new_ramdisk" "$RAMDISK_DIR/ramdisk.cpio"
                nocompflag=
                case $comp in
                    cpio) nocompflag="-n" ;;
                esac
                ./magiskboot repack $nocompflag ./vendor_boot.img "$BUILD_ROOT/$STOCK_EXTRACT_DIR/vendor_boot.img"
                echo "  mi_product 挂载修复完成"
            else
                warn_skip "vendor_ramdisk 重新打包失败，保留原底包 vendor_boot"
            fi
        fi
    fi

    # 清理临时文件与工作目录
    rm -f ./fstab.qcom ./mi_product_block.txt
    cd "$BUILD_ROOT"
    rm -rf ./vendor_boot
fi

# ======================== 解压刷机脚本 & Recovery ========================
echo -e "\n===== 解压刷机脚本 & Recovery ====="
RECOVERY_SRC="./tools/recovery"
RECOVERY_DST="$STOCK_EXTRACT_DIR/recovery.img"
rm -f "$RECOVERY_DST"

case "$DEVICE_TYPE" in
    fuxi)
        RECOVERY_FILE="[REC]3.7.1_12-Mi13_v9.0_A16-fuxi-skkk.img" ;;
    nuwa)
        RECOVERY_FILE="[REC]3.7.1_12-Mi13Pro_v9.0_A16-nuwa-skkk.img" ;;
    ishtar)
        RECOVERY_FILE="[REC]3.7.1_12-Mi13Ultra_v9.0_A16-ishtar-skkk.img" ;;
    *) RECOVERY_FILE= ;;
esac

if [ -n "$RECOVERY_FILE" ]; then
    if [ -f "$RECOVERY_SRC/$RECOVERY_FILE" ]; then
        cp "$RECOVERY_SRC/$RECOVERY_FILE" "$RECOVERY_DST"
        echo "  Recovery 已复制"
    else
        error_exit "Recovery 文件不存在：$RECOVERY_SRC/$RECOVERY_FILE"
    fi
else
    warn_skip "未识别设备型号，跳过 Recovery"
fi

# ======================== 适配刷机脚本 ========================
mkdir -p "$STOCK_EXTRACT_DIR/firmware"
mv "$STOCK_EXTRACT_DIR"/*.img "$STOCK_EXTRACT_DIR/firmware/" 2>/dev/null

unzip -o -q ./tools/flashscript/flashtools.zip -d ./output
mv "$STOCK_EXTRACT_DIR/firmware" ./output/firmware
cp -f ./common_files/cust.img ./output/firmware

FLASH_BAT="./output/FlashWindows.bat"
UPDATE_BINARY="./output/META-INF/com/google/android/update-binary"

# 仅 fuxi/ishtar 需要将刷机脚本中的 nuwa 替换为实际设备名
case "$DEVICE_TYPE" in
    fuxi|ishtar)
        for script_file in "$FLASH_BAT" "$UPDATE_BINARY"; do
            [ -f "$script_file" ] && sed -i "s/nuwa/$DEVICE_TYPE/g" "$script_file"
        done
        echo "  刷机脚本已适配（nuwa → $DEVICE_TYPE）"
        ;;
    nuwa)
        echo "  nuwa 设备，刷机脚本无需修改"
        ;;
esac

# ======================== 修补文件上下文 ========================
echo -e "\n===== 修补文件上下文 ====="
FSPATCH_TOOL="./tools/python/fspatch.py"
CONTEXTPATCH_TOOL="./tools/python/contextpatch.py"

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

total=$(( ${#PARTITIONS[@]} * 2 ))
current=0
for item in "${PARTITIONS[@]}"; do
    partition="${item%:*}"
    root_dir_var="${item#*:}"
    root_dir="${!root_dir_var}"

    fs_config_path="${root_dir}/config/${partition}_fs_config"
    context_path="${root_dir}/config/${partition}_file_contexts"
    target_dir="${root_dir}/${partition}"

    [ ! -d "$target_dir" ] && continue

    current=$((current + 1))
    echo -e "  [$current/$total] fspatch：${partition}"
    python3 "$FSPATCH_TOOL" "$target_dir" "$fs_config_path" 2>/dev/null

    current=$((current + 1))
    echo "  [$current/$total] contextpatch：${partition}"
    python3 "$CONTEXTPATCH_TOOL" "$target_dir" "$context_path" 2>/dev/null
done
echo -e "  补丁处理完毕"

# ======================== 打包 EROFS 镜像 ========================
echo -e "\n===== 打包 EROFS 镜像 ====="
MKFS_EROFS_TOOL="./tools/binary/mkfs.erofs"
COMMON_ARGS=(-zlz4hc,9 -T 1230768000 --quiet)

for item in "${PARTITIONS[@]}"; do
    partition="${item%:*}"
    root_dir_var="${item#*:}"
    root_dir="${!root_dir_var}"

    fs_config_path="${root_dir}/config/${partition}_fs_config"
    context_path="${root_dir}/config/${partition}_file_contexts"
    source_dir="${root_dir}/${partition}"
    output_img="${root_dir}/${partition}.img"

    [ ! -d "$source_dir" ] && { warn_skip "${partition} 源目录不存在"; continue; }
    [ ! -f "$fs_config_path" ] || [ ! -f "$context_path" ] && { warn_skip "${partition} 配置文件缺失"; continue; }

    echo -e "  打包 ${partition}..."
    "$MKFS_EROFS_TOOL" "${COMMON_ARGS[@]}" \
        --mount-point "/${partition}" \
        --fs-config-file "$fs_config_path" \
        --file-contexts "$context_path" \
        "$output_img" "$source_dir" && echo "    ${partition} 镜像生成成功" || echo "    ${partition} 镜像生成失败"
done

# ======================== 打包 super.img ========================
echo -e "\n===== 打包 super.img ====="
get_size() { stat --format="%s" "$1" 2>/dev/null || echo 0; }

mi_ext_size=$(get_size "$MIGRATION_EXTRACT_DIR/mi_ext.img")
odm_size=$(get_size "$STOCK_EXTRACT_DIR/odm.img")
product_size=$(get_size "$MIGRATION_EXTRACT_DIR/product.img")
system_size=$(get_size "$MIGRATION_EXTRACT_DIR/system.img")
system_ext_size=$(get_size "$MIGRATION_EXTRACT_DIR/system_ext.img")
vendor_size=$(get_size "$STOCK_EXTRACT_DIR/vendor.img")
vendor_dlkm_size=$(get_size "$STOCK_EXTRACT_DIR/vendor_dlkm.img")
system_dlkm_size=$(get_size "$STOCK_EXTRACT_DIR/system_dlkm.img")

# mi_product 分区（HyperOS 4 移植包才有；fstab 条目指向 /dev/block/mapper/mi_product_a，须在 super 中存在）
MI_PRODUCT_LPMAKE_ARGS=()
if [ -f "$MIGRATION_EXTRACT_DIR/mi_product.img" ]; then
    mi_product_size=$(get_size "$MIGRATION_EXTRACT_DIR/mi_product.img")
    MI_PRODUCT_LPMAKE_ARGS=(
        --partition mi_product_a:readonly:"$mi_product_size":qti_dynamic_partitions_a
        --image mi_product_a="$MIGRATION_EXTRACT_DIR/mi_product.img"
        --partition mi_product_b:readonly:0:qti_dynamic_partitions_b
    )
fi

./tools/binary/lpmake --device super:9663676416 --virtual-ab \
    --metadata-size 65536 --super-name super --block-size 4096 --metadata-slots 3 \
    --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$STOCK_EXTRACT_DIR/odm.img" \
    --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$MIGRATION_EXTRACT_DIR/product.img" \
    --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$MIGRATION_EXTRACT_DIR/mi_ext.img" \
    --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$MIGRATION_EXTRACT_DIR/system.img" \
    --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$MIGRATION_EXTRACT_DIR/system_ext.img" \
    --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$STOCK_EXTRACT_DIR/vendor.img" \
    --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$STOCK_EXTRACT_DIR/vendor_dlkm.img" \
    --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$STOCK_EXTRACT_DIR/system_dlkm.img" \
    --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b \
    --partition product_b:readonly:0:qti_dynamic_partitions_b \
    --partition system_b:readonly:0:qti_dynamic_partitions_b \
    --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
    --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b \
    --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b \
    --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
    --partition odm_b:readonly:0:qti_dynamic_partitions_b \
    "${MI_PRODUCT_LPMAKE_ARGS[@]}" \
    --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 \
    -F --output ./output/super.img

# 二次压缩
echo -e "\n===== 压缩 super.img ====="
./tools/binary/zstd -9 -f ./output/super.img -o ./output/super.zst --rm

# ======================== 打包 ZIP ========================
echo -e "\n===== 打包 ZIP ====="
OUTPUT_DIR="./output"
# 从移植包文件名提取版本后缀（如 madrid-ota_full-OS4.0.20.0.XEOCNXM-user-17.0-xxx.zip → user-17.0）
if [[ "$MIGRATION_FILENAME" =~ -user-([0-9]+\.[0-9]+)(-|\.|$) ]]; then
    VERSION_SUFFIX="user-${BASH_REMATCH[1]}"
else
    VERSION_SUFFIX="user-17.0"
    warn_skip "移植包文件名未找到 user-xx.0，使用默认后缀 $VERSION_SUFFIX"
fi
ZIP_BASE_NAME="$STOCK_EXTRACT_DIR-ota_full-$NEW_VERSION-$VERSION_SUFFIX"
ZIP_DIR="./zip"

[ ! -d "$OUTPUT_DIR" ] || [ -z "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ] && error_exit "$OUTPUT_DIR 不存在或为空"
command -v 7z &>/dev/null || error_exit "未找到 7z 命令，请先安装 p7zip-full"
mkdir -p "$ZIP_DIR"

zip_temp="${ZIP_DIR}/${ZIP_BASE_NAME}.zip"
7z a -tzip -mx=6 -bb1 "$zip_temp" "$OUTPUT_DIR"/* || { rm -f "$zip_temp"; error_exit "压缩失败"; }

md5_prefix=$(md5sum "$zip_temp" | awk '{print $1}' | cut -c 1-10)
final_zip="${ZIP_DIR}/${ZIP_BASE_NAME}-${md5_prefix}.zip"
mv "$zip_temp" "$final_zip" || error_exit "重命名失败"

echo -e "\n===== 全部完成 ====="
echo "  最终压缩包：$final_zip"
echo "  文件大小：$(du -h "$final_zip" | awk '{print $1}')"

# 清理
rm -rf "$MIGRATION_EXTRACT_DIR" "$STOCK_EXTRACT_DIR" ./output
