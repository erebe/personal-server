# AGENT.md — working notes for AI agents

## Things that will bite you if you skip

- **Ansible tasks are all `never`-tagged.** `just <node>` runs nothing; you must
  pass `--tags`.
- **`kubectl apply --prune --applyset`** is used for every service, so deleting
  a resource from a kustomization deletes it from the live cluster.
- **Every node is tainted** `kubernetes.io/hostname=<name>:NoSchedule`; a
  workload needs affinity *and* toleration.
- **`README.md` is a 2020-2023 blog post**, not current documentation.
- **No tests, no validating CI** — production is the only feedback loop. Dry-run
  first, and say clearly when something can't be verified without applying.
- **Comments explain the failure they prevent** — terse, a line or two. A bare
  value with no rationale is a regression here; so is a paragraph where a
  sentence does.

## What this repository is

Infrastructure-as-code for one person's personal server estate (`erebe.eu`).
There is **no application to build or test here** (with two small exceptions,
`services/blog` and `services/blog-back`). Everything else is declarative
configuration applied to live machines:

| Layer | Tool | Where |
| --- | --- | --- |
| Bare metal / VM / OS config | Ansible | `nodes/` |
| Kubernetes workloads | kustomize + Helm | `services/` |
| Cluster-level infrastructure | kubectl + Helm | `k8s/` |
| Secrets | sops + GPG | `secrets/`, `services/secrets/` |
| DNS | zone files pushed to Cloudflare | `dns/` |
| Entry point for everything | `just` | `justfile`, `nodes/justfile`, `services/justfile` |

Consequences for an agent: there is no test suite and no CI that validates a
change. **The only feedback loop is applying to production.** Prefer dry runs
(`--check`, `kustomize build`, `helm template`) and say plainly when a change
cannot be verified without applying it.

`README.md` (1.9k lines) is a *blog post* from 2020-2023 about building this
setup. It is historically interesting and substantially out of date (it
describes nginx-ingress, postfix/dovecot, pihole, Makefiles). **Do not treat it
as current documentation.** The authoritative descriptions of current state are
the inline comments in the config files themselves, plus
`services/observability/README.md` and `services/_components/README.md`.

## House style — read this before writing anything

This repo has one very distinctive convention: **comments explain the failure
they prevent, not what the line does.** Non-obvious settings carry the reason
they are that value, and what breaks if someone "simplifies" them. Examples
worth reading to calibrate: `nodes/group_vars/all.yml` (MTU derivation),
`nodes/common/tasks/networkd.yml` (why dhcpcd is masked but not stopped),
`k8s/gateway.yaml` (why :80 is namespace-restricted),
`k8s/democratic-csi/local-hostpath-values.yaml` (four load-bearing settings).

**Keep them terse — one or two lines.** State the fact that is not obvious from
the code: the error text, the flag's default, why the value is load-bearing.
Then stop. No line-by-line narration, no retelling how it was found, no
repeating context from the file header. A bare value with no rationale is a
regression here; so is a paragraph where a sentence does.

Other conventions:

- **Versions are pinned deliberately** everywhere — k3s (`nodes/common/tasks/k3s-*.yml`),
  Helm charts (`services/justfile`, root `justfile`), container image tags,
  cilium, envoy-gateway. Bump them intentionally, one at a time, never
  opportunistically as a side effect of another change.
- Commit messages are almost all literally `bump`. Don't read history for
  intent; read the comments.
- Prefer editing the existing file over introducing a new abstraction layer.
- IPv6 is first-class and often *first* (service CIDR, node IPs, NFS server
  addresses). Never assume IPv4-only.

## Repository map

