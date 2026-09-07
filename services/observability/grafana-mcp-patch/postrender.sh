#!/usr/bin/env bash
# Helm post-renderer for the grafana-mcp release.
#
# Reads helm's rendered manifests on stdin, runs them through the kustomization
# next to this script, and writes the result to stdout. Used only to set
# ipFamilyPolicy on the Service, which the chart has no value for.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

cat > "${tmp}/all.yaml"
cp "${dir}/kustomization.yaml" "${tmp}/kustomization.yaml"
kustomize build "${tmp}"
