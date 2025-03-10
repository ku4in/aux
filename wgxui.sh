#!/bin/bash

WG_PORT=51820
WG_PANEL_PORT=51821
WG_PANEL_SSL_PORT=51822

re_num='^[0-9]+$'

apt update
DEBIAN_FRONTEND=noninteractive apt -y upgrade
apt install -y apache2-utils

# Install 3x-ui panel
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Launch 3x-UI to make preliminary set up
# You can Install SSL for x-ui panel
x-ui


# Install Wireguard panel
bash <(curl -sSL https://get.docker.com)
exit # not from this script but from docker script
usermod -aG docker $(whoami)
newgrp docker
host_ip=`curl 2ip.ru`

echo
read -p "WG panel port number [$WG_PANEL_PORT]: " option
if [[ $option =~ $re_num ]]; then WG_PANEL_PORT=$option; fi

echo
wg_passwd=`< /dev/urandom tr -dc _A-Za-z0-9- | head -c16`
read -p "WG panel passowrd [$wg_passwd]: " option
if [[ $option != "" ]]; then wg_passwd=$option; fi
echo $wg_passwd > .wg_passwd

wg_passwd_hash=`htpasswd -bnBC 12 "" $wg_passwd | tr -d ':\n' | sed 's/$2y/$2a/'`

docker run -d --name=wg-easy -e LANG=en -e WG_HOST=$host_ip \
       -e PASSWORD_HASH=$wg_passwd_hash \
       -e PORT=51821 -e WG_PORT=$WG_PORT -e WG_DEFAULT_ADDRESS=10.10.10.x -e WG_ALLOWED_IPS=10.10.10.0/24 \
       -e WG_POST_UP='iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -o wg0 -j MASQUERADE' \
       -e WG_PRE_DOWN='iptables -t nat -D POSTROUTING -s 172.17.0.0/16 -o wg0 -j MASQUERADE' \
       -e WG_PERSISTENT_KEEPALIVE=25 -e UI_TRAFFIC_STATS=true -e UI_CHART_TYPE=2 \
       -v ~/.wg-easy:/etc/wireguard -p $WG_PORT:$WG_PORT/udp -p 51821:51821/tcp --cap-add=NET_ADMIN --cap-add=SYS_MODULE \
       --sysctl="net.ipv4.conf.all.src_valid_mark=1" --sysctl="net.ipv4.ip_forward=1" --restart unless-stopped \
       ghcr.io/wg-easy/wg-easy


ip r add 10.10.10.0/24 via 172.17.0.2 dev docker0
cat > /etc/rc.local << EOF
#!/bin/bash

sleep 10
ip r add 10.10.10.0/24 via 172.17.0.2 dev docker0
exit 0
EOF

echo
read -p "Setup SSL for WG panel? [y/N]: " option
if [ "$option" == "y" -o "$option" == "Y" ]; then wg_ssl=1; else wg_ssl=0; fi
if [ "$wg_ssl" == "0" ]; then exit 0; fi

echo
read -p "WG panel SSL port number [$WG_PANEL_SSL_PORT]: " option
if [[ $option =~ $re_num ]]; then WG_PANEL_SSL_PORT=$option; fi

host_name=`ls /root/cert/`

apt install -y stunnel4

cat > /etc/stunnel/stunnel.conf << EOF
[wgtunnel]
accept = $WG_PANEL_SSL_PORT
connect = 127.0.0.1:$WG_PANEL_PORT
cert = /root/cert/$host_name/fullchain.pem
key = /root/cert/$host_name/privkey.pem
EOF

systemctl start  stunnel4.service
systemctl enable stunnel4.service


# Connections settings

# Go to Wireguard panel:
# host_ip:51821
# add client. Keep address wg_ip.
# Go to 3x-ui --> Xray Settings --> Outbounds --> Add outbound (http, tag, wg_ip, port=12345, admin, admin) --> Save!!!
# Go to Connections --> Add new --> http.
# Go to Xray Settings --> Routing rules --> Add rule --> Inbound Tags (http proxy tag), Outbound Tag (http outboud tag) --> Save!!
# Enjoy!