```
justfile              root recipes: cluster bootstrap, DNS, envoy, CSI, releases
nodes/                Ansible: one directory + playbook per machine
  inventory.ini       the machine list — start here
  group_vars/all.yml  WG hub addresses (resolved from DNS), wg_mtu
  common/tasks/       shared task files: package, networkd, wireguard, k3s-{master,agent}
  <node>/playbook.yml per-node play; all tasks are `never`-tagged (see below)
  <node>/config/      systemd-networkd units, nftables rules, sshd, sudoers
  <node>/k3s/         that node's /etc/rancher/k3s/config.yaml
  <node>/wireguard/   wg*.conf.j2 templates
services/             kustomize-based k8s workloads, one dir per service
  justfile            one recipe per service
  _components/        shared kustomize Components (node tolerations) — read its README
  secrets/            sops-encrypted k8s Secret manifests, consumed via ksops
  observability/      Helm values for Loki/Prometheus/Grafana/Alloy — read its README
k8s/                  cluster-level: cert-manager, envoy gateway, CSI drivers, coredns
dns/                  Cloudflare zone files for erebe.eu / erebe.dev
secrets/              sops-encrypted infra secrets (wireguard, ssh, kubeconfig, cloudflare)
secrets_decrypted/    gitignored scratch output of `sops -d` (all of them, everywhere)
benchmarks/           untracked storage benchmark results (fio across storage classes)
```

## The machines

From `nodes/inventory.ini`. Node names are also k3s node names and taint values.

| Node | Address | Role |
| --- | --- | --- |
| `k3s` | 192.168.1.10 (VM on proxmox) | **k3s control plane** (`node-name: master`) |
| `toybox` | 192.168.1.11 (VM on proxmox) | k3s agent, carries most workloads |
| `proxmox` | 192.168.1.4, root login | hypervisor + ZFS/NFS/iSCSI storage host. Not a k8s node |
| `dns` | 192.168.1.2 (Raspberry Pi) | k3s agent, runs AdGuard Home on hostNetwork |
| `router` | 192.168.1.1 (UniFi UDM), root login | WireGuard hub for the LAN subnet. Not a k8s node |
| `server` | erebe.eu / 49.13.58.9 (Hetzner) | k3s agent, **public entry point** — envoy Gateway lives here |
| `scw` | scw.erebe.eu (Scaleway) | k3s agent, runs the observability stack on local NVMe |
| `styx` | 127.0.0.1, local connection | erebe's desktop — WireGuard client profiles only |
| `laptop` | commented out in inventory | WireGuard client profiles only |

There is no mail node any more — mail is the `stalwart` k8s service. The
`MAIL_*` WireGuard keypair and the `dovecot`/`fetchmail` sops secrets that
belonged to the retired postfix stack are gone too.

Proxmox host details (CPU pinning per CCX, why RAM is the binding constraint,
known unfixed issues like the `nvme` pool being a stripe rather than a mirror)
are in the session memory note `proxmox-host-layout`.

## Ansible: the single most important gotcha

**Every task in every node playbook is tagged `never`.** Running
`ansible-playbook server/playbook.yml` — or `just server` — executes *nothing*.
You must name a tag:

```
cd nodes
just server --tags wireguard        # render + reload wg0.conf
just server --tags firewall         # push nftables.rules
just scw    --tags k3s-agent        # install/upgrade k3s
just k3s    --tags k3s-master,cilium
just proxmox --tags sanoid          # sanoid.conf + the syncoid timers
just scw    --tags sanoid           # sanoid.conf + the key proxmox pulls with
just <node> --tags <tag> --check    # dry run — do this first
```

Tags in use: `package`, `network`, `migrate-networkd`, `firewall`, `ssh`,
`sudo`, `wireguard`, `k3s-agent`, `k3s-master`, `cilium`, `sanoid`. Not every
node has every tag — read its `playbook.yml`.

Other Ansible facts worth knowing:

- `just` recipes are **per-directory**. `just server` only exists inside
  `nodes/`. The root `justfile` and `services/justfile` are different recipe
  sets with overlapping-looking names.
- `ansible.cfg` sets `inject_facts_as_vars = False`. WireGuard templates
  reference `{{ ansible_facts.<NODE>_PRIVATE_KEY }}`, which only resolves
  because `community.sops.load_vars` is called with `name: ansible_facts`.
  Omitting that renders empty configs with no error. See
  `nodes/common/tasks/wireguard.yml`.
