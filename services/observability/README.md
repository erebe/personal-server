# observability

Loki, kube-prometheus-stack (prometheus-operator + Prometheus + Grafana +
kube-state-metrics + node-exporter) and Alloy, as three Helm releases in the
`observability` namespace.

```
just observability            # deploy / upgrade everything
just observability_password   # print the Grafana admin password
```

Grafana is at <https://grafana.erebe.eu> (the `*.erebe.eu` wildcard already
points at the envoy Gateway, so there is no DNS record to add). Prometheus and
Loki are deliberately **not** routed from outside - neither has authentication
of its own. Reach them with a port-forward:

```
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n observability port-forward svc/loki 3100:3100
```

## Layout

| Release | Chart | Provides |
| --- | --- | --- |
| `loki` | `grafana/loki` 7.3.0 | StatefulSet, 1 pod, 50Gi |
| `kube-prometheus-stack` | `prometheus-community/kube-prometheus-stack` 90.0.0 | Prometheus (1, 50Gi), Grafana (1, 10Gi), operator, kube-state-metrics, node-exporter |
| `alloy` | `grafana/alloy` 1.12.1 | DaemonSet, all nodes - pod logs |
| `alloy-events` | `grafana/alloy` 1.12.1 | Deployment, 1 pod - Kubernetes events |
| `grafana-mcp` | `grafana-community/grafana-mcp` 0.22.0 | MCP server over Grafana, ClusterIP only |

Plus the operator CRDs from `prometheus-community/prometheus-operator-crds`
31.0.1, applied separately - see below.

Single instance throughout: Loki is one `-target=all` binary on a local
filesystem, Prometheus is one replica, Grafana keeps state in sqlite on its own
volume, Alertmanager is off. No memcached tiers, no read/write split, no
gateway, no replication.

Prometheus, Grafana, the operator and kube-state-metrics are pinned to `scw`
with a `nodeSelector` plus a toleration for its
`kubernetes.io/hostname=scw:NoSchedule` taint. Grafana uses
`strategy: Recreate` because sqlite on a ReadWriteOnce volume tolerates exactly
one writer.

### grafana-mcp

An MCP server exposing Grafana as tools an LLM client can call - dashboards,
Prometheus and Loki queries, alert rules. Reachable across the WireGuard mesh at
scw's own internal addresses, no port-forward:

```
cd services
claude mcp add --transport sse grafana http://10.200.1.2:8000/sse \
  -H "Authorization: Bearer $(sops -d --extract '["stringData"]["server-auth-token"]' secrets/grafana-mcp.yml)"
```

Callers must present that bearer token - `MCP_GRAFANA_SERVER_TOKEN`, from
`services/secrets/grafana-mcp.yml` (sops), applied by `just observability`.
Without it the server answers 401. It is separate from the Grafana credentials
the server itself uses. `just observability_mcp_token` prints it.

`--allowed-hosts` is **not optional**. Unset, it defaults to the loopback
variants of `--address` - `localhost:8000`, `127.0.0.1:8000`, `[::1]:8000`, see
`DefaultAllowedHosts` in `http_security.go` - so a client connecting to
`http://10.200.1.2:8000` sends `Host: 10.200.1.2:8000`, matches nothing, and is
rejected with **403**. It is DNS-rebinding protection, and the mesh addresses
plus the in-cluster Service names have to be listed explicitly.

That works through `service.externalIPs`, set to scw's Kubernetes InternalIPs -
which are its wireguard addresses, per `node-ip` in `nodes/scw/k3s/config.yaml`.
Cilium's kube-proxy replacement programs a service frontend for each, so a
connection from anywhere on the mesh is load-balanced straight to the pod.

Cilium picks up `wg0` without any extra configuration. Its documentation:

> by default, a NodePort or LoadBalancer service or a service with externalIPs
> will be accessible through the IP addresses of native devices which have the
> default route on the host **or have Kubernetes InternalIP or ExternalIP
> assigned**

`wg0` carries the InternalIP, so it is auto-detected - the commented-out
`devices: "eth0,wg0"` in `nodes/k3s/k3s/cilium.yaml` is not needed for this.
externalIPs support is on by default with `kubeProxyReplacement: true`; there is
no longer any `externalIPs.enabled` gate in Cilium 1.19.

