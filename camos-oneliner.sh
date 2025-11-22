#!/bin/bash
# CamOS GlassTech - One-Line Linux Distro Builder
# Usage: curl -fsSL https://your-url.com/build-camos.sh | sudo bash

set -e

echo "🔥 CamOS GlassTech Linux Builder 🔥"
echo "===================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

# Install dependencies
echo "📦 Installing build dependencies..."
apt update -qq
apt install -y -qq debootstrap squashfs-tools xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools git build-essential cmake pkg-config libx11-dev libxext-dev libxrender-dev libgl1-mesa-dev libwayland-dev python3-pil >/dev/null 2>&1

# Create build directory
BUILD_DIR="/tmp/camos-build-$$"
mkdir -p "$BUILD_DIR"/{chroot,image,iso}
cd "$BUILD_DIR"

echo "🐧 Bootstrapping Debian base system..."
debootstrap --arch=amd64 --variant=minbase bookworm chroot http://deb.debian.org/debian/ >/dev/null 2>&1

# Mount filesystems
echo "💾 Mounting filesystems..."
mount --bind /dev chroot/dev
mount --bind /dev/pts chroot/dev/pts
mount --bind /proc chroot/proc
mount --bind /sys chroot/sys

# Configure inside chroot
echo "⚙️ Configuring system..."
cat > chroot/root/setup.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

echo "camos-glasstech" > /etc/hostname

cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

apt update -qq
DEBIAN_FRONTEND=noninteractive apt install -y -qq linux-image-amd64 systemd network-manager grub-pc xorg openbox lightdm firefox-esr thunar xfce4-terminal sudo wget curl git >/dev/null 2>&1

# Create user
useradd -m -s /bin/bash cam
echo "cam:camos" | chpasswd
usermod -aG sudo cam
echo "cam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install picom for glass effects
cd /tmp
git clone --depth=1 https://github.com/yshui/picom.git >/dev/null 2>&1 || true
if [ -d picom ]; then
    cd picom
    apt install -y -qq meson ninja-build libxcb1-dev libconfig-dev libdbus-1-dev libev-dev libgl1-mesa-dev libpcre3-dev libpixman-1-dev libx11-xcb-dev >/dev/null 2>&1
    meson setup --buildtype=release build >/dev/null 2>&1
    ninja -C build >/dev/null 2>&1
    ninja -C build install >/dev/null 2>&1
fi

# Glass compositor config
mkdir -p /etc/xdg/picom
cat > /etc/xdg/picom/picom.conf << 'EOF'
backend = "glx";
blur-method = "dual_kawase";
blur-strength = 8;
blur-background = true;
corner-radius = 20;
shadow = true;
shadow-radius = 20;
fading = true;
inactive-opacity = 0.85;
active-opacity = 0.95;
vsync = true;
EOF

# Openbox config
mkdir -p /etc/xdg/openbox
cat > /etc/xdg/openbox/autostart << 'EOF'
nitrogen --restore &
picom --config /etc/xdg/picom/picom.conf &
tint2 &
nm-applet &
EOF

# CamOS session
cat > /usr/share/xsessions/camos.desktop << 'EOF'
[Desktop Entry]
Name=CamOS GlassTech
Exec=openbox-session
Type=Application
EOF

# Wallpaper
mkdir -p /usr/share/backgrounds
python3 << 'PYEOF'
try:
    from PIL import Image, ImageDraw
    img = Image.new('RGB', (1920, 1080), color='#0A0F1E')
    draw = ImageDraw.Draw(img)
    for y in range(1080):
        shade = int(10 + (y / 1080) * 30)
        color = (10, 15 + shade, 30 + shade * 2)
        draw.line([(0, y), (1920, y)], fill=color)
    img.save('/usr/share/backgrounds/camos.jpg', quality=95)
except: pass
PYEOF

# Enable services
systemctl enable NetworkManager
systemctl enable lightdm

# Set passwords
echo "root:camos" | chpasswd

# Clean up
apt clean
apt autoremove -y -qq
CHROOT_EOF

chmod +x chroot/root/setup.sh
chroot chroot /root/setup.sh

# Unmount
echo "📤 Unmounting filesystems..."
umount chroot/dev/pts || true
umount chroot/dev || true
umount chroot/proc || true
umount chroot/sys || true

# Create ISO structure
echo "💿 Building ISO..."
mkdir -p image/{casper,isolinux,install}

cp chroot/boot/vmlinuz-* image/casper/vmlinuz 2>/dev/null || true
cp chroot/boot/initrd.img-* image/casper/initrd 2>/dev/null || true

chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' > image/casper/filesystem.manifest

echo "🗜️ Compressing filesystem (this takes a while)..."
mksquashfs chroot image/casper/filesystem.squashfs -e boot -comp xz >/dev/null 2>&1

du -sx --block-size=1 chroot | cut -f1 > image/casper/filesystem.size

cat > image/isolinux/grub.cfg << 'EOF'
set timeout=10
menuentry "CamOS GlassTech Linux (Live)" {
    linux /casper/vmlinuz boot=casper quiet splash
    initrd /casper/initrd
}
EOF

cd image
grub-mkrescue --output=../camos-glasstech.iso --volid="CamOS" . >/dev/null 2>&1

# Move ISO to home
ISO_PATH="$HOME/camos-glasstech.iso"
[ -f ../camos-glasstech.iso ] && mv ../camos-glasstech.iso "$ISO_PATH"

# Cleanup
cd /
rm -rf "$BUILD_DIR"

echo ""
echo "✅ CamOS GlassTech ISO created successfully!"
echo "📍 Location: $ISO_PATH"
echo ""
echo "🔥 To test in QEMU:"
echo "   qemu-system-x86_64 -cdrom $ISO_PATH -m 4G -enable-kvm"
echo ""
echo "💿 To create bootable USB:"
echo "   sudo dd if=$ISO_PATH of=/dev/sdX bs=4M status=progress"
echo ""
echo "🎨 Login: cam / camos"
echo "💎 Glass effects • Neon blue • Medium blur"
