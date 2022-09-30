#!/bin/bash

set -euo pipefail


cd $HOME

mkdir -p ~/.kube
scp root@master0:/root/.kube/config ~/.kube/config

# kubeadm join master0:6443 --token 02iz37.bw2u86fdtj2tka5c --discovery-token-unsafe-skip-ca-verification
kubeadm join --discovery-file ~/.kube/config

echo 'Waiting for Calico network plugin to be ready...'
until kubectl -n calico-system get po --field-selector spec.nodeName=$(hostname) -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n calico-system wait po --field-selector spec.nodeName=$(hostname) --for='condition=Ready' --timeout=10m

echo 'Node is all set.'
