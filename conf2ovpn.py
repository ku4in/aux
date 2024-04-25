#!/usr/bin/env python3
'''
Simple script for combining OpenVPN config files into one .ovpn file
'''

import os
import glob

items = ['ca', 'cert', 'key', 'tls-auth']
idict = dict.fromkeys(items)

for file in glob.glob('./*.conf'):
    with open(file, 'r') as f:
        new_name = os.path.splitext(f.name)[0] + '.ovpn'
        new_file = open(new_name, 'w')
        for line in f.readlines():
            for i in idict.keys():
                if line.startswith(i + ' '):
                    fname = line.split(i + ' ', 1)[-1].strip().split(' ')[0]
                    idict[i] = fname
                    break
            else:
                new_file.write(line)
    for tag, f in idict.items():
        new_file.write('\n<' + tag + '>\n')
        with open(f) as ff:
            wflag = False
            for line in ff.readlines():
                if line.startswith('-----BEGIN'):
                    wflag = True
                if wflag:
                    new_file.write(line)
                if line.startswith('-----END'):
                    wflag = False
        new_file.write('</' + tag + '>\n')
    new_file.close()
