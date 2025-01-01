#!/bin/bash 

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./cilium upgrade --version 1.16.5 -f cilium.yaml

