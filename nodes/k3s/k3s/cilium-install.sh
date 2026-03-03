#!/bin/bash 

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./cilium upgrade --version 1.19.1 -f cilium.yaml

