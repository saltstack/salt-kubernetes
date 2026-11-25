# Kubernetes Compliance Guide

Walkthrough for running CIS Kubernetes Benchmark assessments through a Salt
master and a Salt minion deployed into Kubernetes, using the `salt-master` and
`salt-minion` charts and kube-bench.

1. [Build the images](#1-build-the-images)
2. [Install the charts](#2-install-the-charts)
3. [Run an assessment](#3-run-an-assessment)

> **Scope and status.** The master and minion parts (steps 1 and 2) match the
> charts in this repository. The kube-bench pieces are not part of this
> repository: the minion chart here no longer renders any kube-bench resources
> or pillar, and `kube_bench_cache` comes from `saltext.kubernetes` (pinned in
> `src/minion/kubernetes/salt-extensions.txt`) and the separate
> `salt-k8s-compliance` repository. Steps 2c and 3 are carried over from earlier
> revisions of this guide and **were not re-verified** against the current
> charts; check them against those projects before relying on them.

## Prerequisites

- Docker to build the images, or use published images (see
  [`releasing.md`](releasing.md)).
- Helm 3 and `kubectl` for the target cluster.
- A registry, or another way to get images onto your nodes (see
  [`building.md`](building.md)).

## 1. Build the images

```bash
docker build -t salt-master:3008.5 src/master
docker build -t salt-minion:0.1.0 src/minion/kubernetes
```

`SALT_VERSION` (default `3008.5`) pins a different Salt version for either image:
`--build-arg SALT_VERSION=...`. The minion image preloads `saltext.kubernetes`
and `saltext.vault` (versions in `src/minion/kubernetes/salt-extensions.txt`) and
bundles `kubectl`. Behind a restricted network, route extension installs through
a mirror with `PIP_INDEX_URL`, `PIP_TRUSTED_HOST` and `PIP_ONLY_BINARY`. The full
argument list is in [`building.md`](building.md).

Get the images onto the cluster with a registry (`<registry>/<project>/<image>`,
see [`helm-test.md`](helm-test.md)) or by importing them into every node's
containerd store with `pullPolicy: Never`.

## 2. Install the charts

### 2a. salt-master

```bash
helm dependency update helm/salt-master
helm install salt-master helm/salt-master \
  --namespace salt-master --create-namespace \
  -f my-master-values.yaml
```

Key values (full list in [`helm/salt-master/values.yaml`](../helm/salt-master/values.yaml)):

| Value | Purpose |
| --- | --- |
| `agent.image.repository` / `agent.image.tag` | The master image from step 1 (default `salt-master:3008.5`). |
| `agent.autoAccept` | `true` skips manual acceptance (dev and test only). |
| `agent.trustedMinions.enabled` | Default `true`: minions are accepted with `SaltMinionKey` objects (the operator is installed as a subchart); `salt-key -a` does not stick. Set `false` to use `salt-key`. |
| `agent.jobCache.persistence.enabled` | Persist the job cache across pod replacement. Master keys are not stored on a volume: they live in a Secret. |
| `service.type`, `service.nodePorts.publish`, `service.nodePorts.ret` | `ClusterIP` (default) for minions inside the cluster; `NodePort` (defaults 30505 and 30506) for minions outside the pod network. |

Check the master:

```bash
kubectl -n salt-master get pods -l app=salt-master
kubectl -n salt-master exec salt-master-0 -c salt-master -- salt-key -L
```

### 2b. salt-minion

```bash
helm install salt-minion helm/salt-minion \
  --namespace salt --create-namespace \
  -f my-minion-values.yaml
```

Key values (full list in [`helm/salt-minion/values.yaml`](../helm/salt-minion/values.yaml)):

| Value | Purpose |
| --- | --- |
| `agent.image.repository` / `agent.image.tag` | The minion image from step 1 (default `ghcr.io/saltstack/salt-kubernetes/salt-minion:0.1.0`). |
| `agent.saltMasterHost` | Master address: `salt-master.salt-master.svc.cluster.local` from inside the cluster, or a node IP with `NodePort`. |
| `agent.saltMasterPort`, `agent.saltPublishPort` | Default 4506 and 4505. With a `NodePort` master set both to the NodePort values (30506 and 30505 by default); they must change together. |
| One of `agent.minion.keySecretName`, `agent.minion.privateKeyB64` with `publicKeyB64`, `agent.minion.allowSelfGeneratedKey` | Required key source. The minion's keypair is kept in a Secret, so it survives pod restarts. |
| `agent.replicas`, `agent.minion.idPrefix` | One StatefulSet pod per minion, each with its own ID (the pod name) and keypair. |
| `rbac.fullAccess` | Default `true` gives the minion cluster-admin rights. Set `false` and supply `rbac.customRoleRules`/`customClusterRoleRules` to restrict. |
| `namespace` | Namespace of every chart resource (default `salt`). |

Accept the minion (the minion ID is the pod name, `salt-minion-0` for one replica):

```bash
# trustedMinions disabled on the master:
kubectl -n salt-master exec salt-master-0 -c salt-master -- salt-key -a salt-minion-0 -y
# default (operator): create a SaltMinionKey, see src/salt-key-operator/README.md
kubectl -n salt-master exec salt-master-0 -c salt-master -- salt salt-minion-0 test.ping
```

`test.ping` returning `True` confirms both ports work.

### 2c. kube-bench (external, not re-verified)

An earlier version of this guide installed a `kube-bench-job` chart from the
[`salt-k8s-compliance`](https://github.com/saltstack/salt-k8s-compliance)
repository: a suspended CronJob used as a pod template for on-demand Jobs. Treat
it as a reference, not a drop-in install. Review its `values.yaml` first: host
mount paths (`nodeMounts.*`) differ between distributions, and a wrong path
produces false FAIL results rather than an error. Its namespace must match the
namespace the minion's ServiceAccount can reach (the minion chart's `namespace`,
default `salt`), and the CronJob name must match whatever `kube_bench_cache` is
configured to look for. The current minion chart has no `kubeBench.*` or
`pillar.*` values; provide the `kube_bench` pillar yourself, for example from
the master's `pillar_roots`.

## 3. Run an assessment

Not re-verified; the module is provided by `saltext.kubernetes`. From the master:

```bash
kubectl -n salt-master exec salt-master-0 -c salt-master -- \
  salt 'salt-minion-0' kube_bench_cache.run_assessment

kubectl -n salt-master exec salt-master-0 -c salt-master -- \
  salt 'salt-minion-0' kube_bench_cache.status_for_check test_number=1.1.11
```

`run_assessment` forces a fresh run; `status_for_check` returns the aggregated
status of one CIS control, collecting a new assessment first when the cache is
stale. kube-bench runs the full check set on every node, so the status is the
worst result across nodes with per-node detail in `comment`. The cache TTL, the
Job namespace and similar options come from the `kube_bench` pillar.
