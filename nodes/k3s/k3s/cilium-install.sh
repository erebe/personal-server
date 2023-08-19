#!/bin/bash 

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./cilium install --version 1.14.1 -f cilium.yaml