`ipFamilyPolicy: PreferDualStack` is patched in by `grafana-mcp-patch/` as a
helm `--post-renderer`, because the chart exposes no value for it. Without it the
Service would be IPv6 single-stack - this cluster's `service-cidr` is
`fd02::/112,10.43.0.0/16`, IPv6 first - and its EndpointSlice would carry only
IPv6 backends, leaving the IPv4 externalIP with a frontend and nothing behind it.
`10.200.1.2:8000` would simply not answer.

The Service is a plain `ClusterIP`. `externalIPs` is not tied to the service
type and does all the work on its own, so `LoadBalancer` would only have added a
NodePort allocation - reachable on every node's IP at a port in the 30000-32767
range - and an `EXTERNAL-IP` stuck at `<pending>`, because nothing here assigns
LoadBalancer addresses: no cloud provider, and Cilium's LB IPAM
(`CiliumLoadBalancerIPPool`) is not configured. Nor could it announce over a
wireguard mesh, which has no L2 broadcast domain for `l2announcements` to use.

Security posture, in three layers. It authenticates to Grafana as `admin` and
the `api` tool category proxies arbitrary Grafana API calls, so the blast radius
of reaching it is large - hence:

1. **Caller authentication.** `MCP_GRAFANA_SERVER_TOKEN` makes every request
   without a matching `Authorization: Bearer` return 401.
2. **The node firewall.** `nodes/scw/config/nftables.rules` is `policy drop` and
   accepts port 8000 only from `wg0`, so it is not reachable from the internet
   at all. This is now defence in depth rather than the only control.
3. **Read-only.** `disableWrite: true` unregisters the create/update tools;
   queries and discovery are unaffected.

Auth is basic auth against the same `grafana-admin` sops secret the Grafana
release uses (`GRAFANA_USERNAME`/`GRAFANA_PASSWORD`, a documented mode
upstream). The alternative, `grafana.apiKeySecret`, needs a service account
token minted by hand through the Grafana UI or API - Grafana has no way to
provision one declaratively - so it would add a manual step for no gain.

`disabledCategories` drops `oncall`, `incident`, `sift`, `asserts` and
`pyroscope` - Grafana Cloud and Enterprise features that do not exist in this
install, so leaving them registered only offers tools that always error.

### Why the operator, and why the CRDs are applied by hand

The point of the stack is the CRDs: a workload can ship a `PodMonitor` or
`ServiceMonitor` next to its own manifests instead of everything hanging off
`prometheus.io/*` annotations. Loki and Alloy already use that - both emit a
ServiceMonitor rather than being scraped by annotation. The 24 bundled
dashboards and the kubernetes-mixin rules come along for free.

`crds.enabled: false`, and `just observability` applies them out of band:

```
helm template kps-crds prometheus-community/prometheus-operator-crds --version 31.0.1 \
  | kubectl apply --server-side --force-conflicts -f -
```

Helm does not upgrade CRDs on `helm upgrade`, and these are ~4.4MB of them - the
`prometheuses` one alone is 813KB - which is why they go through server-side
apply. `just envoy` in the repo root already works this way.

**They must be applied before the releases.** Several charts gate their Monitor
objects on `Capabilities.APIVersions.Has "monitoring.coreos.com/v1/..."`, so
with the CRDs absent Loki silently produces no ServiceMonitor and no
PrometheusRule. The recipe orders it correctly; keep it that way.

### What is switched off for k3s

Four of the stack's control-plane targets do not exist here, and each would sit
permanently `Down` with its alerts firing:

| Disabled | Why |
| --- | --- |
| `kubeControllerManager` | k3s runs it in-process, metrics bound to localhost |
| `kubeScheduler` | same |
| `kubeProxy` | `nodes/k3s/k3s/config.yaml` sets `disable-kube-proxy: true` |
| `kubeEtcd` | single k3s server, so the datastore is sqlite - there is no etcd |

The matching `defaultRules` groups are off too, otherwise the rules alert about
components that are deliberately absent. `kubelet`, `kubeApiServer` and
`coreDns` all work and stay on.

### Why Alloy is not a single instance

Alloy tails container log files from `/var/log/pods` on the node it runs on, so
one pod would only ever collect the logs of pods sharing its node. It is a
DaemonSet with `tolerations: [{operator: Exists}]` so it lands on every node,
including the tainted ones - every node in this cluster carries a taint. That is
coverage, not HA: no clustering, no leader election, no replication.

