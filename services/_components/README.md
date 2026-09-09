# _components

Shared [kustomize Components](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/component/)
for the kustomize-based services in this directory. Pull one in with:

```yaml
components:
  - ../_components/toleration-toybox
```

Referencing a path outside the service directory works because every
`kustomize build` in `justfile` already passes `--load-restrictor
LoadRestrictionsNone` (the same thing that lets services reach `../secrets/`).

## toleration-toybox, toleration-server

Every node carries `kubernetes.io/hostname=<name>:NoSchedule`, so a service
pinned to a node needs the matching toleration alongside its affinity. These
supply the toleration half, replacing an inline block that used to be copy-pasted
into each deployment.

Both deliberately omit `effect`. A toleration without one matches every effect
for that key/value, which is exactly what the inline blocks did - adding
`effect: NoSchedule` would silently narrow them.

Used by: blog, blog-back, coub, karakeep (3 deployments), nextcloud, stalwart,
vaultwarden, webhook (toybox); wstunnel (server).

## Services that deliberately do not use these

Four keep bespoke inline tolerations, because a Component replaces the whole
`tolerations` list rather than appending to it - applying one would silently drop
what they carry:

| Service | Why |
| --- | --- |
| `adguard` | raspberry plus `unreachable`, `not-ready` and `node.cilium.io/agent-not-ready` |
| `dashy` | toybox with `effect: NoSchedule`, plus `unreachable` on `NoExecute` |
| `versitygw` | pinned to scw, and there is no `toleration-scw` component |
| `postgres` | its own kustomization patch, with `effect: NoSchedule` |

If a fifth service wants that shape, add a component for it rather than widening
these.

## Not used by services/observability

Those are Helm releases, and tolerations stay in their values files. A
post-renderer would not help there: kube-prometheus-stack's Prometheus is a
`Prometheus` CR whose StatefulSet the operator creates at runtime, so it never
passes through the rendered output at all.
