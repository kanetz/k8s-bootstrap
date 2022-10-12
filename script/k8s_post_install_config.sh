#!/bin/bash

set -euo pipefail


echo -e "\n\e[0;96mConfiguring additional components...\e[0m\n"
cd $HOME


kubectl certificate approve $(kubectl get csr -o jsonpath='{.items[*].metadata.name}')
kubectl apply -f conf/metrics-server-components-ha.yaml
echo 'Waiting for metrics server to be ready...'
until kubectl -n kube-system get po -l k8s-app=metrics-server -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l k8s-app=metrics-server --for 'condition=Ready' --timeout=10m


kubectl apply -f conf/ingress-nginx-controller-v1.4.0.yaml
echo 'Waiting for nginx ingress controller to be ready...'
until kubectl -n ingress-nginx get po -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n ingress-nginx wait po -l app.kubernetes.io/component=controller --for 'condition=Ready' --timeout=10m
echo 'Setting nginx as default ingress class...'
kubectl annotate --overwrite ingressclass nginx ingressclass.kubernetes.io/is-default-class=true


echo -e "\n\e[0;32mK8s cluster is all set.\e[0m\n"
