#!/bin/bash

# This script sets two pairs (TCP + UDP) OpenVPN servers and two tun2socks instances.
# Traffic from one OpenVPN server is routed through one proxy via tun2socks and traffic
# from second OpenVPN server is routed through second proxy in the same manner.

apt update && apt upgrade
apt install -y curl openvpn easy-rsa net-tools zip python3
# reboot

########################
# OpenVPN server setup #
########################

mkdir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
cp -R /usr/share/easy-rsa /etc/openvpn/
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
openvpn --genkey --secret /etc/openvpn/easy-rsa/pki/ta1.key
openvpn --genkey --secret /etc/openvpn/easy-rsa/pki/ta2.key
./easyrsa gen-crl
./easyrsa build-server-full server1 nopass 
./easyrsa build-server-full server2 nopass 
cp ./pki/ca.crt /etc/openvpn/ca.crt
cp ./pki/dh.pem /etc/openvpn/dh.pem
cp ./pki/crl.pem /etc/openvpn/crl.pem
cp ./pki/ta1.key /etc/openvpn/ta1.key
cp ./pki/ta2.key /etc/openvpn/ta2.key
cp ./pki/issued/server1.crt /etc/openvpn/server1.crt
cp ./pki/issued/server2.crt /etc/openvpn/server2.crt
cp ./pki/private/server1.key /etc/openvpn/server1.key
cp ./pki/private/server2.key /etc/openvpn/server2.key

cd /etc/openvpn

# make udp config
cat > server1.conf << EOF
port 1194
proto udp
dev ovpn1
dev-type tun
ca ca.crt
cert server1.crt
key server1.key
dh dh.pem
server 10.10.1.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp1.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth ta1.key 0
cipher AES-256-CBC
persist-key
persist-tun
status /var/log/openvpn/openvpn-status1.log
verb 3
explicit-exit-notify 1
EOF

# make tcp config
cat server1.conf | sed 's/10[.]1[.]/10.10./g' | sed 's/udp/tcp/' | sed 's/ovpn1/ovpn10/' | sed 's/ipp1/ipp10/' | sed 's/status1/status10/' | sed '/explicit/d' > server10.conf

# tcp and udp configs for second server
# 'server2.conf' is the same as 'server1.conf' but with minor changes
cat server1.conf | sed 's/\([a-eg-z]\)1/\12/g' | sed 's/10[.]1[.]/10.2./g' | sed 's/1194/1195/' > server2.conf
cat server2.conf | sed 's/10[.]2[.]/10.20./g' | sed 's/udp/tcp/' | sed 's/ovpn2/ovpn20/' | sed 's/ipp2/ipp20/' | sed 's/status2/status20/' | sed '/explicit/d' > server20.conf

systemctl enable --now openvpn@server1
systemctl enable --now openvpn@server10
systemctl enable --now openvpn@server2
systemctl enable --now openvpn@server20

# allow forwarding
echo 1 | tee /proc/sys/net/ipv4/ip_forward
# uncomment line 'net.ipv4.ip_forward=1' in /etc/sysctl.conf
sed -i '/net.ipv4.ip_forward=1/s/#//' /etc/sysctl.conf

###############################
# Issuing client certificates #
###############################

cd /etc/openvpn/easy-rsa
./easyrsa build-client-full client1 nopass
./easyrsa build-client-full client2 nopass

cd
mkdir clients

cp /etc/openvpn/easy-rsa/pki/ca.crt /root/clients
cp /etc/openvpn/easy-rsa/pki/ta1.key /root/clients
cp /etc/openvpn/easy-rsa/pki/ta2.key /root/clients
cp /etc/openvpn/easy-rsa/pki/issued/client1.crt /root/clients
cp /etc/openvpn/easy-rsa/pki/issued/client2.crt /root/clients
cp /etc/openvpn/easy-rsa/pki/private/client1.key /root/clients
cp /etc/openvpn/easy-rsa/pki/private/client2.key /root/clients

cd clients

# client1 udp
export myip=`curl 2ip.ru 2>/dev/null`
cat > client1.conf << EOF
client
dev tun
proto udp
remote $myip 1194
resolv-retry infinite
keepalive 10 120
nobind
persist-key
persist-tun
ca ca.crt
cert client1.crt
key client1.key
remote-cert-tls server
key-direction 1
tls-auth ta1.key 1
cipher AES-256-CBC
verb 3
EOF


# client1 tcp
cat client1.conf | sed 's/udp/tcp/' > client10.conf

# client2 udp
cat client1.conf | sed 's/\([a-z]\)1/\12/' | sed 's/1194/1195/' > client2.conf

# client2 tcp
cat client2.conf | sed 's/udp/tcp/' > client20.conf

# concatenate client config files into .ovpn
wget https://raw.githubusercontent.com/ku4in/auxiliary/main/conf2ovpn.py
chmod +x conf2ovpn.py
./conf2ovpn.py

# Now can you zip and copy certificates to user devices
zip clients.zip *.ovpn


###################
# tun2socks setup #
###################

cd
wget https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-amd64.zip
unzip tun2socks-linux-amd64.zip 
rm tun2socks-linux-amd64.zip 
cp tun2socks-linux-amd64 /usr/local/bin/tun2socks

systemctl enable --now systemd-networkd 

cat > /etc/systemd/system/tun2socks1.service << EOF
[Unit]
Description=Tun2Socks gateway
After=network.target
Wants=network.target

[Service]
User=root
Type=simple
RemainAfterExit=true
ExecStart=/usr/local/bin/tun2socks -device tun://t2s1 -proxy socks5://12.32.97.67:1184
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/tun2socks2.service << EOF
[Unit]
Description=Tun2Socks gateway 2
After=network.target
Wants=network.target

[Service]
User=root
Type=simple
RemainAfterExit=true
ExecStart=/usr/local/bin/tun2socks -device tun://t2s2 -proxy socks5://26.17.56.15:4773
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/network/10-t2s1.network << EOF
[Match]
Name=t2s1

[Network]
Address=10.20.1.1/24

[RoutingPolicyRule]
IncomingInterface=ovpn1
Table=100

[RoutingPolicyRule]
IncomingInterface=ovpn10
Table=100

[Route]
Gateway=0.0.0.0
Table=100
EOF

cat /etc/systemd/network/10-t2s1.network | sed 's/t2s1/t2s2/' | sed 's/20[.]1[.]/20.2./' | sed 's/100/200/' | sed 's/ovpn1/ovpn2/' > /etc/systemd/network/20-t2s2.network

systemctl daemon-reload
networkctl reload

systemctl enable --now tun2socks1.service 
systemctl enable --now tun2socks2.service 

# Make sure that the proxies are working properly
curl --interface t2s1 2ip.ru
curl --interface t2s2 2ip.ru

reboot
# reboot and check that everything is working properly
