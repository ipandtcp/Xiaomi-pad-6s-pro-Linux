#!/bin/bash
set -e

# ========================================================
# build-ubuntu26-rootfs.sh — Ubuntu 26.04 (Resolute) 构建
# 在 2026-07-02 Kevin Zhu 版本基础上增加“个人预设”注入：
#   - 用户 pp / 密码 1
#   - 恢复当前系统 GNOME 全部设置 (dconf)、扩展、快捷键、终端
#   - fcitx5 拼音输入法 (安装 + 配置)
#   - keepass2、qbootctl
#   - 不预装浏览器 (用户刷机后自行安装)
# ========================================================

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

# ------- 预设 (preset) 参数 -------
USER_NAME="pp"
USER_PASS="1"
ROOT_PASS="1"

# 预设文件目录 (相对本脚本所在目录)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRESET_DIR="$SCRIPT_DIR/gnome-preset"

usage() {
    echo "用法: $0 <kernel_version> <desktop_environment>"
    echo "desktop_environment: gnome, kde 或 xfce"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

KERNEL=$1
DESKTOP_ENV=$2

if [[ ! "$DESKTOP_ENV" =~ ^(gnome|kde|xfce)$ ]]; then
    echo "错误: desktop_environment 必须是 gnome, kde 或 xfce"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 LTS (Resolute) RootFS"
echo "桌面环境: $DESKTOP_ENV"
echo "内核版本: $KERNEL"
echo "用户: $USER_NAME / 密码: $USER_PASS"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$UBUNTU_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 基础软件源
printf "deb %s %s main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list
printf "deb %s %s-backports main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list
printf "deb %s %s-security main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list

chroot rootdir apt update

# ========================================================
# 修复点1：先安装系统核心依赖，再安装内核
# ========================================================
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus kmod initramfs-tools

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
    KERNEL_MODULE_DIR=$(ls rootdir/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   ✅ 动态识别到真实内核版本目录: $KERNEL_MODULE_DIR"
        chroot rootdir /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

# 语言环境 (英文基础 + 中文，供 fcitx5 拼音使用)
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir bash -c "sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/; s/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen || true"
chroot rootdir locale-gen en_US.UTF-8 zh_CN.UTF-8 || chroot rootdir locale-gen en_US.UTF-8

# root 用户初始化
chroot rootdir bash -c "echo -e '${ROOT_PASS}\n${ROOT_PASS}' | passwd root"
echo "ubuntu26-${DESKTOP_ENV}" > rootdir/etc/hostname

# ========================================================
# 📦 桌面环境分支
# ========================================================
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot rootdir apt install -y --no-install-recommends ubuntu-desktop-minimal gnome-terminal firefox gdm3
    DM="gdm3"
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot rootdir apt install -y --no-install-recommends plasma-desktop sddm konsole firefox plasma-workspace systemsettings discover packagekit
    DM="sddm"
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot rootdir apt install -y --no-install-recommends xfce4 xfce4-terminal lightdm lightdm-gtk-greeter firefox mousepad thunar
    DM="lightdm"
fi

# ========================================================
# 🧑 创建用户 pp (密码 1)
# ========================================================
chroot rootdir useradd -m -s /bin/bash "$USER_NAME"
echo "${USER_NAME}:${USER_PASS}" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev "$USER_NAME"

# ========================================================
# 🎨 GNOME 个人预设注入 (仅 gnome 桌面)
# ========================================================
if [ "$DESKTOP_ENV" = "gnome" ]; then
    echo "=========================================="
    echo "🎨 开始注入 GNOME 个人预设 (扩展/快捷键/终端/输入法/壁纸)"
    echo "=========================================="

    # ---- 1. 额外软件包: 输入法 + 扩展 + tweaks + keepass2 + qbootctl + 中文包 ----
    #      注: 不预装 Chromium/Chrome (用户刷机后自行安装)
    chroot rootdir apt install -y --no-install-recommends \
        keepass2 qbootctl \
        fcitx5 fcitx5-chinese-addons fcitx5-frontend-all fcitx5-config-qt \
        fcitx5-module-chttrans fcitx5-module-pinyinhelper fcitx5-module-punctuation \
        gnome-shell-extensions gnome-shell-extension-light-style \
        gnome-shell-ubuntu-extensions gnome-tweaks dconf-cli \
        language-pack-zh-hans language-pack-gnome-zh-hans im-config || true

    # ---- 2. dconf: 恢复全部 GNOME 设置 (系统级默认，作用于新用户 pp) ----
    if [ -f "$PRESET_DIR/dconf-pp.txt" ]; then
        mkdir -p rootdir/etc/dconf/db/local.d rootdir/etc/dconf/profile
        printf 'user-db:user\nsystem-db:local\n' > rootdir/etc/dconf/profile/user
        cp "$PRESET_DIR/dconf-pp.txt" rootdir/etc/dconf/db/local.d/00-pp
        chroot rootdir dconf update || true
        echo "✅ GNOME dconf 设置已注入"
    fi

    # ---- 3. GNOME 扩展: 安装 kimpanel (fcitx5 面板, 用户自装, 非 apt 包) ----
    if [ -d "$PRESET_DIR/kimpanel@kde.org" ]; then
        mkdir -p rootdir/usr/share/gnome-shell/extensions
        cp -r "$PRESET_DIR/kimpanel@kde.org" rootdir/usr/share/gnome-shell/extensions/
        echo "✅ kimpanel 扩展已安装"
    fi

    # ---- 4. fcitx5 配置 + 输入法环境变量 ----
    if [ -d "$PRESET_DIR/fcitx5" ]; then
        mkdir -p rootdir/etc/skel/.config
        mkdir -p rootdir/home/"$USER_NAME"/.config
        cp -r "$PRESET_DIR/fcitx5" rootdir/etc/skel/.config/fcitx5
        cp -r "$PRESET_DIR/fcitx5" rootdir/home/"$USER_NAME"/.config/fcitx5
        chroot rootdir chown -R "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"/.config
        echo "✅ fcitx5 配置已注入"
    fi
    # 输入法环境变量 (全局)
    printf '\n# fcitx5 input method\nGTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\n' >> rootdir/etc/environment
    # 设置默认输入法为 fcitx5
    chroot rootdir bash -c "im-config -n fcitx5 2>/dev/null || true"

    # ---- 5. 壁纸 ----
    if [ -f "$PRESET_DIR/mendhak-Red_Acer.jpg" ]; then
        mkdir -p rootdir/usr/share/backgrounds
        cp "$PRESET_DIR/mendhak-Red_Acer.jpg" rootdir/usr/share/backgrounds/
        echo "✅ 壁纸已注入"
    fi

    echo "🎨 GNOME 个人预设注入完成"
fi

# ========================================================
# ⚙️ 底层硬件自愈与触控校准
# ========================================================
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# 高通 8 Gen 2 WiFi 固件修复
FW_DIR="rootdir/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then
    cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
    echo "✅ board.bin 伪装成功！"
fi
chroot rootdir apt install -y qrtr-tools || true
chroot rootdir systemctl enable qrtr-ns || true
# qbootctl: 标记当前启动槽位为 Good (双系统 A/B 槽位管理)
chroot rootdir systemctl enable qbootctl || true

# ========================================================
# 🔒 自动登录 (pp)
# ========================================================
if [ "$DM" = "gdm3" ]; then
    mkdir -p rootdir/etc/gdm3
    printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=%s\n" "$USER_NAME" > rootdir/etc/gdm3/daemon.conf
    chroot rootdir systemctl enable gdm3
fi

if [ "$DM" = "sddm" ]; then
    mkdir -p rootdir/etc/sddm.conf.d
    printf "[General]\nDisplayServer=x11\nInputMethod=\n" > rootdir/etc/sddm.conf.d/ubuntu-defaults.conf
    printf "[Autologin]\nUser=%s\nSession=plasma\n" "$USER_NAME" > rootdir/etc/sddm.conf.d/autologin.conf
    if chroot rootdir id -u sddm >/dev/null 2>&1; then
        chroot rootdir usermod -aG video,render,input sddm || true
    fi
    mkdir -p rootdir/etc/xdg
    printf "[PowerManagement]\nScreenBlanking=false\nDisplaySleep=0\n" > rootdir/etc/xdg/plasmarc
    chroot rootdir systemctl enable sddm
fi

if [ "$DM" = "lightdm" ]; then
    mkdir -p rootdir/etc/lightdm/lightdm.conf.d
    printf "[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n" "$USER_NAME" > rootdir/etc/lightdm/lightdm.conf.d/autologin.conf
    chroot rootdir systemctl enable lightdm
fi

chroot rootdir systemctl set-default graphical.target

# 文件系统挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 清理缓存
chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 原始镜像生成完成: $ROOTFS_IMG"

# ========================================================
# ⚡ 转换为 Fastboot 稀疏镜像并压缩
# ========================================================
SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

7z a "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z" "$SPARSE_IMG"

rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
echo "🎉 Ubuntu 26.04 (pp预设) 构建成功！"
