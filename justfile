release app:
    #!/usr/bin/env bash
    SECRET=$(sops exec-env services/secrets/webhook.yml 'echo ${DEPLOYER_SECRET}')
    curl -i -X POST \
        -H 'Content-Type: application/json' \
        -H "X-Webhook-Token: ${SECRET}" \
        -d '{ "application_name": "{{app}}", "image_tag": "latest" }' \
        -s https://hooks.erebe.eu/hooks/deploy

install:
    sops -d --extract '["public_key"]' --output ~/.ssh/erebe_eu.pub secrets/ssh.yml
    sops -d --extract '["private_key"]' --output ~/.ssh/erebe_eu secrets/ssh.yml
    chmod 600 ~/.ssh/erebe_eu*
    grep -q erebe.eu ~/.ssh/config > /dev/null 2>&1 || cat config/ssh_client_config >> ~/.ssh/config
    mkdir ~/.kube || exit 0
    sops -d --output ~/.kube/config secrets/kubernetes-config.yml

dns:
    #!/usr/bin/env bash
    set -euo pipefail
    CF_KEY=$(sops -d --extract '["apirest"]["key"]' secrets/cloudflare.yml)
    # zone id : zone file. Cloudflare's import *replaces* the zone, so these
    # files are the source of truth - records are never edited in the dashboard.
    #
    # The -f check is not paranoia. curl posts an empty body for a missing
    # `--form file=@...`, and the reply arrives as a lone `null` out of
    # `jq .success`, sitting between the other zones' `true`s. That is how a
    # third zone here - erebe.eus, whose file went away in f3c1638 - kept being
    # "published" long after there was nothing left to publish. Fail loudly.
    for zone in \
        0acc1290d9dd674f677b6d3580611e6a:dns/erebe.eu.zones \
        8b8062d04b84fe017d647cbaa46e29e7:dns/erebe.dev.zones
    do
        zone_id="${zone%%:*}"
        zone_file="${zone#*:}"
        [[ -f "${zone_file}" ]] || { echo "no such zone file: ${zone_file}" >&2; exit 1; }
        printf '%s -> ' "${zone_file}"
        curl -s --request POST \
            --url "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/import" \
            --header 'Content-Type: multipart/form-data' \
            --header 'X-Auth-Email: cloudflare@erebe.eu' \
            --header "Authorization: Bearer ${CF_KEY}" \
            --form "file=@${zone_file}" \
            --form proxied=false | jq .success
    done

k8s:
    kubectl apply -k k8s/cert-manager
    kubectl apply -f k8s/coredns-custom.yaml
    kubectl apply -f k8s/lets-encrypt-issuer.yml
    kubectl apply -f k8s/wildward-erebe-eu.yaml
    kubectl delete secret cloudflare-credentials --namespace cert-manager || exit 0
    kubectl create secret generic cloudflare-credentials --namespace cert-manager \
        --from-literal=api-token="$(sops -d --extract '["apirest"]["key"]' secrets/cloudflare.yml)"
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm upgrade --install nfs-nvme nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -f k8s/nfs-provisioner-nvme-values.yaml
    helm upgrade --install nfs-hdd  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -f k8s/nfs-provisioner-hdd-values.yaml

envoy:
    helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm -f k8s/envoy-crds.yaml --version v1.9.1 | kubectl apply --server-side --force-conflicts -f -
    helm upgrade envoy oci://docker.io/envoyproxy/gateway-helm --version v1.9.1 -n default --create-namespace -f k8s/envoy.yaml --skip-crds
    kubectl apply -f k8s/gateway.yaml

csi:
    helm repo add democratic-csi https://democratic-csi.github.io/charts/
    helm repo update
    helm upgrade --install zfs-iscsi democratic-csi/democratic-csi \
        --namespace democratic-csi \
        --values k8s/democratic-csi/zfs-iscsi-values.yaml --create-namespace
    helm upgrade --install local-hostpath democratic-csi/democratic-csi \
        --namespace democratic-csi \
        --values k8s/democratic-csi/local-hostpath-values.yaml --create-namespace
