#!/usr/bin/env python3

'''
Simple script to redirect (DNAT) incoming packets to another IP:PORT taken from file.
Script is intended for using proxies tied to a specific address by several users.
White list is used to limit users IP addresses
'''

import os
import sys

BASE_PORT = 50000

# Returns name of the default gateway interface
def get_def_gateway():
    with open("/proc/net/route") as f:
        for line in f:
            fields = line.strip().split()
            if fields[1] == '00000000' and int(fields[3], 16) & 2:
                return fields[0]
    return None

# Returns public IP
def get_my_ip():
    import requests
    headers = {"Accept": "*/*", "User-Agent": "curl/7.47.0"}
    res = requests.get('https://2ip.ru', headers=headers)
    return res.text.strip()


if len(sys.argv) < 2:
    print("ERROR: No file specified!", file=sys.stderr)
    print(f"Usage: {sys.argv[0]} file_with_proxy.txt")
    sys.exit(1)

ifname = get_def_gateway()
proxy_file = sys.argv[1]
nft_file = "/etc/nftables.conf"
my_ip = get_my_ip()

# Create table 'proxy' for IPv4 with 'prerouting' and 'postrouting' chains and masquerade rule
os.system( "nft flush ruleset")
os.system( "nft add table ip proxy")
os.system( "nft add chain ip proxy prerouting {type nat hook prerouting priority dstnat\; policy accept\; }")
os.system( "nft add chain ip proxy postrouting {type nat hook postrouting priority srcnat\; policy accept\; }")
os.system(f"nft add rule ip proxy postrouting oifname {ifname} counter masquerade")

nport = BASE_PORT

# DNAT all packets to ports starting with BASE_PORT to proxies from file
fproxy = open(proxy_file)
for line in fproxy:
    proxy = line.strip()
    if not proxy:
        continue
    if '@' in proxy:
        ip_port, user_pass = proxy.split('@')
        print(f"{my_ip}:{nport}@{user_pass}")
    else:
        ip_port = proxy
        user_pass = ''
        print(f"{my_ip}:{nport}")
    os.system(f"nft add rule ip proxy prerouting iifname {ifname} tcp dport {nport} counter dnat to {ip_port}")
    nport += 1

fproxy.close()

# Add whitelist
if len(sys.argv) > 2:
    white_list_file = sys.argv[2]
    os.system("nft add set ip proxy my_whitelist { type ipv4_addr \; flags interval \; }")
    with open(white_list_file) as f:
        for line in f:
            os.system(f"nft add element ip proxy my_whitelist  {{{ line.strip() }}}")
    os.system(f"nft insert rule ip proxy prerouting iifname {ifname} ip saddr != @my_whitelist tcp dport {{{BASE_PORT}-{nport-1}}} counter drop")

# Save firewall configuration to file and enable it after reboot
os.system("echo flush ruleset > /etc/nftables.conf")
os.system("nft -s list ruleset >> /etc/nftables.conf")
os.system("systemctl enable --now nftables.service")

# Enable forwarding
os.system("echo 1 > /proc/sys/net/ipv4/ip_forward")
os.system("sed -i '/net.ipv4.ip_forward=1/s/#//' /etc/sysctl.conf")
