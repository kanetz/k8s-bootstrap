#!/bin/bash

set -euo pipefail


NODE_NAME="$(hostname)"
echo -e "\n\e[0;96mBootstrapping k8s control plane on [${NODE_NAME}]...\e[0m\n"
cd $HOME

kubeadm init --config conf/kubeadm.config.yaml
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

kubectl create -f conf/calico-3.24.1-tigera-operator.yaml
echo 'Waiting for Calico crds to be ready...'
until kubectl get crd installations.operator.tigera.io -o jsonpath='{.metadata.name}' &>/dev/null; do sleep 1; done
kubectl wait crd installations.operator.tigera.io --for 'condition=Established' --timeout=10m
until kubectl get crd apiservers.operator.tigera.io -o jsonpath='{.metadata.name}' &>/dev/null; do sleep 1; done
kubectl wait crd apiservers.operator.tigera.io --for 'condition=Established' --timeout=10m

kubectl create -f conf/calico-custom-resources.yaml
echo 'Waiting for Calico components to be ready...'
until kubectl -n calico-system get po --field-selector spec.nodeName=${NODE_NAME} -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n calico-system wait po --field-selector spec.nodeName=${NODE_NAME} --for 'condition=Ready' --timeout=10m

tar Cxf /usr/bin redist/calicoctl-linux-amd64-v3.24.1.tgz

echo 'Waiting for kube-dns apps to be ready...'
until kubectl -n kube-system get po -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l k8s-app=kube-dns --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;32mK8s control plane is all set on [${NODE_NAME}].\e[0m\n"
