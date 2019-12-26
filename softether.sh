#!/usr/bin/env bash
set -e
prefix=$(ip -6 route show dev ens3 | awk '{print $1}.0' | head -n 1 | sed 's#\/.*$##g')
# Config
VPN_URL=https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.31-9727-beta/softether-vpnserver-v4.31-9727-beta-2019.11.18-linux-x64-64bit.tar.gz
INSTALL_PATH=/opt
TAP_IPV4=10.121.20.1/24
TAP_IPV6="$prefix""1/80"

wget $VPN_URL -O /tmp/softether-vpnserver.tar.gz
tar -zxvf /tmp/softether-vpnserver.tar.gz -C $INSTALL_PATH
sudo yum install gcc make -y
make -C /opt/vpnserver

# Remove firewalld, install iptables
echo "Installing iptables ..."
(sudo systemctl list-units | grep firewalld) && (sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo yum remove -y firewalld
)
sudo yum install -y iptables-services
sudo systemctl enable iptables
sudo systemctl enable ip6tables
sudo systemctl start iptables
sudo systemctl start ip6tables
# install dnsmasq
echo "Installing dnsmasq ..."
sudo yum install dnsmasq -y
# configure dhcp and dns

echo "" > /etc/dnsmasq.conf
echo "
interface=tap_soft
dhcp-range=tap_soft,10.121.20.2,10.121.20.200,255.255.255.0,12h
dhcp-option=tap_soft,3,10.121.20.1
dhcp-option=option:dns-server,1.1.1.1,8.8.8.8,10.121.20.1
" >> /etc/dnsmasq.conf
echo "
dhcp-range=$prefix"100", $prefix"1ff", 80, 12h
" >> /etc/dnsmasq.conf
echo "
enable-ra
dhcp-authoritative
" >> /etc/dnsmasq.conf

# enable ipv4 & ipv6 ipforwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sysctl -p

echo "[Unit]
Description=SoftEther VPN Server
After=network.target auditd.service
ConditionPathExists=!$INSTALL_PATH/vpnserver/do_not_run

[Service]
Type=forking
EnvironmentFile=-$INSTALL_PATH/vpnserver
ExecStart=$INSTALL_PATH/vpnserver/vpnserver start
ExecStartPost=/bin/sleep 1
ExecStartPost=-/sbin/ip address add $TAP_IPV4 dev tap_soft
ExecStartPost=-/sbin/ip address add $TAP_IPV6 dev tap_soft
ExecStartPost=iptables -I INPUT -i tap_soft -p udp --dport=67 -j ACCEPT; ip6tables -I INPUT -i tap_soft -p udp --dport=547 -j ACCEPT; iptables -I FORWARD -i tap_soft -j ACCEPT; iptables -I FORWARD -o tap_soft -j ACCEPT; ip6tables -I FORWARD -i tap_soft -j ACCEPT; ip6tables -I FORWARD -o tap_soft -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
ExecStartPost=-/usr/bin/systemctl restart dnsmasq
ExecStop=$INSTALL_PATH/vpnserver/vpnserver stop
ExecStopPost=iptables -D INPUT -i tap_soft -p udp --dport=67 -j ACCEPT; ip6tables -D INPUT -i tap_soft -p udp --dport=547 -j ACCEPT; iptables -D FORWARD -i tap_soft -j ACCEPT; iptables -D FORWARD -o tap_soft -j ACCEPT; ip6tables -D FORWARD -i tap_soft -j ACCEPT; ip6tables -D FORWARD -o tap_soft -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
Restart=on-failure

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/softether.service
echo
echo "Starting SoftEther VPN Server ..."
$INSTALL_PATH/vpnserver/vpnserver start
iptables -I INPUT -p tcp --dport=5555 -j ACCEPT
ip6tables -I INPUT -p tcp --dport=5555 -j ACCEPT
echo
echo "Please use SoftEther VPN Server Manager to configure."
read -p "Press any key to continue..."
echo "Restarting VPN Server ..."
$INSTALL_PATH/vpnserver/vpnserver stop
systemctl enable softether
systemctl start softether
iptables -D INPUT -p tcp --dport=5555 -j ACCEPT
ip6tables -D INPUT -p tcp --dport=5555 -j ACCEPT
echo
echo Success!
