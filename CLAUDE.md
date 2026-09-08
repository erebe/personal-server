# CLAUDE.md

Guidance for Claude Code when working in this repository.

**Read [AGENT.md](AGENT.md) first.** It is the single source of orientation for
this repo: what it is, how it is laid out, the machines it manages, the network
overlay, the Kubernetes cluster, secrets handling, and the conventions to
follow. Everything below is a pointer into it.

## The short version

This is infrastructure-as-code for a personal server estate (`erebe.eu`), not an
application. Ansible in `nodes/` for hosts, kustomize/Helm in `services/` and
`k8s/` for the k3s cluster, sops+GPG for secrets, `just` as the entry point in
each of the three directories.

## Things that will bite you if you skip AGENT.md

- **Ansible tasks are all `never`-tagged.** `just <node>` runs nothing; you must
  pass `--tags`.
- **`kubectl apply --prune --applyset`** is used for every service, so deleting
  a resource from a kustomization deletes it from the live cluster.
- **Every node is tainted** `kubernetes.io/hostname=<name>:NoSchedule`; a
  workload needs affinity *and* toleration.
- **`README.md` is a 2020-2023 blog post**, not current documentation.
- **No tests, no validating CI** — production is the only feedback loop. Dry-run
  first, and say clearly when something can't be verified without applying.
- **Comments explain the failure they prevent.** Match that density; a bare
  value with no rationale is a regression here.

## Secrets

Encrypted with sops under one GPG key. Never write plaintext secrets to tracked
files, never emit decrypted content anywhere it could leave the machine, and
edit with `sops`/`sops set` rather than decrypt-edit-reencrypt. Details in
AGENT.md.
