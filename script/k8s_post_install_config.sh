#!/bin/bash

set -euo pipefail


cd $HOME
mkdir -p /root/.kube
scp root@master0:/root/.kube/config /root/.kube/


echo "Approving CSRs for kubelet serving certs..."
until kubectl certificate approve $(
	kubectl get csr -o jsonpath='{.items[?(@.spec.signerName=="kubernetes.io/kubelet-serving")].metadata.name}'
); do sleep 1; done


echo -e "\n\e[0;96mConfiguring eventrouter...\e[0m\n"
kubectl apply --server-side -f conf/eventrouter.yaml
echo 'Waiting for the eventrouter components to be ready...'
until kubectl -n kube-system get po -l app=eventrouter -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l app=eventrouter --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring local-path-provisioner...\e[0m\n"
kubectl apply --server-side -f conf/local-path-provisioner-v0.0.22.yaml
kubectl annotate storageclasses.storage.k8s.io local-path storageclass.kubernetes.io/is-default-class=true
echo 'Waiting for the local-path-provisioner components to be ready...'
until kubectl -n local-path-storage get po -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n local-path-storage wait po --all --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring node-problem-detector...\e[0m\n"
helm upgrade --install node-problem-detector ./redist/charts/node-problem-detector-2.2.6.tgz \
	--namespace=kube-system \
	--values conf/node-problem-detector-chart-values.yaml
echo 'Waiting for the node-problem-detector to be ready...'
until kubectl -n kube-system get po -l app=node-problem-detector -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n kube-system wait po -l app=node-problem-detector --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring Loki...\e[0m\n"
helm upgrade --install loki ./redist/charts/loki-3.2.1.tgz \
	--namespace=loki --create-namespace \
	--values conf/loki-chart-values.yaml
echo 'Waiting for the Loki components to be ready...'
until kubectl -n loki get po -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n loki wait po -l app.kubernetes.io/name=loki --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring Promtail...\e[0m\n"
helm upgrade --install promtail ./redist/charts/promtail-6.5.0.tgz \
	--namespace=loki --create-namespace \
	--values conf/promtail-chart-values.yaml
echo 'Waiting for the Promtail components to be ready...'
until kubectl -n loki get po -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n loki wait po -l app.kubernetes.io/name=promtail --for 'condition=Ready' --timeout=10m
kubectl label --overwrite -n loki svc loki-headless prometheus.io/service-monitor=false


echo -e "\n\e[0;96mConfiguring namespace monitoring...\e[0m\n"
kubectl create ns monitoring
kubectl get cm -n kube-system kube-etcd-ca.crt -o yaml | \
	sed 's/namespace:.*/namespace: monitoring/' | \
	kubectl apply -f -
kubectl get secret -n kube-system kube-etcd-healthcheck-client-tls-secret -o yaml | \
	sed 's/namespace:.*/namespace: monitoring/' | \
	kubectl apply -f -


echo -e "\n\e[0;96mConfiguring kube-prometheus-stack...\e[0m\n"
helm upgrade --install kube-prometheus-stack ./redist/charts/kube-prometheus-stack-41.4.0.tgz \
	--namespace=monitoring \
	--values conf/kube-prometheus-stack-chart-values.yaml
echo 'Waiting for the kube-prometheus-stack components to be ready...'
until kubectl -n monitoring get po -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n monitoring wait po --all --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring prometheus-adapter for the Metrics API...\e[0m\n"
helm upgrade --install prometheus-adapter ./redist/charts/prometheus-adapter-3.4.0.tgz \
	--namespace=monitoring \
	--values conf/prometheus-adaptor-chart-values.yaml
echo 'Waiting for the prometheus-adapter components to be ready...'
until kubectl -n monitoring get po -l app.kubernetes.io/name=prometheus-adapter -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n monitoring wait po -l app.kubernetes.io/name=prometheus-adapter --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;96mConfiguring Ingress NGINX Controller...\e[0m\n"
helm upgrade --install ingress-nginx ./redist/charts/ingress-nginx-4.3.0.tgz \
	--namespace=ingress-nginx --create-namespace \
	--values conf/ingress-nginx-chart-values.yaml
echo 'Waiting for the ingress-nginx components to be ready...'
until kubectl -n ingress-nginx get po -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl -n ingress-nginx wait po --all --for 'condition=Ready' --timeout=10m


echo -e "\n\e[0;32mWe are all set.\e[0m\n"
