#!/usr/bin/env bash
set -e
# Config
VPN_URL=https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.34-9745-beta/softether-vpnserver-v4.34-9745-beta-2020.04.05-linux-x64-64bit.tar.gz
INSTALL_PATH=/opt
TAP_IPV4=10.121.20.1/24

wget $VPN_URL -O /tmp/softether-vpnserver.tar.gz
tar -zxvf /tmp/softether-vpnserver.tar.gz -C $INSTALL_PATH
sudo yum install gcc make gcc-c++ git -y
make -C /opt/vpnserver

# Remove firewalld, install iptables
echo "Installing iptables ..."
(sudo systemctl list-units | grep firewalld) && (sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo yum remove -y firewalld
)
sudo yum install -y iptables-services
sudo systemctl enable iptables
sudo systemctl start iptables
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
dhcp-authoritative
" >> /etc/dnsmasq.conf
sudo systemctl enable dnsmasq

# enable ipv4 ipforwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sysctl -p

echo
echo "Starting SoftEther VPN Server ..."
$INSTALL_PATH/vpnserver/vpnserver start
iptables -I INPUT -p tcp --dport=5555 -j ACCEPT
ip6tables -I INPUT -p tcp --dport=5555 -j ACCEPT
echo
echo "Please use SoftEther VPN Server Manager to configure."
read -p "Press any key to continue..."
iptables -D INPUT -p tcp --dport=5555 -j ACCEPT
ip6tables -D INPUT -p tcp --dport=5555 -j ACCEPT
echo -n "Enter the local bridge interface name:"
read if_name
test -n "$if_name"
tap_soft=tap_$if_name
echo "[Unit]
Description=SoftEther VPN Server
After=network.target auditd.service
ConditionPathExists=!$INSTALL_PATH/vpnserver/do_not_run

[Service]
Type=forking
EnvironmentFile=-$INSTALL_PATH/vpnserver
ExecStart=$INSTALL_PATH/vpnserver/vpnserver start
ExecStartPost=/bin/sleep 10
ExecStartPost=-/sbin/ip address add $TAP_IPV4 dev $tap_soft
ExecStartPost=/usr/sbin/iptables -I INPUT -i $tap_soft -p udp --dport=67 -j ACCEPT
ExecStartPost=/usr/sbin/iptables -I FORWARD -i $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/iptables -I FORWARD -o $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=-/usr/bin/systemctl start dnsmasq
ExecStartPost=-/usr/bin/systemctl start ndppd
ExecStop=$INSTALL_PATH/vpnserver/vpnserver stop
ExecStopPost=/usr/sbin/iptables -D INPUT -i $tap_soft -p udp --dport=67 -j ACCEPT
ExecStopPost=/usr/sbin/iptables -D FORWARD -i $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/iptables -D FORWARD -o $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ExecStopPost=-/sbin/ip address del $TAP_IPV4 dev $tap_soft
ExecStopPost=-/sbin/ip address del $TAP_IPV6 dev $tap_soft
Restart=on-failure

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/softether.service
echo "Restarting VPN Server ..."
$INSTALL_PATH/vpnserver/vpnserver stop
systemctl enable softether
systemctl start softether
echo
echo Success!
echo
echo "Edit /etc/sysconfig/iptables to open additional ports, such as:"
echo
echo "-A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"
echo