#!/bin/bash

# 更改时区为 Asia/Shanghai
echo "更改时区为 Asia/Shanghai..."
sudo timedatectl set-timezone Asia/Shanghai

# 安装自动构建所需依赖
echo -e "\n=== 开始安装自动构建依赖 ==="

# 依赖列表（按类别分组，清晰可维护）
dependencies=(
    # 基础工具
    "pv" "libarchive-tools" "p7zip-full" "unzip" "cpio" 
    # Java 环境
    "openjdk-25-jre-headless" 
    # 数据处理工具
    "jq" "python3" 
    # 压缩/传输工具
    "lz4" "axel"
)

# 检查 apt 是否可用
if ! command -v apt &> /dev/null; then
    echo "错误：当前系统不支持 apt 包管理器（仅支持 Debian/Ubuntu 系统）"
    exit 1
fi

# 预检查：更新 apt 缓存（可选，提升安装成功率）
echo -e "\n[1/2] 更新 apt 软件包缓存..."
if ! sudo apt update -y; then
    echo "错误：apt 缓存更新失败，请检查网络连接或软件源配置"
    exit 1
fi

# 安装依赖
echo -e "\n[2/2] 开始安装依赖包（共 ${#dependencies[@]} 个）..."
if sudo apt install -y "${dependencies[@]}"; then
    echo -e "\n=== 所有依赖安装成功！==="
else
    echo -e "\n错误：依赖安装失败，请检查上述错误信息并重试"
    exit 1
fi

# 为自动构建需要运行的binary设置权限
echo "=== 开始设置二进制文件权限 ==="

# 需要设置权限的文件列表
files=(
    "./tools/binary/extract.erofs"
    "./tools/binary/lpmake"
    "./tools/binary/magiskboot"
    "./tools/binary/mkfs.erofs"
    "./tools/binary/payload_extract"
    "./tools/binary/zstd"
)

# 循环处理每个文件
for file in "${files[@]}"; do
    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        echo " 警告：文件不存在 - $file"
        continue  # 跳过不存在的文件，继续处理下一个
    fi

    # 尝试设置权限（需要sudo，若用户无权限会提示输入密码）
    echo "正在设置权限：$file"
    if sudo chmod 777 "$file"; then
        echo " 成功设置权限：$file"
    else
        echo " 失败：无法设置 $file 的权限（可能需要管理员权限）"
        exit 1  # 遇到错误时终止脚本（可选：若希望继续处理其他文件，可改为 continue）
    fi
done

echo "=== 所有文件权限设置完成 ==="