- Facts are cached in `nodes/.ansible_facts_cache` (gitignored, 24h).
- `group_vars/all.yml` resolves `erebe.eu` and `scw.erebe.eu` to literal IPs at
  render time via `getent`, on purpose: `wg-quick` resolves an `Endpoint` only
  once at interface bringup, and some of these nodes *are* the DNS server. The
  cost is that a hub IP change requires re-running the playbook. If DNS on the
  control node is broken, these lookups fail loudly with a `mandatory()` message.
- `nodes/common/tasks/networkd.yml` deliberately masks-but-does-not-stop dhcpcd
  and deletes netplan's generated units. It prints a reboot reminder rather than
  rebooting. Don't "fix" this into a stop or a reboot.

## WireGuard overlay

Two hub-and-spoke subnets, joined to each other, all on UDP **995** (except LAN
nodes' own `ListenPort` of 51820):

| Subnet | Hub | Members |
| --- | --- | --- |
| `10.200.0.0/24` + `fd00:cafe::/64` | `router` (`.1`) | dns `.2`, k3s `.3`, toybox `.4`, proxmox `.7`, styx `.52` |
| `10.200.1.0/24` + `fd00:cafe:1::/64` | `server` (`.1`) | scw `.2`, laptop `.50`, phone `.51`, styx-full-tunnel `.52` |

Rules that keep coming up:

- Direct peer entries with `/32` + `/128` are carved out of the hub's `/23` +
  `/32` on purpose, so LAN↔WAN nodes tunnel directly instead of hairpinning
  through a hub. Longest-prefix match is what makes this work — narrowing or
  widening a prefix silently reroutes or blackholes traffic.
- The `router` peer must carry the whole LAN `/24`, not just `.1`: WireGuard
  drops a decrypted packet whose source falls outside the `AllowedIPs` of the
  peer it arrived on. A `/32` there blackholes every spoke behind the router.
- Nodes behind home NAT get **no** `Endpoint` (learned from handshake) and use
  `PersistentKeepalive = 20`.
- `wg_mtu: 1440` is derived in `group_vars/all.yml` from a measured 1500-byte
  IPv4 path; the derivation is spelled out there. It intentionally replaces
  wg-quick's default of 1420.
- `styx` renders three profiles but `wg_autostart: [wg0]` starts only the
  overlay one; `wgall` (exit via server) and `wgall-scw` (exit via scw) are
  chosen locally with `systemctl enable --now wg-quick@<name>`.

To add a WireGuard node: add `<NODE>_PRIVATE_KEY`/`_PUBLIC_KEY` to
`secrets/wireguard.yml` with `sops`, create
`nodes/<node>/wireguard/wg0.conf.j2` and `playbook.yml`, add a `[Peer]` block on
the appropriate **hub** template (`router` for LAN, `server` for anything
terminating outside it) with a free address in that hub's subnet, add matching
direct peers on any node that should reach it without hairpinning, then wire the
node into `nodes/site.yml` and `nodes/justfile`.

WireGuard is managed exclusively through Ansible. There is deliberately no
root-level `just wireguard`: the recipe that used to live there templated a
single hand-maintained `wg0.conf` for `erebe.eu` only, and was removed once
every node got its own `.j2`.

## The Kubernetes cluster

k3s, single control-plane node, dual-stack **IPv6-first**. Config in
`nodes/k3s/k3s/config.yaml`:

- `cluster-cidr: fd01::/48,10.42.0.0/16`, `service-cidr: fd02::/112,10.43.0.0/16`
- Node IPs are the **WireGuard overlay addresses**, so all apiserver, kubelet
  and CNI traffic rides the tunnels. Agents join at `https://[fd00:cafe::3]:6443`.
- Disabled: `servicelb`, `traefik`, `local-storage`, `kube-proxy`,
  `network-policy`, `helm-controller`, flannel.
- CNI is **Cilium** (`kubeProxyReplacement: true`, hubble off, envoy off),
  installed by `nodes/k3s/k3s/cilium-install.sh` via `just k3s --tags cilium`.

### Every node is tainted

Each node carries `kubernetes.io/hostname=<name>:NoSchedule` (the master
carries `node-role.kubernetes.io/master:NoSchedule`). **A workload therefore
needs both a nodeAffinity and the matching toleration**, or it stays Pending
forever. Use the shared Components:

```yaml
components:
  - ../_components/toleration-toybox     # or toleration-server
```

Read `services/_components/README.md` before touching this: a kustomize
Component *replaces* the whole `tolerations` list, so the four services with
bespoke lists (`adguard`, `dashy`, `minio`, `postgres`) deliberately don't use
these.

### Ingress: Envoy Gateway

One `Gateway` named `envoy` in the `default` namespace, bound to server's public
IPs (`49.13.58.9`, `2a01:4f8:c013:7b8::1`), defined in `k8s/gateway.yaml`,
deployed with root `just envoy`. Listeners: HTTP 80, HTTPS 443 (terminates the
`erebe-eu-tls` wildcard from cert-manager), plus raw **TCP** on 25/587/465/993
for mail.

- Services expose themselves with an `HTTPRoute` whose `parentRefs: [{name: envoy}]`
  and a `hostnames:` entry. DNS needs no new record — `*.erebe.eu` already
  points at the Gateway.
- Mail uses `TCPRoute` (not TLS/Passthrough) on purpose: Envoy only inserts the
  `tls_inspector` filter when it must match SNI, and SMTP's server-first `220`
  banner deadlocks behind it.
- The `:80` listener only accepts routes from the `https-redirect` namespace, so
  the global 301 redirect isn't outbid by per-service routes. `allowedRoutes`
  can't filter by route name, which is why that namespace exists.
- `k8s/gateway.yaml` also holds the HTTP/3, ALPN and compression policies; each
  has a comment explaining what breaks without it.

### Storage classes

| Class | Backing | Notes |
| --- | --- | --- |
| `nfs-nvme` | proxmox `fd00:cafe::7:/nvme` over NFSv4 | **cluster default** |
| `nfs-hdd` | proxmox `fd00:cafe::7:/backup/data` | bulk / backup |
| `zfs-nvme` | democratic-csi zfs-generic-iscsi to proxmox | block; see snapshot caveat below |
| `local-hostpath-zdata` | plain directories on scw's `zdata` ZFS mirror (`/mnt/zdata`) | observability only, `WaitForFirstConsumer`, node-deployment provisioning |

Installed by root `just k8s` (NFS provisioners) and `just csi` (democratic-csi).
`benchmarks/storage-benchmark.csv` has fio numbers across all four.

Caveats that have already cost time: deleting a `zfs-nvme` PVC fails while
sanoid snapshots exist (fixed by the `post_snapshot_script` in
`nodes/proxmox/sanoid/`, applied with `just proxmox --tags sanoid`); IPv6-first
service CIDR means a Service without `ipFamilyPolicy: PreferDualStack` gets
IPv6-only endpoints, which is why `grafana-mcp` needs a Helm post-renderer.

### ZFS snapshots and replication

sanoid takes the snapshots, syncoid moves them, both driven by systemd timers.
Two hosts run sanoid, each with its own `sanoid/sanoid.conf` under `nodes/<node>/`
(the file cannot include another, so the shared `template_*` blocks are
duplicated on purpose); the install half is `nodes/common/tasks/sanoid.yml` and
both are applied with `--tags sanoid`.

| Pair | Direction | When | Retention |
| --- | --- | --- | --- |
| `nvme` -> `backup/nvme-backup` | local, on proxmox | `syncoid-backup.timer`, 00:01 | 36 hourly + 7 daily on source, 90 daily on target |
| scw `zdata` -> `backup/scw-backup` | **pull** over wg0, proxmox -> `erebe@10.200.1.2` | `syncoid-scw.timer`, 03:00 | same |
| `backup/data` | not replicated | — | `template_archive`: 30 daily, 8 weekly, 12 monthly |

Things to know before touching it: pulls, not pushes, so the credential lives
on the host holding the backups (`/etc/syncoid/id_scw`, from
`secrets/syncoid.yml`, authorized for `erebe` on scw with `from=` and
`restrict`); snapshot names are **UTC** because the packaged `sanoid.service`
sets `TZ=UTC`, which is why 03:00 local is after scw's daily and why a replica
can look 2h stale when it is not; a replica section needs `autosnap = no` or
the next incremental has to roll it back; and **nothing monitors either timer**,
while a pull that fails for more than 7 days outlives the last common daily and
needs a full send.

## Services inventory

Each directory under `services/` is a kustomize overlay applied by
`cd services && just <name>`. All of them go out as:

```
kustomize build --enable-alpha-plugins --enable-exec --load-restrictor LoadRestrictionsNone <dir>/ \
  | KUBECTL_APPLYSET=true kubectl apply -f - --server-side --prune --applyset=configmaps/<name>-applyset
```

Two things this implies. `--load-restrictor LoadRestrictionsNone` is required
because overlays reach outside their own directory into `../secrets/` and
`../_components/`. And `--prune --applyset` means **removing a resource from a
kustomization deletes it from the cluster** on the next apply. Run
`kustomize build` and read the diff before applying.

| Service | URL | Pinned to | Notes |
| --- | --- | --- | --- |
| `stalwart` | mail.erebe.eu | toybox | mail server (SMTP/IMAP), replaced postfix+dovecot |
| `nextcloud` | cloud.erebe.eu | toybox | two PVCs: nvme + hdd |
| `vaultwarden` | bitwarden.erebe.eu | toybox | |
| `karakeep` | keep.erebe.eu | toybox | own namespace; web + meilisearch + chrome |
| `blog` | **wstunnel.erebe.eu/.dev** | toybox | **Rust/axum static file server**, `services/blog/`. One site per subdir of `public/`, selected by the hostname's first label (`src/sites.rs`); `public/` holds only `wstunnel/` |
| `blog-back` | blog.erebe.eu/.dev — **not routed** | — | Retired Zola blog, **no justfile recipe**. See the warning below |
| `coub` | coub.erebe.eu | toybox | |
| `dashy` | board.erebe.eu | toybox (bespoke tolerations) | dashboard |
| `adguard` | — (hostNetwork :53) | dns (Raspberry Pi) | LAN DNS + adblock, privileged |
| `minio` | — | toybox (bespoke) | S3 |
| `postgres` | — | toybox (bespoke) | CloudNativePG operator |
| `wstunnel` | — (**no HTTPRoute**) | **server** | erebe's own tunnel server; reached on `:8084`, opened in `nodes/server/config/nftables.rules`, not via the Gateway |
| `webhook` | hooks.erebe.eu | toybox | the deployment trigger, see CI/CD |
| `observability` | obs.erebe.eu (Grafana) | **scw** | Helm, not kustomize — `just observability` |
| `backup` | — | server | nightly CronJob, `just backup` |
| `app/warpgate.yml` | *.warp.erebe.eu | — | `just warpgate` |

### The blog / blog-back collision

`services/blog-back` is the retired Zola blog, kept for its `content/blog/*.md`
posts. It has no recipe in `services/justfile`, and **do not add one without
renaming its objects first**: its Service and HTTPRoute are both named `blog` on
port 8087 in `default` — byte-identical to the live `services/blog` — and
`just blog` owns those names through `--applyset=configmaps/blog-applyset`.
Applying `blog-back` as it stands would hand `wstunnel.erebe.eu` to the Zola
pod. `blog.erebe.eu` is currently routed by nothing in this repo.

## Secrets

sops with a single GPG key, fingerprint `2D6D9958A384D88D8F3D1BE8A8F8B1104C38763A`
(`.sops.yaml`). Encrypted files are committed; decrypted output goes to
`secrets_decrypted/` directories, all of which are gitignored (only `.empty`
placeholders are tracked).

- `secrets/` — infra: `wireguard.yml` (all node keypairs), `ssh.yml`,
  `kubernetes-config.yml`, `cloudflare.yml`.
- `services/secrets/` — sops-encrypted **Kubernetes Secret manifests**, pulled
  into overlays with a `ksops` generator (`secret-generator.yaml`, exec path
  `/opt/kustomize/viaduct.ai/v1/ksops/ksops`). This is why every build needs
  `--enable-alpha-plugins --enable-exec`.

Rules: never write a plaintext secret into a tracked file; never `cat` a
decrypted secret into a commit, a PR body, or anything leaving the machine; edit
with `sops <file>` or `sops set`, not by decrypting to disk and re-encrypting.
`just install` (root) bootstraps the local machine's ssh key, ssh config and
kubeconfig from sops.

## CI/CD and releases

There is no test CI. `.github/workflows/` holds two workflows, which build a
container image to `ghcr.io/erebe/*` on a path-filtered push
(`services/blog/**`, `services/webhook/Dockerfile`) and then POST to
`https://hooks.erebe.eu/hooks/deploy` with `X-Webhook-Token`.

That webhook (`services/webhook/`) runs `deploy.sh`, which is simply
`kubectl delete pod -l app=<name>` and waits for Ready — the deployments use
`:latest` with `imagePullPolicy: Always`, so deleting the pod *is* the deploy.
Root `just release <app>` fires the same webhook by hand.

The hook definition (in `services/secrets/webhook.yml`) passes **only**
`application_name` to `deploy.sh`; the `image_digest` and `image_tag` fields in
the payload are decoration and nothing reads them.

## DNS

`dns/erebe.eu.zones` and `dns/erebe.dev.zones` are BIND-style zone files pushed
to Cloudflare's *import* API by root `just dns` (zone IDs and the Cloudflare
token live in that recipe / `secrets/cloudflare.yml`). Import **replaces** the
zone, so the file is the source of truth — edit it, don't touch the Cloudflare
UI.