`node-exporter` is a DaemonSet for the same reason. `kube-state-metrics` is a
single instance next to Prometheus.

### Why Kubernetes events are a second Alloy release

`alloy-events` is a one-replica Deployment running
`loki.source.kubernetes_events`, and it is separate from the DaemonSet for the
mirror-image reason. Events are cluster-scoped API objects, not node-local
files, so a DaemonSet would watch the same stream from every node and push a
copy of every event per node. Upstream is explicit that the component is not
safe deployed that way - its `clustering` block only *minimises* duplicates,
warning that "when a namespace moves from one cluster node to another the new
node may re-deliver events that were already sent by the previous node".

One replica avoids the problem entirely. Nothing needs to be highly available:
if the pod is down, events in that window go uncollected, the same trade already
made for metrics and logs.

The component attaches `namespace`, `job` and `instance` labels itself, so no
processing stage is needed - query them straight away:

```
{job="kubernetes-events"}
{job="kubernetes-events", namespace="observability"}
```

Kind, name, reason and message stay in the logfmt line rather than becoming
labels; they are high-cardinality and would multiply Loki streams. RBAC comes
free - the chart's default ClusterRole already grants `get/list/watch` on
events.

### Where the volumes live

All three volumes are on scw's own 2TB NVMe RAID1, through a **second
democratic-csi release** (`k8s/democratic-csi/local-hostpath-values.yaml`,
installed by `just csi` alongside the iSCSI one). Nothing in this stack touches
iSCSI or crosses WireGuard for storage.

k3s's bundled `local-storage` is disabled in `nodes/k3s/k3s/config.yaml` and
re-enabling it is not an option: k3s marks its `local-path` class as default and
`nfs-nvme` already holds that role, so there would be two defaults and
karakeep's PVCs - which name no class - would become ambiguous.

Four things about that release are load-bearing:

- `csiDriver.attachRequired: false`. The driver deliberately does not advertise
  `PUBLISH_UNPUBLISH_VOLUME` (commented out at
  `src/driver/controller-client-common/index.js:68`) because a directory is
  bind-mounted by the node plugin, never attached. At the chart's default of
  `true`, every pod would wait forever on a `VolumeAttachment` nothing creates.
- `csiDriver.fsGroupPolicy: File`. kubelet only applies a pod's `fsGroup` to a
  CSI volume according to this policy, and the default
  `ReadWriteOnceWithFSType` needs an fsType - which a bind-mounted directory has
  not got. Without it kubelet skips the chown, the directory stays
  `root:root 0770`, and Prometheus dies with `open /data/queries.active:
  permission denied`. Each workload also sets `fsGroupChangePolicy:
  OnRootMismatch` so kubelet does not re-walk the whole TSDB on every restart.
- `volumeBindingMode: WaitForFirstConsumer`. The volume is a directory on one
  machine, so the PV cannot be bound before the scheduler has placed the pod.
- `controller.strategy: node`. The controller sidecars ride on the node
  DaemonSet, so the thing creating the directory runs on the machine that owns
  it. With the DaemonSet pinned to scw, provisioning can only happen on scw.

## Prerequisites

`just csi` (repo root) must have run since the `local-hostpath` release was
added, so the StorageClass and its node DaemonSet exist on scw. Without it every
PVC sits `Pending` and the pods stay in `ContainerCreating`.

```
kubectl get sc local-hostpath-scw
kubectl -n democratic-csi get pods -o wide   # expect a local-hostpath pod on scw
```

Nothing here needs `zfs-nvme` any more, so the old iSCSI prerequisites - the scw
toleration on the CSI node plugin, and `open-iscsi` from
`nodes/common/tasks/package.yml` - no longer gate this stack. Both changes are
still in the repo and remain correct for anything else wanting `zfs-nvme` on
scw.

## Things worth knowing

- **Nothing enforces the claim sizes.** `local-hostpath` provisions a plain
  directory under `/var/lib/csi-local-hostpath` on scw and applies no quota, so
  every size above is documentation. The only real budget is
  `prometheusSpec.retentionSize: 40GB`, which also protects Prometheus from a
  full filesystem - it wedges rather than pruning when the disk fills. **Loki
  has no byte-based retention at all**, only `retention_period: 720h`, so its
  footprint is whatever 30 days of ingest happens to be. There is a lot of room
  on 2TB, but it is the one genuinely unbounded thing here.

