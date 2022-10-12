#!/bin/bash

set -euo pipefail


NODE_NAME="$(hostname)"
echo -e "\n\e[0;96mInstalling k8s prerequisites on [${NODE_NAME}]...\e[0m\n"
cd $HOME


echo "Fetching redist materials..."
scp -r root@deployer:/root/redist root@deployer:/root/conf .


cat <<-EOF >/etc/modules-load.d/k8s.conf
	overlay
	br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<-EOF >/etc/sysctl.d/k8s.conf
	net.bridge.bridge-nf-call-iptables  = 1
	net.bridge.bridge-nf-call-ip6tables = 1
	net.ipv4.ip_forward                 = 1
	net.ipv4.conf.all.forwarding		= 1
	net.ipv6.conf.all.forwarding		= 1
	net.netfilter.nf_conntrack_max      = 1000000
EOF
sysctl --system

# mkdir -p /etc/NetworkManager/conf.d
# cat <<-EOF >/etc/NetworkManager/conf.d/calico.conf
# 	[keyfile]
# 	unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
# EOF


apt-get update -y
apt-get install -y \
	apt-transport-https \
    ca-certificates \
    curl \
    jq \
    gnupg \
    lsb-release

mkdir -p /etc/apt/keyrings

curl -fsSL http://mirrors.cloud.aliyuncs.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] http://mirrors.cloud.aliyuncs.com/docker-ce/linux/ubuntu \
  $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list

cp -f redist/kubernetes-archive-keyring.gpg /usr/share/keyrings/kubernetes.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes.gpg] http://mirrors.cloud.aliyuncs.com/kubernetes/apt/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list

apt-get update -y


apt-get install -y containerd.io
mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
cp -f conf/containerd.config.toml /etc/containerd/config.toml
mkdir -p /etc/containerd/certs.d/docker.io
cp -f conf/containerd.registry.docker.io.hosts.toml /etc/containerd/certs.d/docker.io/hosts.toml
systemctl restart containerd

cp -f conf/crictl.yaml /etc/crictl.yaml

tar Cxf /usr/bin redist/nerdctl-0.23.0-linux-amd64.tar.gz
mkdir -p /etc/nerdctl
cp -f conf/nerdctl.toml /etc/nerdctl/nerdctl.toml
nerdctl -n k8s.io load -i redist/metrics-server-linux-amd64-v0.6.1.tar
nerdctl -n k8s.io load -i redist/ingress-nginx-controller-linux-amd64-v1.4.0.tar
nerdctl -n k8s.io load -i redist/kube-webhook-certgen-linux-amd64-v20220916-gd32f8c343.tar
nerdctl -n k8s.io load -i redist/tektoncd-pipeline-cmd-controller-linux-amd64-v0.40.2.tar
nerdctl -n k8s.io load -i redist/tektoncd-pipeline-cmd-webhook-linux-amd64-v0.40.2.tar


apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl


crictl completion bash >/etc/bash_completion.d/crictl
nerdctl completion bash >/etc/bash_completion.d/nerdctl
kubeadm completion bash >/etc/bash_completion.d/kubeadm
kubectl completion bash >/etc/bash_completion.d/kubectl

echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc


echo -e "\n\e[0;32mK8s prerequisites are all set on [${NODE_NAME}].\e[0m\n"