The recipe loops over `zone_id:file` pairs and refuses to run if a zone file is
missing. That guard exists because a third zone — `erebe.eus`, dropped in
`f3c1638` — went on being "published" from a deleted file for months: `curl`
posts an empty body for a missing `--form file=@...` and `jq .success` prints a
lone `null` between the other zones' `true`s. A good run prints exactly two
`true`s.

Records carry SPF/DKIM/DMARC for the mail server, a `*` wildcard at server's
IPs, an HTTPS/ALPN record, and `scw`. Certificates come from cert-manager +
Let's Encrypt via the Cloudflare DNS-01 token (`k8s/lets-encrypt-issuer.yml`,
`k8s/wildward-erebe-eu.yaml`), applied by root `just k8s`.

## Observability

`services/observability/README.md` is long and genuinely current — read it
before touching that stack. Highlights: everything single-replica on scw's local
disk, Alertmanager off (alerts fire nowhere), 30-day retention, **nothing is
backed up**, and the four k3s-absent control-plane scrape targets are
deliberately disabled. Alloy also ships each node's systemd journal (including
kernel messages) to Loki; the `systemd journal` dashboard is provisioned from
`services/observability/dashboards/` via a `grafana_dashboard=1` ConfigMap,
which is how dashboards get into Grafana here — its API is not the source of
truth. Grafana is at `obs.erebe.eu`. `grafana-mcp` is
reachable over the mesh at
`http://10.200.1.2:8000/sse` with a bearer token from
`just observability_mcp_token`.