- **Nothing here is backed up.** All volumes live only on scw, no snapshots and
  no off-node copy, so rebuilding that node loses everything. For metrics and
  logs that is the deliberate trade for the local write path. For Grafana, what
  is actually at stake is small: the dashboards, datasources and admin password
  are all provisioned from grafana.com, `kube-prometheus-stack-values.yaml` and
  `services/secrets/grafana.yml`, so the exposure is dashboards you build by
  hand, users you add, and saved preferences. If that matters, the cheapest
  cover is a CronJob in the mould of `services/backup/` copying
  `/var/lib/grafana/grafana.db` - a few MB.

- **Alerts fire but go nowhere.** `defaultRules` creates 29 PrometheusRules, and
  Alertmanager is disabled - there is no routing or receiver config anywhere in
  the repo. Firing alerts are visible in the Prometheus UI and Grafana's
  alerting view; nothing pages anyone. The recording rules are the half that
  matters day to day: several bundled dashboards plot them.

- **The operator's admission webhooks are off.** They validate PrometheusRule
  syntax at apply time, at the cost of two hook Jobs plus a Mutating and a
  ValidatingWebhookConfiguration. We are not hand-writing rules, and the
  previous incarnation of this stack (`k8s/old/prometheus.yaml`) had them off
  too.

- **26 dashboards.** 24 arrive as ConfigMaps read by Grafana's sidecar, plus two
  fetched from grafana.com by an init container: 1860 (Node Exporter Full, rev
  45) and 13639 (Logs / App, rev 2). Loki's chart contributes two more of its
  own. The kubernetes cluster/namespace/node/pod dashboards that used to be
  pulled by id are now redundant - the stack's kubernetes-mixin ones cover
  that ground - so 15757-15760 and 3662 were dropped.

  Pinned revisions matter: a `gnetId` with no `revision` resolves to revision 1,
  which for 1860 means a dashboard last touched in 2017. Check the latest before
  adding one:

  ```
  curl -s https://grafana.com/api/dashboards/<id> | jq '{name, revision}'
  ```

- **Only 13639 gets a `datasource` mapping**, because it is the one that
  hardcodes `"datasource": "${DS_LOKI}"` inline; 1860 resolves its own through a
  template variable. Note the mapping uses the list form (`- name: DS_LOKI` /
  `value: Loki`) - the string shorthand seds *every* `"datasource"` field in the
  file, which silently breaks any dashboard querying more than one source.

- **Grafana needs egress to grafana.com to start.** That init container runs on
  every pod start with `set -eufo pipefail` and `curl -f`, so if grafana.com is
  unreachable the pod stays in `Init` rather than starting without those two
  dashboards. It fails loudly, which is the chart's tested default, but it does
  couple a monitoring stack to an external website. To make it non-fatal, drop
  the `e`: `defaultShellOptions: "ufo pipefail"`.

- **Retention is 30 days** on both sides: Loki via
  `limits_config.retention_period` plus a compactor with `retention_enabled`
  (Loki deletes nothing without it), Prometheus via `retention: 30d`.

- **Alloy's log labels** are `namespace`, `pod`, `container`, `node` and a `job`
  of `<namespace>/<container>`. Lines are parsed with `stage.cri {}`, the format
  containerd writes under k3s - the real timestamp and the stdout/stderr stream
  come from there, not from the message text.

- **Deleting a `zfs-nvme` PVC used to be impossible** while sanoid was
  snapshotting it. democratic-csi tags each zvol
  `democratic-csi:managed_resource=true`, ZFS snapshots inherit their dataset's
  user properties, and the driver then cannot tell a sanoid snapshot from one of
  its own - so `DeleteVolume` fails with `FailedPrecondition ... filesystem has
  dependent snapshots` and the PVC hangs in `Terminating`. Fixed by a
  `post_snapshot_script` in `nodes/proxmox/sanoid/`, applied with
  `cd nodes && just proxmox --tags sanoid`. This no longer affects this stack,
  which is entirely on local storage, but it applies to any `zfs-nvme` PVC. To
  clear an already stuck volume, destroy its snapshots on the storage host:

  ```
  zfs destroy -r nvme/k8s-test/pvc-<uuid>
  ```
