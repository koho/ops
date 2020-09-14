#!/usr/bin/env bash

# Config
V2_CONFIG=/etc/v2ray/config.json
FULLCHAIN_FILE=/etc/fullchain.pem
KEY_FILE=/etc/privkey.pem
V2_PORT=18000

set -e
echo Installing V2Ray ...
curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash
echo Updating V2Ray config file ...
yum install python2 -y
python2 -c "import json;f=open('$V2_CONFIG');conf=json.load(f);f.close();conf['inbounds'][0]['port']=$V2_PORT;conf['inbounds'][0]['streamSettings']={'network': 'ws', 'wsSettings': {'path': '/ws'}};f=open('$V2_CONFIG','w');json.dump(conf,f,indent=2);f.close()"
client_info=$(python2 -c "import json;f=open('$V2_CONFIG');conf=json.load(f);f.close();c=conf['inbounds'][0]['settings']['clients'][0];print('id: %s\nalterId: %d' % (c['id'],c['alterId']))")
systemctl enable v2ray
echo Installing nginx ...
sudo yum install yum-utils -y
echo "[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true" > /etc/yum.repos.d/nginx.repo
sudo yum-config-manager --enable nginx-mainline
sudo yum install nginx -y
systemctl enable nginx
# Doh
echo Installing DOH ...
sudo yum install git golang -y
git clone https://github.com/m13253/dns-over-https
pushd dns-over-https
sudo make install
popd
sudo systemctl start doh-server.service
sudo systemctl enable doh-server.service
echo -n "[*] Input your domain name:"
read domain
test -n "$domain"
echo -n "[*] Input your Ali_Key:"
read key
echo -n "[*] Input your Ali_Secret:"
read secret
if [ "$key" ]; then export Ali_Key="$key"; fi
if [ "$secret" ]; then export Ali_Secret="$secret"; fi
echo Getting certificate ...
curl https://get.acme.sh | sh
/root/.acme.sh/acme.sh --issue --dns dns_ali -d $domain
echo "upstream dns-backend {
    server 127.0.0.1:8053;
    keepalive 30;
}

server{
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ssl_certificate $FULLCHAIN_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.3 TLSv1.2;

    server_name $domain;
    root /usr/share/nginx/html;
    index  index.html index.htm;

    location /ws {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:$V2_PORT;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \"upgrade\";
      proxy_set_header Host \$http_host;
    }
    
    location /dns-query {
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Host $http_host;
      proxy_set_header X-NginX-Proxy true;
      proxy_set_header Connection "";
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_redirect off;
      proxy_set_header        X-Forwarded-Proto $scheme;
      proxy_read_timeout 86400;
      proxy_pass http://dns-backend/dns-query;
    }
}" > /etc/nginx/conf.d/v2ray.conf
/root/.acme.sh/acme.sh --install-cert -d $domain --key-file $KEY_FILE --fullchain-file $FULLCHAIN_FILE --reloadcmd "systemctl restart nginx"
echo Enable http \& https service in firewall ...
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload
echo Setting selinux ...
setsebool httpd_can_network_connect on -P
echo Enable BBR ...
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo Starting V2Ray ...
systemctl restart v2ray
systemctl restart nginx
echo
echo Success!
echo
echo "----------------"
echo "address: $domain"
echo "port: 443"
echo "$client_info"
echo "network: ws"
echo "security: tls"
echo "path: /ws"
echo "----------------"
echo
echo NOTE:
echo 1. You can also configure nginx to redirect from 80 to 443. See /etc/nginx/conf.d/default.conf.
echo Add the following line to the port 80 server:
echo
echo "return 301 https://\$host\$request_uri;"
echo
echo 2. Use CDN service to hide your IP address, such as Cloudflare CDN.
echo
echo 3. You can edit /etc/dns-over-https/doh-server.conf to change the upstream dns resolver.
echo
echo "Please reboot to make all things fully functional!"
