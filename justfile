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

# Drop into a subshell holding the s3.fr1.next.ink credentials, for poking at
# the restic buckets by hand. Unlike `just install`, nothing is written to
# disk - sops exec-env passes the decrypted values through the environment and
# they die with the shell.
#
# The whole of secrets/restic.yml comes along, so both restic repository
# passwords are in scope here too, not just the S3 keys. Treat the shell as
# holding the keys to both repositories and exit when done.
#
#   aws s3 ls s3://lisez-next/
#   rclone ls s3:lisez-next/nvme
#
# Pass a repository name to select one, so restic runs with no flags at all -
# proxmox does the same thing through /etc/restic/<name>.env:
#   just s3 nvme-backup   ->   restic snapshots / restic ls latest / restic diff
# With no argument both are still reachable, just not selected:
#   restic -r "$RESTIC_NEXTCLOUD_REPOSITORY" \
#     --password-command 'printf %s "$RESTIC_NEXTCLOUD_PASSWORD"' snapshots

# Same idea as `just s3`, but pointed at your own gateway instead of the
# offsite provider: versitygw on scw, reached at https://s3.erebe.eu.
#
#   aws s3 ls
#   aws s3 mb s3://photos && aws s3 cp file s3://photos/
#   rclone ls s3:photos
#
# Two things differ from the next.ink shell. Only the secret half of the root
# account is in sops, and that file is a Kubernetes Secret manifest, so the
# value sits under stringData rather than at the top level; the access key is a
# literal in the deployment, read from there rather than repeated here so the
# two cannot drift. And the gateway runs with --virtual-domain s3.erebe.eu, so a bucket
# is addressed as <bucket>.s3.erebe.eu: bucket names have to be DNS labels,
# and a name containing a dot breaks TLS because the wildcard certificate
# covers exactly one label.

# subshell with the versitygw (s3.erebe.eu) credentials loaded (aws, rclone)
s3-gw:
    #!/usr/bin/env bash
    set -euo pipefail
    AWS_ACCESS_KEY_ID=erebe
    export AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY="$(sops -d --extract '["stringData"]["ROOT_SECRET_ACCESS_KEY"]' services/secrets/versitygw.yml)"
    export AWS_SECRET_ACCESS_KEY
    # versitygw's own default; it has no per-bucket regions.
    export AWS_DEFAULT_REGION=us-east-1
    export AWS_REGION=us-east-1
    export AWS_ENDPOINT_URL=https://s3.erebe.eu
    export RCLONE_CONFIG_S3_TYPE=s3
    export RCLONE_CONFIG_S3_PROVIDER=Other
    export RCLONE_CONFIG_S3_ENV_AUTH=true
    export RCLONE_CONFIG_S3_ENDPOINT="$AWS_ENDPOINT_URL"
    export RCLONE_CONFIG_S3_REGION="$AWS_REGION"
    echo "s3.erebe.eu (versitygw on scw) — aws + rclone configured — exit to drop the credentials"
    exec "${SHELL:-/bin/bash}"

# subshell with the s3.fr1.next.ink credentials loaded (aws, rclone, restic)
s3 repo="":
    #!/usr/bin/env bash
    set -euo pipefail
    exec sops exec-env secrets/restic.yml '
      export AWS_ENDPOINT_URL="https://s3.fr1.next.ink"
      # aws reads AWS_DEFAULT_REGION, most SDKs read AWS_REGION. Set both.
      export AWS_REGION="$AWS_DEFAULT_REGION"
      # rclone needs no config file: this defines the remote `s3:` entirely,
      # and env_auth makes it reuse the AWS_* credentials above.
      export RCLONE_CONFIG_S3_TYPE=s3
      export RCLONE_CONFIG_S3_PROVIDER=Other
      export RCLONE_CONFIG_S3_ENV_AUTH=true
      export RCLONE_CONFIG_S3_ENDPOINT="$AWS_ENDPOINT_URL"
      export RCLONE_CONFIG_S3_REGION="$AWS_DEFAULT_REGION"
      # Selecting a repository is what lets restic run without -r and
      # --password-command. Spelled out per repository rather than derived by
      # indirect expansion, because sops runs this through /bin/sh.
      case "{{repo}}" in
        nextcloud)
          export RESTIC_REPOSITORY="$RESTIC_NEXTCLOUD_REPOSITORY"
          export RESTIC_PASSWORD="$RESTIC_NEXTCLOUD_PASSWORD" ;;
        nvme-backup)
          export RESTIC_REPOSITORY="$RESTIC_NVME_BACKUP_REPOSITORY"
          export RESTIC_PASSWORD="$RESTIC_NVME_BACKUP_PASSWORD" ;;
        "") ;;
        *) echo "unknown repository: {{repo}} (nextcloud | nvme-backup)" >&2; exit 1 ;;
      esac
      echo "s3.fr1.next.ink — aws + rclone${RESTIC_REPOSITORY:+ + restic → {{repo}}} — exit to drop the credentials"
      exec "${SHELL:-/bin/bash}"
    '


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
