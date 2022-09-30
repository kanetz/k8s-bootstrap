#!/bin/bash

swapoff -a

cat <<-EOF >/root/.ssh/config
	Host *
	    TCPKeepAlive yes
		ServerAliveInterval 10
		ServerAliveCountMax 3
		StrictHostKeyChecking no
		UserKnownHostsFile /dev/null
EOF

resolvectl domain eth0 vpc
systemctl restart systemd-resolved
