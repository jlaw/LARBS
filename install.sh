#!/bin/sh

# curl -sL https://tinyurl.com/archi-rnkvms | sh

archi_dialog() {
    echo $(dialog --no-shadow --backtitle "Arch Linux Installer (RamNode SKVMS)" "$@" 3>&1 1>&2 2>&3)
}

# disk
disk=$(archi_dialog --title "Storage Device" --no-cancel --inputbox "Please enter path to storage device:" 8 60 "/dev/vda")

# root
root=${disk}$(archi_dialog --title "Root Partition" --no-cancel --inputbox "Please enter root partition #:" 8 60 "1")

# IP
ip=$(archi_dialog --title "IP Address" --no-cancel --inputbox "Please enter IPv4 address assigned to this host:" 8 60 "127.0.1.1")
ip_dev=$(ls -1 /sys/class/net | grep -v lo)

# hostname
hostname=$(archi_dialog --title "Hostname" --no-cancel --inputbox "Please enter a name for this host:" 8 60 "rnkvm")

# SSH port
ssh_port=$(archi_dialog --title "SSH Port" --no-cancel --inputbox "Please enter port for SSH:" 8 60 "22")

# root password
pass1=$(archi_dialog --title "Root Password" --insecure --no-cancel --passwordbox "Enter a strong password for the root user:" 8 60)
pass2=$(archi_dialog --title "Root Password" --insecure --no-cancel --passwordbox "Retype password:" 8 60)
while ! [ "$pass1" = "$pass2" ]; do
    unset pass2
    pass1=$(archi_dialog --title "Root Password" --insecure --no-cancel --passwordbox "Passwords do not match.\n\nEnter password again:" 10 60)
    pass2=$(archi_dialog --title "Root Password" --insecure --no-cancel --passwordbox "Retype password:" 8 60)
done

# show inputs and final confirmation
dialog --no-shadow --title "WARNING" --yesno "\
disk=${disk}\n
root=${root}\n
ip=${ip}\n
ip_dev=${ip_dev}\n
hostname=${hostname}\n
ssh_port=${ssh_port}\n
root_password=${pass1}\n
\nAll data will be WIPED from ${disk}!\nProceed?" 14 60 || { clear; exit; }

# clear screen
reset

# update the system clock
timedatectl set-ntp true

# setup root partition
mkfs.ext4 ${root}
mount ${root} /mnt

{
# update keyring and pacman
pacman --noconfirm -Sy archlinux-keyring
pacman --noconfirm -S pacman

# find fastest mirror
pacman --noconfirm -S python reflector
reflector --verbose -c US -l 20 --score 10 -p https --sort rate --save /etc/pacman.d/mirrorlist

# install the base system
pacstrap /mnt base linux linux-firmware

# generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# chroot
arch-chroot /mnt sh << EOS
#!/bin/sh

# sync hardware clock and set timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc --utc

# setup system locale
sed -i '/^#en_US\.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# setup network
pacman --noconfirm -S dhcpcd
cat << EOF > /etc/dhcpcd.conf
# define static profile
profile static_${ip_dev}
static ip_address=${ip}/24
static routers=$(echo ${ip} | sed 's/\.[0-9]*$/.1/')

# fallback to static profile on ${ip_dev}
interface ${ip_dev}
static domain_name_servers=1.1.1.1 1.0.0.1
fallback static_${ip_dev}
EOF
systemctl enable dhcpcd.service

# set hostname
echo "${hostname}" > /etc/hostname
cat << EOF >> /etc/hosts
127.0.0.1	localhost
::1		localhost
${ip}	${hostname}
EOF

## setup fail2ban
#pacman --noconfirm -S fail2ban
#systemctl enable fail2ban.service

# setup SSH
pacman --noconfirm -S openssh
cat << EOF >> /etc/ssh/sshd_config
#PasswordAuthentication no
PermitRootLogin no
Port ${ssh_port}
EOF
systemctl enable sshd.service

# support qemu QMP
pacman --noconfirm -S qemu-guest-agent
systemctl enable qemu-ga.service

# update Intel CPU ucode
pacman --noconfirm -S intel-ucode

# set root password
echo "Set root password"
echo "root:${pass1}" | chpasswd

# configure boot manager
echo "Configuring GRUB boot loader"
pacman --noconfirm -S grub
grub-install --target=i386-pc --recheck ${disk}
#sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# setup user
curl -sL https://raw.githubusercontent.com/jlaw/archi/rnkvm/user.sh | sh
EOS
} 2>&1 | tee install.log && cp install.log /mnt/root/ && umount -R /mnt
