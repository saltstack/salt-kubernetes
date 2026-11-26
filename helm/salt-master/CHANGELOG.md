# Changelog (salt-master chart)

Records what each chart release defaults to (release tag `chart-salt-master-vX.Y.Z`, see
[`docs/releasing.md`](../../docs/releasing.md); the headings below use the older
`salt-master-chart/vX.Y.Z` form). The chart's own version is independent
of the image version it happens to default to — check here, not the tag number.

## salt-master-chart/v1.1.0
**Breaking - requires a fresh install, not `helm upgrade`, from v1.0.0 or earlier:**
- `kind: Deployment` -> `kind: StatefulSet` (`templates/deployment.yaml` and the standalone
  `templates/job-cache-pvc.yaml` removed, replaced by `templates/statefulset.yaml`). Kubernetes
  cannot reconcile a Deployment-owned release into a StatefulSet of the same name in place. The
  job cache is now a per-replica `volumeClaimTemplate` (`agent.jobCache.persistence.*`, off by
  default), mounted at `/var/cache/salt/master/jobs` in classic mode.
- New `agent.replicas` (default `1`). `agent.replicas > 1` without cluster mode is classic
  multi-master: it requires `agent.masterKeySecretName` (the chart fails to render otherwise)
  because every replica must share one keypair, and minions list each replica through the
  headless Service's per-pod DNS names. Pods start in parallel (`podManagementPolicy: Parallel`).
- Default image tag `3008.2` -> `3008.5`.
- The init containers no longer run as root or add capabilities. `prepare-master-keys` (classic)
  and `prepare-cluster-dirs` (cluster) run with `agent.containerSecurityContext`, create their
  directories as the master's own user (the pod's `fsGroup` makes the volumes group-writable)
  and the master mounts those existing subdirectories - the same pattern as the salt-minion
  chart. The Secret with the master keys is mounted `0440`. The `agent.initContainers.fixCachePerms`
  value (a root init container) is removed. A volume you supply yourself
  (`sharedStorage.existingClaim`) must already be writable by uid/gid 10001.

**New: Salt master cluster mode (opt-in, `agent.cluster.enabled`, default `false`):**
- New `agent.cluster.*` values: `enabled`, `id` (default the release name), `clusterDomain`,
  `poolPort` (`cluster_pool_port`, default `4520`, also added to the headless Service),
  `secretName`, `storageMode`, `persistence.{storageClassName,accessMode,size}`,
  `sharedStorage.existingClaim`, `keysCacheDriver`, `autoReplaceVoters` (default `false`) and
  `minVoters` (default replicas - 1, at least 1). New `templates/cluster-secret.yaml`: a random
  `cluster_secret` Secret `<release>-cluster-secret`, generated once and kept across upgrades
  (`helm.sh/resource-policy: keep`) unless `agent.cluster.secretName` is set.
- `agent.cluster.storageMode` is `isolated` (default; Salt 3008 `cluster_isolated_filesystem`, one
  PVC per pod, no shared storage; `file_roots`/`pillar_roots` changes need
  `salt-run cluster.sync_roots`) or `shared` (one existing ReadWriteMany claim for
  pki/cache/file_roots/pillar_roots; `sharedStorage.existingClaim` required).
- In cluster mode each master keeps its own keypair on its own PVC, so `agent.masterKeySecretName`
  and the master-keygen Job are not used, and `trustedMinions` writes into `cluster_pki_dir`
  (`/etc/salt/pki/cluster`). The chart fails to render when `agent.replicas < 2`.
- Found by testing on a real cluster: Salt refuses a member with no peers, so cluster mode needs
  `agent.replicas >= 2` (use 3 or more); each master's `interface` and `id` must be its own pod IP
  (Salt uses `interface` as the consensus node identity); `keysCacheDriver` is empty because
  `mmap_key` could not read its own keys back on Longhorn volumes (Salt's default `localfs_key`
  is used).
- Tested: 3 replicas with isolated storage. Not tested: shared storage, minions connecting
  through the cluster, node failure.
