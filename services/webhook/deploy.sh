#!/bin/sh

[[ -z "$1" ]] && exit 1

set -o xtrace

app_name="$1"
kubectl delete pod -n default -l app=${app_name}
kubectl wait --for=condition=Ready --timeout=-1s -n default -l app=${app_name} pod
