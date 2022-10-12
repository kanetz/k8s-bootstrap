#!/bin/bash

set -euo pipefail


kubectl create deploy hello --image nginxdemos/hello:plain-text
kubectl expose deploy hello --port 80
kubectl create ing hello --rule /=hello:80
