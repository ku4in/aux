#!/bin/bash

set -e

if [ -z $ip_prefix          ]; then ip_prefix=10.0.0; fi
if [ -z $ip_mask            ]; then ip_mask=24; fi
if [ -z $start_ip           ]; then start_ip=101; fi
if [ -z $wg_port            ]; then wg_port=51820; fi
if [ -z $server_file        ]; then server_file=wg0.conf; fi
if [ -z $client_file_prefix ]; then client_file_prefix=client; fi
if [ -z $allowedips         ]; then allowedips=0.0.0.0/0; fi
if [ -z "$DNS"              ]; then DNS='DNS = 1.1.1.1,8.8.8.8'; elif [ "$DNS" != " " ]; then DNS="DNS = $DNS"; fi;

postup_rules=postup.rules
postdown_rules=postdown.rules
client_file_suffix=.conf

wg_pub_ip=`curl -s -4 2ip.ru`
number_clients="$1"


if [ ! "$number_clients" ]; then
	echo "Usage: $0 <number of client config files>"
	exit 1
fi


##########################
# Generate server config #
##########################

server_priv_key=`wg genkey`
server_pub_key=`wg pubkey <<< $server_priv_key`

echo "[Interface]" > $server_file
echo "Address = $ip_prefix.1/$ip_mask" >> $server_file
echo "ListenPort = $wg_port" >> $server_file
echo "PrivateKey = $server_priv_key" >> $server_file

if [ -f ./$postup_rules ]; then
	while read line; do
		echo "PostUp = $line" >> $server_file
	done < $postup_rules
fi
if [ -f ./$postdown_rules ]; then
	while read line; do
		echo "PostDown = $line" >> $server_file
	done < $postdown_rules
fi
echo >> $server_file


###########################
# Generate client configs #
###########################

for ((i=1; i<=$number_clients; i++)); do

	client_priv_key=`wg genkey`
	client_pub_key=`wg pubkey <<< $client_priv_key`

	echo "[Interface]" > $client_file_prefix$i$client_file_suffix
	echo "PrivateKey = $client_priv_key" >> $client_file_prefix$i$client_file_suffix
	echo "Address = $ip_prefix.$((start_ip+i-1))/$ip_mask" >> $client_file_prefix$i$client_file_suffix
	echo "$DNS" >> $client_file_prefix$i$client_file_suffix
	echo >> $client_file_prefix$i$client_file_suffix
	echo "[Peer]" >> $client_file_prefix$i$client_file_suffix
	echo "AllowedIPs = $allowedips" >> $client_file_prefix$i$client_file_suffix
	echo "PublicKey = $server_pub_key" >> $client_file_prefix$i$client_file_suffix
	echo "Endpoint = $wg_pub_ip:$wg_port" >> $client_file_prefix$i$client_file_suffix
	echo "PersistentKeepalive = 25" >> $client_file_prefix$i$client_file_suffix
	
	# add client to server config file
	echo >> $server_file
	echo "[Peer]" >> $server_file
	echo "PublicKey = $client_pub_key" >> $server_file
	echo "AllowedIPs = $ip_prefix.$((start_ip+i-1))/32" >> $server_file
done

exit 0
