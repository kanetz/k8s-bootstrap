#!/bin/bash

set -euo pipefail


cd $HOME
scp -r root@deployer:/root/redist .


cat <<-EOF | tee /etc/modules-load.d/k8s.conf
	overlay
	br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<-EOF | tee /etc/sysctl.d/k8s.conf
	net.bridge.bridge-nf-call-iptables  = 1
	net.bridge.bridge-nf-call-ip6tables = 1
	net.ipv4.ip_forward                 = 1
EOF
sysctl --system


apt-get update -y
apt-get install -y \
	apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

mkdir -p /etc/apt/keyrings

curl -fsSL http://mirrors.cloud.aliyuncs.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] http://mirrors.cloud.aliyuncs.com/docker-ce/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

cp -f redist/kubernetes-archive-keyring.gpg /usr/share/keyrings/kubernetes.gpg
# curl -fsSL http://mirrors.cloud.aliyuncs.com/kubernetes/apt/doc/apt-key.gpg -o /etc/apt/keyrings/kubernetes.gpg
# echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
# echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/usr/share/keyrings/kubernetes.gpg] http://mirrors.cloud.aliyuncs.com/kubernetes/apt/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y


apt-get install -y containerd.io
mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
cp -f redist/containerd.config.toml /etc/containerd/config.toml
# mkdir -p /etc/containerd/certs.d/docker.io
# cp -f redist/containerd.registry.dockerio.hosts.toml /etc/containerd/certs.d/docker.io/hosts.toml
systemctl restart containerd

cp -f redist/crictl.yaml /etc/crictl.yaml
tar Cxf /usr/bin redist/nerdctl-0.23.0-linux-amd64.tar.gz

apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

crictl completion bash | tee /etc/bash_completion.d/crictl > /dev/null
nerdctl completion bash | tee /etc/bash_completion.d/nerdctl > /dev/null
kubeadm completion bash | tee /etc/bash_completion.d/kubeadm > /dev/null
kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc


nerdctl -n k8s.io load -i redist/metrics-server-linux-amd64-v0.6.1.tar
