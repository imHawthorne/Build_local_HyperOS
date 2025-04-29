#!/bin/bash

# 检查 axel 是否已安装
if ! command -v axel &> /dev/null; then
    echo "axel 需要安装。请使用 'sudo apt install axel' 安装它。"
    exit 1
fi

# 提示用户输入下载链接
echo "请输入下载链接（每个链接用空格分隔）："
read -a urls

# 创建一个临时目录用于存放下载的文件
mkdir -p downloads
cd downloads || exit

# 使用 nproc 获取系统的处理器核心数
threads=$(nproc)

# 使用 axel 进行多线程下载
echo "开始下载，使用 $threads 个线程..."
for url in "${urls[@]}"; do
    axel -n "$threads" "$url" &  # -n 设置使用的线程数
done
wait  # 等待所有后台下载完成

# 返回上级目录
cd ..
echo "所有下载任务已完成！"