## Quick command reference

```
# root — cluster-level
just install                 # bootstrap this machine: ssh key, ssh config, kubeconfig
just k8s                     # cert-manager, issuers, wildcard cert, coredns, NFS provisioners
just envoy                   # Envoy Gateway CRDs (server-side) + chart + Gateway
just csi                     # democratic-csi: zfs-iscsi + local-hostpath
just dns                     # push zone files to Cloudflare
just release <app>           # trigger the deploy webhook

# nodes/ — Ansible (ALWAYS pass --tags)
just <node> --tags <tag> [--check]
just all --tags <tag>        # every node via site.yml

# services/ — kubernetes workloads
just <service>               # kustomize build | kubectl apply --server-side --prune
just observability           # the Helm stack
just observability_password  # Grafana admin password
just nextcloud_resync_file   # occ files:scan --all
```

## Before you finish a change

- `kustomize build --enable-alpha-plugins --enable-exec --load-restrictor LoadRestrictionsNone <dir>/`
  renders cleanly, and you have read the diff for accidental prunes.
- Ansible changes were tried with `--check` where the module supports it.
- Any non-obvious value carries a comment saying why it is that value, in a
  line or two.
- Nothing decrypted or plaintext-secret is staged for commit
  (`git status`, and confirm `secrets_decrypted/` is still ignored).
- Version bumps are separate from behaviour changes.
