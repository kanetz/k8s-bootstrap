#!/bin/bash

set -euo pipefail


cd $HOME
kubectl apply -f conf/tekton-release-v0.40.2.yaml
