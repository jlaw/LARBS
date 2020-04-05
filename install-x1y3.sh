#!/usr/bin/env bash

# curl -sLo install.sh https://goo.gl/G1bBNT

# https://wiki.archlinux.org/index.php/Fan_speed_control#ThinkPad_laptops
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Yoga_(Gen_3)#Enabling_S3
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Yoga_(Gen_3)#Tablet_Functions
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Power_management/Throttling_issues
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Keyboard_Fn_Shortcuts
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Special_buttons
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Bind_special_keys
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Disabling_red_LED_Thinkpad_logo
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#HDR_Display_Color_Calibration
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Intel_Graphics_UHD_620_issues
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#TrackPoint_and_Touchpad_issues
# https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Diagnostics
####### set some variables
hostname=nautilus

keymap=us                # console keyboard layout
font="latarcyrheb-sun32" # increase font size for retina display

disk=nvme0n1
boot="${disk}p1"
root="${disk}p2"
#######

{
# change keyboard layout and font
loadkeys ${keymap}
setfont ${font}

# update the system clock
timedatectl set-ntp true

### caution
# prepare partition table
#echo "label: gpt" | sfdisk /dev/${disk}
#sfdisk /dev/${disk} << EOF
#,512M,U
#;
#EOF

# format EFI partition
#mkfs.fat -F32 /dev/${boot}
###

# setup root partition and enable encryption
#dd if=/dev/urandom of=/dev/${root} bs=512 count=20480
cryptsetup -v luksFormat --type luks2 /dev/${root}
cryptsetup open /dev/${root} root
mkfs.ext4 /dev/mapper/root

# mount root
mount /dev/mapper/root /mnt

# mount boot
mkdir -p /mnt/boot && mount /dev/${boot} /mnt/boot

# remove old kernel
#rm /mnt/boot/vmlinuz-linux

# select a mirror
pacman -Sy --noconfirm reflector
reflector --verbose -c US -l 20 --score 10 -p https --sort rate --save /etc/pacman.d/mirrorlist

# install the base system
pacstrap /mnt base

# generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

####### chroot
# create chroot.sh script
mkdir -p /mnt/root/
cat > /mnt/root/chroot.sh << EOS
#!/usr/bin/env bash

# sync hardware clock and set timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc --utc

# setup system locale
sed -i '/^#en_US\.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# retain keymap and font after reboot
cat > /etc/vconsole.conf << EOF
KEYMAP=${keymap}
FONT=${font}
EOF

# set hostname
echo "${hostname}" > /etc/hostname
cat >> /etc/hosts << EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	${hostname}.lan	${hostname}
EOF

# enable periodic trimming
systemctl enable fstrim.timer

# update Intel CPU ucode
pacman -S --noconfirm intel-ucode

# load modules on startup to decrypt file system
sed -i '/^HOOKS/s/.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont ykfde encrypt fsck filesystems shutdown)/' /etc/mkinitcpio.conf

# regenerate initramfs
mkinitcpio -p linux

# set root password
echo "Set root password"
passwd

# install boot manager
bootctl --path=/boot install

# create entry for arch
cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options cryptdevice=UUID=$(blkid /dev/${root} -s UUID -o value):root:allow-discards root=/dev/mapper/root rw
EOF

# set arch as default
cat > /boot/loader/loader.conf << EOF
default arch
EOF

# setup user
curl -LO https://raw.githubusercontent.com/jlaw/archi/master/larbs.sh
bash larbs.sh

# setup touchscreen and stylus
pacman -S --noconfirm xf86-input-wacom

# setup touchpad
cat > /etc/X11/xorg.conf.d/30-touchpad.conf << EOF
Section "InputClass"
	Identifier "libinput touchpad"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	Option "ClickMethod" "clickfinger"
	Option "DisableWhileTyping" "false"
	Option "NaturalScrolling" "true"
	Option "ScrollMethod" "twofinger"
	Option "Tapping" "true"
	Option "TappingDrag" "false"
EndSection
EOF
EOS
#######

# run chroot script
arch-chroot /mnt bash /root/chroot.sh
} |& tee -a install.log

cp install.log /mnt/root/

# prepare for reboot
umount -R /mnt
cryptsetup close root
