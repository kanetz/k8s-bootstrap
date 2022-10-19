#!/bin/bash

set -euo pipefail


echo -e "\n\e[0;96mConfiguring [deployer]...\e[0m\n"
cd $HOME


echo "Fetching and unpacking redist materials..."
curl -fsSL http://k8s-bootstrap.oss-cn-shenzhen-internal.aliyuncs.com/redist.tgz -o redist.tgz
tar xzvf redist.tgz


echo "Configuring kubectl..."
cp -f redist/kubernetes-archive-keyring.gpg /usr/share/keyrings/kubernetes.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes.gpg] http://mirrors.cloud.aliyuncs.com/kubernetes/apt/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y kubectl jq unzip
kubectl completion bash >/etc/bash_completion.d/kubectl
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc


echo "Configuring helm3..."
tar Cxzf /usr/local/bin redist/helm-v3.10.0-linux-amd64.tar.gz linux-amd64/helm --strip-components=1
helm completion bash >/etc/bash_completion.d/helm


echo "Configuring haproxy..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy
cp -f /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
cat <<EOF >/etc/haproxy/haproxy.cfg
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
	stats timeout 30s
	user haproxy
	group haproxy
	daemon

	# Default SSL material locations
	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private

	# See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
	ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
	ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
	ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
	log	global
	mode	tcp
	option	tcplog
	option	dontlognull
	timeout connect 5000
	timeout client  50000
	timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http

frontend k8s_api_server_tcp_6443
	mode tcp
	bind :6443
	default_backend k8s_api_server
backend k8s_api_server
	server master0 master0:6443

frontend k8s_ingress_controller_tcp_80
	mode tcp
	bind :80
	default_backend workers_node_port_30080
backend workers_node_port_30080
	server worker0 worker0:30080
EOF
systemctl restart haproxy


echo -e "\n\e[0;32m[deployer] is all set.\e[0m\n"
