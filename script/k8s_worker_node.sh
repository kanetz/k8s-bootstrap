#!/bin/bash

set -euo pipefail


NODE_NAME="$(hostname)"
echo -e "\n\e[0;96mBootstrapping k8s worker node on [${NODE_NAME}]...\e[0m\n"
cd $HOME

mkdir -p ~/.kube
scp root@master0:/root/.kube/config ~/.kube/config

kubeadm join --discovery-file ~/.kube/config

echo 'Waiting for the Calico components to be ready...'
until kubectl -n calico-system get po --field-selector spec.nodeName=${NODE_NAME} -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n calico-system wait po --field-selector spec.nodeName=${NODE_NAME} --for 'condition=Ready' --timeout=10m


tar Cxf /usr/bin redist/calicoctl-linux-amd64-v3.24.1.tgz


echo -e "\n\e[0;32mK8s worker node is all set on [${NODE_NAME}].\e[0m\n"
