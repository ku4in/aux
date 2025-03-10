#!/bin/bash

apt update
DEBIAN_FRONTEND=noninteractive apt -y upgrade

# Install Wireguard panel
bash <(curl -sSL https://get.docker.com)
usermod -aG docker $(whoami)
newgrp docker
host_ip=`curl 2ip.ru`
docker run -d --name=wg-easy -e LANG=en -e WG_HOST=$host_ip \
       -e PASSWORD_HASH='$2a$12$508zOqXGhX8RNw62yP9MoeAguIc.s5XGHT2GKoz7yIfqXrXYDPLue' \
       -e PORT=51821 -e WG_PORT=51820 -e WG_DEFAULT_ADDRESS=10.10.10.x -e WG_ALLOWED_IPS=10.10.10.0/24 \
       -e WG_POST_UP='iptables -t nat -A POSTROUTING -s 172.17.0.0/16 -o wg0 -j MASQUERADE' \
       -e WG_PRE_DOWN='iptables -t nat -D POSTROUTING -s 172.17.0.0/16 -o wg0 -j MASQUERADE' \
       -e WG_PERSISTENT_KEEPALIVE=25 -e UI_TRAFFIC_STATS=true -e UI_CHART_TYPE=3 \
       -v ~/.wg-easy:/etc/wireguard -p 51820:51820/udp -p 51821:51821/tcp --cap-add=NET_ADMIN --cap-add=SYS_MODULE \
       --sysctl="net.ipv4.conf.all.src_valid_mark=1" --sysctl="net.ipv4.ip_forward=1" --restart unless-stopped \
       ghcr.io/wg-easy/wg-easy


# Install 3x-ui pannel
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
ip r add 10.10.10.0/24 via 172.17.0.2 dev docker0
cat > /etc/rc.local << EOF
#!/bin/bash

sleep 10
ip r add 10.10.10.0/24 via 172.17.0.2 dev docker0
exit 0
EOF

# Launch 3x-UI to make preliminary set up
# You can Install SSL in x-ui pannel
x-ui

read -p "Setup SSL for WG panel? [y/N]: " option
if [ "$option" == "y" -o "$option" == "Y" ]; then wg_ssl=1; else wg_ssl=0; fi

if [ "$wg_ssl" == "0" ]; then exit 0; fi

host_name=`ls /root/cert/`

apt install -y stunnel4

cat > /etc/stunnel/stunnel.conf << EOF
[wgtunnel]
accept = 51822
connect = 127.0.0.1:51821
cert = /root/cert/$host_name/fullchain.pem
key = /root/cert/$host_name/privkey.pem
EOF

systemctl start  stunnel4.service
systemctl enable stunnel4.service


# Connections settings

# Go to Wireguard pannel:
# host_ip:51821
# add client. Keep address wg_ip.
# Go to 3x-ui --> Xray Settings --> Outbounds --> Add outbound (http, tag, wg_ip, port=12345, admin, admin) --> Save!!!
# Go to Connections --> Add new --> http.
# Go to Xray Settings --> Routing rules --> Add rule --> Inbound Tags (http proxy tag), Outbound Tag (http outboud tag) --> Save!!
# Enjoy!


