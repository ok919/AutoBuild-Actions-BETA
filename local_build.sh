#!/bin/bash

# 下载本地编译库
# git clone https://github.com/ok919/AutoBuild-Actions-BETA.git
# cd AutoBuild-Actions-BETA

# 添加错误处理，任何命令失败则脚本退出
set -e

# 配置编译环境
echo "INFO: Updating package lists and installing prerequisites..."
sudo apt update
# 其中 lib32gcc-s1 适用于 22.04，lib32gcc1 是适用于 20.04。gcc-multilib 应该能处理好
sudo apt -y install busybox build-essential cmake asciidoc binutils bzip2 gawk gettext git libncurses5-dev libz-dev patch unzip zlib1g-dev lib32gcc-s1 libc6-dev-i386 subversion flex uglifyjs git-core gcc-multilib g++-multilib p7zip p7zip-full msmtp libssl-dev texinfo libreadline-dev libglib2.0-dev xmlto qemu-utils upx libelf-dev autoconf automake libtool autopoint ccache curl wget vim nano python2.7 python3 python3-pip python3-ply haveged lrzsz device-tree-compiler scons antlr3 gperf intltool mkisofs rsync
sudo apt -y autoremove --purge
sudo apt clean

# 配置环境变量
## 请确保 Configs/d-team-newifi-d2-Home 文件存在
CONFIG_FILE="d-team-newifi-d2-Home"
if [ ! -f "Configs/$CONFIG_FILE" ]; then
    echo "ERROR: Config file Configs/$CONFIG_FILE does not exist!"
    exit 1
fi
echo "INFO: Using config file: $CONFIG_FILE"

## 将所有需要导出的变量明确使用 export
# 使用 $(pwd) 比只使用 `pwd` 更安全
export GITHUB_WORKSPACE=$(pwd)
export WORK="${GITHUB_WORKSPACE}/openwrt"
export CONFIG_TEMP="${WORK}/.config"

Rexport REPO_URL="https://github.com/coolsnowwolf/lede"
export REPO_BRANCH=master
export Compile_Date=$(date +%Y%m%d%H%M)
export Display_Date=$(date +%Y/%m/%d)

export GITHUB_ENV="/tmp/local_github_env_vars.txt"
touch $GITHUB_ENV
echo "INFO: GITHUB_ENV set to $GITHUB_ENV"

# 克隆 openwrt 代码库
echo "INFO: Cloning OpenWrt source code from $REPO_URL (branch: $REPO_BRANCH)..."
## 只有当 openwrt 目录不存在时才克隆，或者如果需要总是全新克隆，则在前面删除
if [ -d "openwrt" ]; then
     echo "INFO: openwrt directory already exists. Consider removing it for a fresh clone or pulling updates."
     # rm -rf openwrt # 取消注释以强制全新克隆
fi
if [ ! -d "openwrt" ]; then
    git clone -b $REPO_BRANCH $REPO_URL openwrt
fi

# 进入 openwrt 源码目录
cd openwrt
echo "INFO: Current directory: $(pwd)"
echo "INFO: Updating and installing feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 自定义配置
echo "INFO: Starting custom configuration steps..."
## 第一次复制用于 `make defconfig` 生成运行 `Firmware_Diy_Start` 所需变量
cp $GITHUB_WORKSPACE/Configs/$CONFIG_FILE .config
echo "INFO: Sourcing DIY scripts..."
# 明确脚本的执行上下文，source 命令会影响当前 shell
source "$GITHUB_WORKSPACE/Scripts/local_diy_script.sh"
source "$GITHUB_WORKSPACE/Scripts/local_function.sh"

echo "INFO: Running first 'make defconfig'..."
make defconfig
echo "INFO: Running Firmware_Diy_Start..."
## 此函数内部会 source $GITHUB_ENV
Firmware_Diy_Start
echo "INFO: Resetting .config to seed and running main DIY functions..."
## 第二次复制手于自定义
rm -f .config && cp "$GITHUB_WORKSPACE/Configs/$CONFIG_FILE" .config
Firmware_Diy_Main
Firmware_Diy
Firmware_Diy_Other
echo "INFO: Custom configuration steps finished."

# 生成完整配置然后下载编译
echo "INFO: Installing feeds again and running final 'make defconfig'..."
## 这一步通常是安全的，但可能不是严格必需，因为前面已经执行过
./scripts/feeds install -a
## 第二次，也是最终的 defconfig
make defconfig
echo "INFO: Downloading source code for packages..."
## 可以根据CPU核心数调整
make download -j$(nproc)
echo "INFO: Starting compilation..."
# 可以使用 $(nproc) 自动获取CPU核心数
make -j$(nproc) || make -j1 V=s

echo "INFO: Compilation finished."

# 建议9: 添加固件整理步骤
echo "INFO: Checking out firmware..."
## 这个函数会整理固件到 $WORK/bin/Firmware 目录
Firmware_Diy_End

echo "INFO: Build process complete. Firmware (if successful) should be in $WORK/bin/Firmware/"
echo "Final .config SHA256: $(sha256sum .config)"
echo "Timestamp: $(date)"