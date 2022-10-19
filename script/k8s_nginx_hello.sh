#!/bin/bash

set -euo pipefail


kubectl create deploy hello --image nginxdemos/hello:plain-text
kubectl expose deploy hello --port 80
kubectl create ing hello --rule /hello=hello:80
until kubectl get po -l app=hello -o jsonpath='{.items[0].metadata.name}' &>/dev/null; do sleep 1; done
kubectl wait po -l app=hello --for 'condition=Ready' --timeout=10m