- **Known limitation:** the pod IP is the cluster identity, so a restarted or rescheduled master
  joins as a new learner while its old identity stays a dead voter; quorum is lost after the
  second restart and a 2-replica cluster cannot recover from any single failure.
  `cluster_auto_replace_voters` is left off because it was seen to demote a healthy voter.
  Treat pod restarts in cluster mode as unsupported until the node identity can be made stable.
- New `agent.image.imagePullSecrets` for pulling the master image from a private registry, and a
  `keygen` block for the one-time master-key Job: `keygen.image.repository`/`tag`/`pullPolicy`/
  `imagePullSecrets` (defaults unchanged, `bitnami/kubectl:latest`) and restricted
  `keygen.podSecurityContext`/`keygen.containerSecurityContext` (non-root, `RuntimeDefault` seccomp,
  no privilege escalation, all capabilities dropped). The Job image used to be hardcoded and the
  Job had no security context. Checked on a real cluster: the Job completes and creates the Secret.
- Requires master image `salt-master-image/v1.1.0` or later (the cluster configuration is rendered
  by the image's `entrypoint.sh`). `Chart.yaml` `appVersion` is not updated to track the image.

## salt-master-chart/v1.0.0
Correction: the earlier text of this entry described a StatefulSet, `service.perOrdinal.*`
Services and an `agent.replicas` value. None of those are in the templates of this
chart version, which still rendered a `Deployment`; the StatefulSet arrived in v1.1.0 above, and
the chart has no per-ordinal Services at all (use the headless Service's per-pod DNS names, or the
flat Service). What v1.0.0 does carry:
- New `templates/service-headless.yaml` (`clusterIP: None`). The flat `templates/service.yaml`'s
  default `service.type` changed `NodePort` -> `ClusterIP` (standard practice - nothing exposed
  outside the cluster unless explicitly configured).
- New `service.gateway.*` (default `enabled: false`): generates Gateway API `TCPRoute` objects
  (raw TCP passthrough, e.g. via Envoy Gateway) for external access instead of
  NodePort/LoadBalancer - a standard Kubernetes `Ingress` cannot do this at all (HTTP(S)-only;
  Salt's ports are raw ZeroMQ). New `templates/gateway-tcproute.yaml`.
- `agent.persistence.*` (PKI persistence) removed - the master's identity comes from the Secret
  named by `agent.masterKeySecretName` (keys `master.pem`/`master.pub`; or the keygen Job's
  `<release>-master-keys`). Replaced by `agent.jobCache.persistence.*` for the job/event cache
  only (`/var/cache/salt/master/jobs`).
- New `agent.trustedMinions.*` (default `enabled: true`): delegates minion acceptance
  to `salt-key-operator` entirely. New `templates/configmap.yaml` creates a ConfigMap
  (rendered with no `data:` key, so `helm upgrade` never stomps the operator's
  out-of-band writes to it) that a new `trusted-minions-sync` sidecar container
  continuously copies into the writable directory Salt actually reads. **Not** a
  direct ConfigMap volume mount onto `/etc/salt/pki/master/minions` - confirmed by
  live testing that Kubernetes always mounts ConfigMap volumes as symlinks, and
  Salt 3008's `localfs_key` cache driver explicitly rejects symlinks in every key
  read path as a PKI-tampering hardening measure. `cp` dereferences a symlink
  source by default, which is what makes the sidecar's copy actually work. Once
  enabled, `salt-key -a` no longer sticks (the sidecar removes keys that are not in the
  ConfigMap) - that's intentional, see `values.yaml`'s comment.

## salt-master-chart/v0.1.0
- Default image: `salt-master:1.0.0` (`appVersion` in `Chart.yaml`) — see
  [`../../src/master/CHANGELOG.md`](../../src/master/CHANGELOG.md) for what that image
  version carries. Chart default `agent.image.repository` is still the unqualified local name
  `salt-master` (see `values.yaml`), not this published tag.
