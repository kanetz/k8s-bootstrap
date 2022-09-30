#!/bin/bash

set -euo pipefail


cd $HOME

kubeadm init --config redist/kubeadm.config.yaml
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

kubectl create -f redist/calico-3.24.1-tigera-operator.yaml
kubectl create -f redist/calico-3.24.1-custom-resources.yaml

echo 'Waiting for Calico network plugin to be ready...'
until kubectl -n calico-system get po --field-selector spec.nodeName=$(hostname) -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n calico-system wait po --field-selector spec.nodeName=$(hostname) --for='condition=Ready' --timeout=10m

echo 'Waiting for kube-dns apps to be ready...'
until kubectl -n kube-system get po -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l k8s-app=kube-dns --for='condition=Ready' --timeout=10m



echo 'Control plane is all set.'
