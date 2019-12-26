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
dhcp-option=option6:dns-server,[2606:4700:4700::1111],[2606:4700:4700::1001]
" >> /etc/dnsmasq.conf
echo "
enable-ra
dhcp-authoritative
" >> /etc/dnsmasq.conf
sudo systemctl enable dnsmasq

# enable ipv4 & ipv6 ipforwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.proxy_ndp = 1' | sudo tee -a /etc/sysctl.conf
sysctl -p
echo "Installing ndppd ..."
git clone https://github.com/DanielAdolfsson/ndppd.git /tmp/ndppd
pushd /tmp/ndppd
make
make install
popd
echo "route-ttl 30000
proxy ens3 {
  router yes
  timeout 500
  ttl 30000
  rule $TAP_IPV6 {
    static
  }
}
" > /etc/ndppd.conf
echo "[Unit]
Description=NDP Proxy Daemon
After=network.target

[Service]
ExecStart=/usr/local/sbin/ndppd -d -p /var/run/ndppd/ndppd.pid
Type=forking

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/ndppd.service
systemctl enable ndppd
systemctl start ndppd

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
ExecStartPost=-/sbin/ip address add $TAP_IPV6 dev $tap_soft
ExecStartPost=/usr/sbin/iptables -I INPUT -i $tap_soft -p udp --dport=67 -j ACCEPT
ExecStartPost=/usr/sbin/ip6tables -I INPUT -i $tap_soft -p udp --dport=547 -j ACCEPT
ExecStartPost=/usr/sbin/iptables -I FORWARD -i $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/iptables -I FORWARD -o $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/ip6tables -I FORWARD -i $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/ip6tables -I FORWARD -o $tap_soft -j ACCEPT
ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
ExecStartPost=-/usr/bin/systemctl start dnsmasq
ExecStartPost=-/usr/bin/systemctl start ndppd
ExecStop=$INSTALL_PATH/vpnserver/vpnserver stop
ExecStopPost=/usr/sbin/iptables -D INPUT -i $tap_soft -p udp --dport=67 -j ACCEPT
ExecStopPost=/usr/sbin/ip6tables -D INPUT -i $tap_soft -p udp --dport=547 -j ACCEPT
ExecStopPost=/usr/sbin/iptables -D FORWARD -i $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/iptables -D FORWARD -o $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/ip6tables -D FORWARD -i $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/ip6tables -D FORWARD -o $tap_soft -j ACCEPT
ExecStopPost=/usr/sbin/iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
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
