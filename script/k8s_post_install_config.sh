#!/bin/bash

set -euo pipefail


cd $HOME

kubectl apply -f redist/metrics-server-components-ha.yaml
echo 'Waiting for Calico network plugin to be ready...'
until kubectl -n kube-system get po -l k8s-app=metrics-server -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l k8s-app=metrics-server --for='condition=Ready' --timeout=10m

