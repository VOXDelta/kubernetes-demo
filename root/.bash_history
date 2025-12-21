ls
apt update
ping google.com
ping 8.8.8.8
 ip -a
ip a
apt update
shutdown 
shutdown -c
shutdown -t 0
shutdown -h
shutdown --help
shutdown -P
shutdown -Pk
shutdown -kH
stop
apt update
apt-cdrom
apt-secure
apt-secure(8)
apt update
apt-get update
mv /etc/apt/sources.list /etc/apt/sources.list.backup
sudo ufw allow ssh
ufw allow ssh
ufw
apt install ufw
iptables
systemctl start ssh
dpkg -l | grep openssh-server
li openssh-server
nano /etc/apt/sources.list
apt update
apt install openssh-server
nft list ruleset
ssh
nano /etc/ssh/ssh_config
systemctl restart ssh
systemctl start ssh
ssh
nano /etc/apt/sources.list
reboot
apt update
ping 8.8.8.8
ip a
systemctl status resolvconf
systemctl status resolvconf
nano /etc/network/interfaces
reboot
ping google.com
ping 9.9.9.9
nano /etc/resolv.conf 
ping google.com
apt update
apt upgrade
apt install openssh-server
nano /etc/ssh/sshd_config
systemctl restart ssh
swapoff -a
sed -i '/swap/d' /etc/fstab
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

Setting up python3-referencing (0.36.2-1) ...
sysctl --system
cat > /etc/modules-load.d/k3s.conf << 'EOF'
br_netfilter
overlay
EOF

modprobe br_netfilter
modprobe overlay
# Machine-ID löschen (wird beim Clone neu generiert)
rm -f /etc/machine-id
touch /etc/machine-id
# SSH Host Keys löschen (werden beim Clone neu generiert)
rm -f /etc/ssh/ssh_host_*
# Netzwerk-Config cleanen
rm -f /etc/udev/rules.d/70-persistent-net.rules
# Cloud-init cleanen
cloud-init clean --logs
# Herunterfahren
poweroff
hostenamectl set-hostname k3s-node-1
hostnamectl set-hostname k3s-node-1
nano /etc/network/interfaces
systemctl restart network
dpkg-reconfigure openssh-server
systemd-machine-id-setup 
reboot
shutdown -h now
