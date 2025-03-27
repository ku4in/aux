#!/bin/bash

OVPN_PANEL_PORT=8080        # Do not change this port, it is used by OpenVPN UI
OVPN_PANEL_SSL_PORT=44443

banner () {
	if [ -z "$1" ]; then pad=" "; else OVPN_PANEL_SSL_PORT=OVPN_PANEL_PORT; pad=""; fi
	echo "**************************************************************************"
	echo "*                                                                        *"
	echo "*                  INSTALLATION COMPLETED SUCCESSFULLY!                  *"
	echo "*                                                                        *"
	echo "* Your 3x-ui panel parameters:                                           *"
	echo "*                                                                        *"
	while read -r line; do
		printf "* %-70s *\n" "$line"
	done < <(x-ui <<< "10" | tail -5 | sed -r "s/\x1B\[[0-9;]*[mK]//g")
	echo "*                                                                        *"
	echo "*                                                                        *"
	echo "* Your OpenVPN panel parameters:                                         *"
	echo "*                                                                        *"
	printf "* username: %-60s *\n" "$ovpn_user"
	printf "* password: %-60s *\n" "$ovpn_passwd"
	printf "* Access URL: http%s://%-50s %s*\n" "$1" "$host_name:$OVPN_PANEL_SSL_PORT" "$pad"
	echo "*                                                                        *"
	echo "**************************************************************************"
}

apt update
DEBIAN_FRONTEND=noninteractive apt -y upgrade
apt install -y docker.io docker-compose-v2 socat sqlite3



# Install 3x-ui panel
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Launch 3x-UI to make preliminary set up
# You can Install SSL for x-ui panel
x-ui

# Install OpenVPN panel
git clone https://github.com/d3vilh/openvpn-server
cd openvpn-server

# Ask user for OpenVPN web login and password
echo
ovpn_user=admin
ovpn_passwd=`< /dev/urandom tr -dc _A-Za-z0-9- | head -c16`
read -p "OpenVPN panel user [$ovpn_user]: " option
if [[ $option != "" ]]; then ovpn_user=$option; fi
read -p "OpenVPN panel passowrd [$ovpn_passwd]: " option
if [[ $option != "" ]]; then ovpn_passwd=$option; fi
echo -e "$ovpn_user\n$ovpn_passwd" > .ovpn_creds


# set user & passwd in Docker
sed -i "/OPENVPN_ADMIN_USERNAME/s/=.*/=$ovpn_user/" docker-compose.yml
sed -i "/OPENVPN_ADMIN_PASSWORD/s/=.*/=$ovpn_passwd/" docker-compose.yml

# Set firewall inside OVPN container
echo "iptables -t nat -A POSTROUTING -s 172.18.0.0/16 -o tun0 -j MASQUERADE" >> fw-rules.sh

rm -rf server.conf
docker-compose up -d


# Restart containers to apply new config
echo "Restarting containers to apply custom configs. Please wait..."
docker stop openvpn-ui
docker stop openvpn

# Set parameters in DB
host_ip=`curl 2ip.ru`
echo "
UPDATE o_v_config SET redirect_g_w='# redirect-gateway def1 bypass-dhcp';
UPDATE o_v_config SET route='# route 10.0.71.0 255.255.255.0';
UPDATE o_v_config SET push_route='# route 10.0.60.0 255.255.255.0';
UPDATE o_v_client_config SET server_address='$host_ip';
UPDATE o_v_client_config SET redirect_gateway='# redirect-gateway def1'; " | sqlite3 db/data.db

rm -rf server.conf

docker start openvpn-ui
sleep 2
docker start openvpn

cat > /etc/rc.local << EOF
#!/bin/bash

# Wait for Docker to be fully ready
while ! docker inspect -f '{{.State.Running}}' openvpn 2>/dev/null | grep -q true; do
    sleep 1
done

# Get container's IP
ip_addr=\$(docker exec openvpn ip a show dev eth0 | grep inet | grep -E -o -m 1 '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

# Add the route
/usr/sbin/ip route add 10.0.70.0/24 via \$ip_addr
exit 0
EOF
chmod +x /etc/rc.local

# Add the route right now
/etc/rc.local


# SSL for OpenVPN?
read -p "Setup SSL for OpenVPN panel? [y/N]: " option
if [ "$option" == "y" -o "$option" == "Y" ]; then ovpn_ssl=1; else ovpn_ssl=0; fi
if [ "$ovpn_ssl" == "0" ]; then banner; exit 0; fi

host_name=`ls /root/cert/`
if [ -z "$host_name" ]; then echo "ERROR: No SSL cert found!"; banner; exit 1; fi

apt install -y stunnel4

# Set custom SSL port for OpenVPN panel
echo
re_num='^[0-9]+$'
read -p "OpenVPN panel SSL port number [$OVPN_PANEL_SSL_PORT]: " option
if [[ $option =~ $re_num ]]; then OVPN_PANEL_SSL_PORT=$option; fi

cat > /etc/stunnel/stunnel.conf << EOF
[ovpntunnel]
accept = $OVPN_PANEL_SSL_PORT
connect = 127.0.0.1:$OVPN_PANEL_PORT
cert = /root/cert/$host_name/fullchain.pem
key = /root/cert/$host_name/privkey.pem
EOF

systemctl start  stunnel4.service
systemctl enable stunnel4.service

banner s
exit 0
