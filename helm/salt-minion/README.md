# salt-minion

Installs Salt minions into a Kubernetes cluster as a StatefulSet, with RBAC, health
probes, and optional Vault and Kubernetes (`saltext.kubernetes`) integration. The
minions can also run kube-bench based CIS compliance assessments (see
[Kubernetes compliance guide](../../docs/kubernetes-compliance-guide.md)).

Features:
- In-cluster (StatefulSet) or external (RBAC only) deployment modes
- One minion per pod: the pod name is the minion ID, and every pod has its own keypair
- Three ways to supply minion keys: an existing Secret, inline values, or a key
  generation Job
- Liveness and readiness probes
- Vault integration (`saltext.vault`)
- Salt multi-master connectivity (a list of masters)
- Security hardened (non-root, no privilege escalation, no added capabilities)

The image builds a self-contained Salt minion (core Salt plus `saltext.vault` and
`saltext.kubernetes`) with `kubectl` bundled in. Build it from the repository root:

```bash
docker build -t salt-minion:local ./src/minion/kubernetes
```

See [`src/minion/README.md`](../../src/minion/README.md) for build arguments and
[`CHANGELOG.md`](CHANGELOG.md) for which Salt and extension versions each image
release carries. The default `agent.image.tag` is an image release tag (`0.2.0`), not a
Salt version.

## Deployment Modes

Selected via `agent.authMode`:

- **in_cluster** (default): the Salt minion runs as a StatefulSet inside the cluster.
  - Chart creates the StatefulSet and RBAC (ServiceAccount, Role, ClusterRole, bindings)
  - Each minion connects to the Salt master on the configured ports
  - Liveness and readiness probes restart or hold back unhealthy pods
  - A key source is required (see [Key Management](#key-management))
- **external**: RBAC only, for a minion that runs outside the cluster.
  - ServiceAccount (and its RBAC) is created; use its token for an external kubeconfig
  - No StatefulSet, key Secret, or key generation Job is created
  - The minion runs via salt-ssh or standalone

## Prerequisites

- Kubernetes 1.24+
- Helm 3+
- A Salt master reachable from the minion pods (required for in_cluster mode)
- For in_cluster mode, a key source: `agent.minion.keySecretName`, or both
  `agent.minion.privateKeyB64` and `agent.minion.publicKeyB64`, or
  `agent.minion.allowSelfGeneratedKey: true`. Without one the install fails with
  `set agent.minion.keySecretName or both agent.minion.privateKeyB64 and
  agent.minion.publicKeyB64, or enable agent.minion.allowSelfGeneratedKey`.

The chart creates every namespaced object in `namespace` (default `salt`), not in
the namespace given to `helm --namespace`. Pass both consistently, as the examples do
(`--namespace salt` with the default `namespace: salt`), or set `--set namespace=<ns>`
to match.

## Quick Start

### In-Cluster Minion

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.minion.allowSelfGeneratedKey=true
```

This creates a StatefulSet named `salt-minion` with one pod, `salt-minion-0`. The
minion ID is the pod name, `salt-minion-0`. The key generation Job creates the keys
in Secret `<release>-keys` (here `salt-minion-keys`). The public key then has to be
accepted on the master (see [Verification](#verification)).

### External Minion (RBAC only)

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.authMode=external

# Token for the external minion's kubeconfig
kubectl create token salt-minion -n salt
```

## Installation

### With Vault Integration

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.minion.allowSelfGeneratedKey=true \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.vault.addr=https://vault.example.com:8200 \
  --set agent.vault.roleId=my-role-id
```

### Multiple Masters

`agent.saltMasterHost` also accepts a list, which gives every minion one independent,
simultaneous connection to each master (Salt's native multi-master mode, not
failover):

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.minion.allowSelfGeneratedKey=true \
  --set 'agent.saltMasterHost={master-0.example.com,master-1.example.com}'
```

The chart joins the list with commas into `SALT_MASTER`, and the image entrypoint
turns that into a YAML list in the minion configuration. Every master in the list has
to accept every minion key.

Do not use this for a Salt master *cluster* (`agent.cluster.enabled` in the
[salt-master chart](../salt-master/README.md)). A master cluster presents one
logical master: point `agent.saltMasterHost` at its single `salt-master` Service. A
list is for independent masters, such as the classic multi-master mode of the
salt-master chart, where each replica is addressed through the headless Service
(`<master-pod>.<headless-service>.<namespace>.svc.cluster.local`).

### Using a Values File

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  -f my-values.yaml
```

## Verification

### Check the StatefulSet

```bash
# Watch pod initialization
kubectl rollout status statefulset/salt-minion -n salt

# List the pods (named <idPrefix>-0, <idPrefix>-1, ...)
kubectl get pod -n salt -l app=salt-minion

# Probe status
kubectl describe pod -n salt -l app=salt-minion | grep -A 5 Probe
```

Use the `agent.minion.idPrefix` value instead of `salt-minion` in the StatefulSet and
pod names if you set it.

### Verify the Master Connection

Substitute the master's namespace and pod name. The commands below assume the
salt-master chart's default StatefulSet `salt-master` in namespace `salt-master`:

```bash
# List pending keys
kubectl exec -n salt-master salt-master-0 -c salt-master -- salt-key -L

# Accept a minion (when not using salt-key-operator or auto-accept)
kubectl exec -n salt-master salt-master-0 -c salt-master -- salt-key -a salt-minion-0 -y
```

If the master delegates acceptance to `salt-key-operator`
(`agent.trustedMinions.enabled`), `salt-key -a` does not apply; create a
`SaltMinionKey` instead (see [Accepting the keys on the master](#accepting-the-keys-on-the-master)).

### Test Minion Connectivity

```bash
# From the master
kubectl exec -n salt-master salt-master-0 -c salt-master -- salt 'salt-minion-0' test.ping

# From the minion (local test, does not use the master)
kubectl exec -n salt salt-minion-0 -- salt-call --local test.ping
```

## Uninstalling

```bash
helm uninstall salt-minion -n salt
```

The key Secret generated by the key generation Job is not owned by Helm, so it is
left behind. Delete it if you do not want to reuse the keys:

```bash
kubectl delete secret salt-minion-keys -n salt
```

## Configuration

See [values.yaml](values.yaml) for the complete list of configuration options.

### Key Configuration Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `namespace` | Namespace of every namespaced object the chart creates | `salt` |
| `agent.authMode` | `in_cluster` or `external` | `in_cluster` |
| `agent.replicas` | Number of minion pods. Each pod is a separate minion with its own ID and keypair (see [Multiple replicas](#multiple-replicas)) | `1` |
| `agent.minion.id` | Explicit minion ID. Empty uses the pod name. Only allowed with `agent.replicas: 1` | `""` |
| `agent.minion.idPrefix` | Names the StatefulSet; pod `N` is `<idPrefix>-N` and that is its minion ID. Empty uses `salt-minion` | `""` |
| `agent.minion.keySecretName` | Existing Secret that holds the keys (see [Key Management](#key-management)). Empty uses `<release-name>-keys` | `""` |
| `agent.minion.privateKeyB64` | Base64-encoded private PEM key; requires `publicKeyB64`; one replica only | `""` |
| `agent.minion.publicKeyB64` | Base64-encoded public PEM key; requires `privateKeyB64`; one replica only | `""` |
| `agent.minion.allowSelfGeneratedKey` | Let the key generation Job create the keys. The Job only runs when `keySecretName`, `privateKeyB64` and `publicKeyB64` are all empty | `false` |
| `agent.minion.masterPubKeyB64` | Base64-encoded master public key, passed as `SALT_MASTER_PUBKEY_B64` so the minion trusts the master directly | `""` |
| `agent.podSecurityContext` | Pod security context; `fsGroup` gives the containers access to the key Secret and the PKI volume | `{"fsGroup": 10001, "runAsNonRoot": true}` |
| `agent.containerSecurityContext` | Security context shared by the minion and the `prepare-minion-keys` init container | `{"allowPrivilegeEscalation": false, "runAsNonRoot": true, "capabilities": {"drop": ["ALL"]}}` |
| `agent.image.repository` | Minion image repository | `ghcr.io/saltstack/salt-minion` |
| `agent.image.tag` | Minion image tag | `0.2.0` |
| `agent.image.pullPolicy` | Minion image pull policy | `IfNotPresent` |
| `agent.image.imagePullSecrets` | Pull Secrets for the minion pods | `[]` |
| `keygen.image.repository` | Key generation image (needs `kubectl` and `openssl`) | `bitnami/kubectl` |
| `keygen.image.tag` | Key generation image tag | `latest` |
| `keygen.image.pullPolicy` | Key generation image pull policy | `Always` |
| `keygen.image.imagePullSecrets` | Pull Secrets for the key generation Job | `[]` |
| `keygen.podSecurityContext` | Pod security context of the key generation Job | `runAsNonRoot: true`, `seccompProfile: RuntimeDefault` |
| `keygen.containerSecurityContext` | Container security context of the key generation Job | no privilege escalation, all capabilities dropped |
| `agent.saltMasterHost` | Salt master hostname, or a list of masters (REQUIRED in in_cluster mode) | `""` |
| `agent.saltMasterPort` | Master request/return port (`master_port`) | `4506` |
| `agent.saltPublishPort` | Master publish port (`publish_port`) | `4505` |
| `agent.authTimeout`, `agent.masterAliveInterval`, `agent.reconDefault`, `agent.reconMax`, `agent.reconRandomize` | Minion connection and reconnect tuning (see comments in values.yaml) | `60`, `60`, `1000`, `5000`, `true` |
| `agent.logLevel` | Minion log level | `info` |
| `agent.vault.*` | Vault settings; `agent.vault.addr` enables `saltext.vault` | `""` |
| `agent.nodeSelector` | Node selector for the minion pods | `{}` |
| `rbac.create` | Create RBAC resources | `true` |
| `rbac.fullAccess` | Grant the minion cluster-admin-equivalent rights (`*` on `*`, in the namespace and cluster wide) | `true` |
| `serviceAccount.name` | ServiceAccount name | `salt-minion` |

The chart has no persistence settings. The minion's PKI directory is an `emptyDir`,
and the keys always come from a Secret (see below).

### Pod identity

Each pod of the StatefulSet is its own minion. The minion ID is the pod name, taken
from `POD_NAME` by the image entrypoint:

| Settings | StatefulSet | Minion IDs |
| --- | --- | --- |
| defaults | `salt-minion` | `salt-minion-0` |
| `agent.minion.idPrefix=edge`, `agent.replicas=3` | `edge` | `edge-0`, `edge-1`, `edge-2` |
| `agent.minion.id=web`, `agent.replicas=1` | `salt-minion` | `web` (overrides the pod name) |

Note that a default single-replica install registers as `salt-minion-0`. The
StatefulSet does not need a Service; minions only connect outward to the master.

### Key storage

Every pod has an `emptyDir` PKI volume at `/pki`. When the pod starts, the
`prepare-minion-keys` init container copies the pod's keys from the key Secret into
`/pki/minion` (through a temporary directory, then an atomic `mv`), and the minion
container mounts that directory at `/etc/salt/pki/minion`. The copy runs on every pod
start, so the Secret is the source of truth and a rescheduled pod keeps its identity.

### Vault Integration

```yaml
agent:
  vault:
    addr: https://vault.example.com:8200
    authMethod: approle
    roleId: my-role-id
    secretId: my-secret-id  # or secretIdFile (a path to a mounted file)
    sdbProfile: vault_sdb
```

Then reference secrets in pillar:

```sls
credentials:
  api_key: sdb://vault_sdb/secret/data/api:key
```

The chart has no value for mounting a Secret into the pod, so `secretIdFile` and
`tokenFile` only help if the file is provided some other way. `secretId` and `token`
are plain pod environment variables, visible in `kubectl get pod -o yaml`.

### Key Management

The init container and the minion use the same image and container security context
(uid/gid `10001`, no privilege escalation, all capabilities dropped). The pod
`fsGroup` and the Secret volume mode `0440` let the non-root init container read the
key Secret. Inside the pod the private key ends up with mode `0400` and the public
key with `0644`.

There are three key sources. One is required in in_cluster mode.

| Source | Settings | Secret | Replicas |
| --- | --- | --- | --- |
| Existing Secret | `agent.minion.keySecretName` | You create it | any |
| Inline keys | `privateKeyB64` + `publicKeyB64` | Chart creates `keySecretName`, or `<release>-keys` when that is empty | 1 only |
| Key generation Job | `allowSelfGeneratedKey: true` (and no `keySecretName`) | Job creates `<release>-keys` | any |

Secret layout:

- One replica: keys `minion.pem` and `minion.pub`, both containing PEM text.
- More than one replica: one pair per pod, `<pod-name>.pem` and `<pod-name>.pub`
  (for example `edge-0.pem`, `edge-0.pub`). Each pod mounts only its own pair; the
  Secret volume uses `items` and `subPathExpr: $(POD_NAME)` for that. The Secret has
  to contain a pair for every pod from `0` to `replicas-1`; if a pair is missing, the
  pods cannot mount the volume and stay in `ContainerCreating`.

Inline keys: Helm creates the Secret. The install fails if an unmanaged Secret with
that name already exists. To use an existing Secret, set `keySecretName` and no
inline keys. `privateKeyB64` and `publicKeyB64` must be set together.

The key generation Job only runs when `allowSelfGeneratedKey` is `true` and
`keySecretName`, `privateKeyB64` and `publicKeyB64` are all empty. If you set
`keySecretName` as well, no Job is created and the Secret must already exist.

#### Pre-seeded keys (one replica)

```bash
kubectl create secret generic my-minion-keys \
  --from-file=minion.pem=/path/to/minion.pem \
  --from-file=minion.pub=/path/to/minion.pub \
  -n salt

helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.minion.keySecretName=my-minion-keys
```

#### Auto-generated keys

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.minion.allowSelfGeneratedKey=true
```

The Job is an ordinary Job, not a Helm hook. It starts together with the
StatefulSet; the pods wait in `ContainerCreating` until the Secret exists. It uses the
ServiceAccount `salt-minion`, bound to a Role (`<release>-minion-keygen-role`) that
can `create`, `get`, `list` and `patch` Secrets in the namespace
(`rbac.create: false` skips the Role and RoleBinding, and then you must provide
equivalent rights).

With one replica the Job creates Secret `<release>-keys` with `minion.pem` and
`minion.pub`, and does nothing if the Secret already exists.

### Multiple replicas

Every replica is a separate minion with its own ID (the pod name) and its own keypair.
Set `agent.minion.idPrefix` to choose the names:

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.replicas=3 \
  --set agent.minion.idPrefix=external-minion \
  --set agent.minion.allowSelfGeneratedKey=true
# minions: external-minion-0, external-minion-1, external-minion-2
```

Rules the chart enforces for `agent.replicas > 1`:

- `agent.minion.id` is rejected: `agent.minion.id cannot be used with agent.replicas > 1
  (every pod would register as the same minion); use agent.minion.idPrefix to get
  <prefix>-0, <prefix>-1, ...`
- `privateKeyB64`/`publicKeyB64` are rejected: `agent.minion.privateKeyB64/publicKeyB64
  hold a single keypair and cannot be used with agent.replicas > 1; set
  agent.minion.keySecretName to a Secret with per-pod keys, or enable
  agent.minion.allowSelfGeneratedKey`
- The StatefulSet uses `podManagementPolicy: Parallel`, so pods start and are replaced
  independently.

#### Generated per-pod keys

With `allowSelfGeneratedKey`, the key generation Job creates Secret `<release>-keys`
holding a pair per pod. The Job is named `<release>-keygen-<replicas>` (so a different
replica count is a new Job) and is idempotent:

- It reads the Secret's existing keys and never regenerates a pair that exists, because
  the master already trusts it.
- It creates the Secret if it does not exist, or adds only the missing pairs with
  `kubectl patch`.
- If nothing is missing it logs `All keys already exist; nothing to do` and exits.

Scale up (`helm upgrade --set agent.replicas=5`): the new `<release>-keygen-5` Job adds
the pairs for the new pods only. Existing pods keep their keys. The new minions have to
be accepted on the master. Pods that restart before the Job finishes wait in
`ContainerCreating` until the pairs exist.

Scale down: the extra pods are removed, but their key pairs stay in the Secret, and
their keys stay accepted on the master. Remove both if you do not want them
(edit the Secret to drop the `<pod>.pem`/`<pod>.pub` entries, and run
`salt-key -d <minion-id>` on the master or delete the `SaltMinionKey`). Scaling back up
later reuses a stored pair.

If you change from one replica to several, the existing Secret keeps `minion.pem` and
`minion.pub`, and the Job adds `<name>-0`, `<name>-1`, ... pairs. Pod 0 then uses a
new keypair (and, if you used `agent.minion.id`, a new ID), which must be accepted
again.

#### Your own per-pod keys

Create the Secret yourself with a pair for every pod and set `keySecretName`:

```bash
kubectl create secret generic my-minion-keys -n salt \
  --from-file=external-minion-0.pem=./0.pem --from-file=external-minion-0.pub=./0.pub \
  --from-file=external-minion-1.pem=./1.pem --from-file=external-minion-1.pub=./1.pub

helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.replicas=2 \
  --set agent.minion.idPrefix=external-minion \
  --set agent.minion.keySecretName=my-minion-keys
```

Add the pairs for new pods to the Secret before you raise `agent.replicas`. Key names
must be exactly `<idPrefix>-<ordinal>.pem` and `.pub`.

#### Accepting the keys on the master

The master has to accept the public key of every pod. With the
[salt-key-operator](../salt-key-operator/), create one `SaltMinionKey` per pod, in the
master's namespace, using the public key from the Secret:

```bash
for i in 0 1 2; do
  id="external-minion-$i"
  pub="$(kubectl get secret salt-minion-keys -n salt \
    -o go-template="{{index .data \"$id.pub\" | base64decode}}")"
  kubectl apply -f - <<EOF
apiVersion: salt.saltstack.io/v1alpha1
kind: SaltMinionKey
metadata:
  name: $id
  namespace: salt-master
spec:
  minionId: $id
  publicKey: |
$(printf '%s\n' "$pub" | sed 's/^/    /')
EOF
done
```

(`salt-minion-keys` is `<release>-keys` for a release named `salt-minion`.) Without
the operator, use `salt-key -a <pod-name>` on the master (see Verification), or enable
auto-accept on the master. With a pod's own key already trusted on the master, the
minion is accepted without any prompt, even if the pod is rescheduled.

### Health Checks

The minion container has both probes (not configurable through values):

| Probe | Initial delay | Period | Timeout | Failure threshold |
| --- | --- | --- | --- | --- |
| Liveness | 30s | 60s | 10s | 3 |
| Readiness | 15s | 30s | 10s | 3 |

Both run `salt-call --local test.ping`, which checks the local minion install, not
the connection to the master. Change the templates if you need other timings.

## Security Design

- Runs as non-root uid/gid `10001` (set by the image); `runAsNonRoot` is enforced
- `fsGroup: 10001`; the key Secret is mounted with mode `0440`
- The init container `prepare-minion-keys` runs with the same non-root container
  security context as the minion, with no added capabilities
- Privilege escalation disabled, all Linux capabilities dropped
- Keys are copied atomically into an `emptyDir`; private key mode `0400`, public key
  `0644`; Secret volumes are read-only
- Each pod mounts only its own key pair when `agent.replicas > 1`
- The image enables Salt FIPS mode (`SALT_FIPS_MODE=true`) by default; the chart has no
  value to turn it off
- RBAC: `rbac.fullAccess` defaults to `true`, which grants `*` on `*` through a Role
  and a ClusterRole. Set it to `false` and supply `rbac.customRoleRules` and
  `rbac.customClusterRoleRules` to restrict the minion
- Minion keys are not auto-accepted by the chart; acceptance happens on the master

## Upgrading

The Deployment from earlier releases was replaced by a StatefulSet, and a Deployment
cannot be converted to a StatefulSet in place. Uninstall and reinstall instead of
`helm upgrade`:

```bash
helm uninstall salt-minion -n salt
helm install salt-minion ./helm/salt-minion ...   # same values
```

Minion IDs change from the old random Deployment pod name (or `agent.minion.id`) to
`<idPrefix>-<ordinal>` unless you keep `agent.minion.id` with one replica. Delete the
old minion keys on the master and accept the new ones. An existing key Secret
(`<release>-keys` or your own) with `minion.pem`/`minion.pub` is reused for a
single-replica install and keeps its keypair.

## Troubleshooting

### Pods stay in ContainerCreating

```bash
kubectl describe pod -n salt salt-minion-0
```

Look for a missing Secret or Secret key. With `agent.replicas > 1` the key Secret must
hold `<pod>.pem` and `<pod>.pub` for every pod, and for the generated case the
key generation Job must have completed (`kubectl get job -n salt`).

### Pods stay in Pending

```bash
kubectl describe pod -n salt -l app=salt-minion
# Check: node selectors, resource availability, pull secrets
```

### Install fails at render time

The chart rejects: no key source in in_cluster mode, `privateKeyB64` without
`publicKeyB64` (or the reverse), `agent.minion.id` with several replicas, inline keys
with several replicas, and inline keys when an unmanaged Secret of that name already
exists. The error text names the setting to change.

### Minion not connecting to master

```bash
# Check master hostname resolution
kubectl exec -n salt salt-minion-0 -- nslookup salt-master.salt-master.svc.cluster.local

# Check connectivity
kubectl exec -n salt salt-minion-0 -- nc -zv salt-master.salt-master.svc.cluster.local 4506

# View minion logs
kubectl logs -n salt salt-minion-0
```

### Health check failing

```bash
kubectl exec -n salt salt-minion-0 -- salt-call --local test.ping
kubectl describe pod -n salt salt-minion-0 | grep -A 5 "Probe"
```

### Key not appearing on the master

```bash
# Verify the key Secret exists and holds the expected keys
kubectl describe secret salt-minion-keys -n salt

# Check the key generation Job
kubectl get job -n salt
kubectl logs job/salt-minion-keygen -n salt        # one replica
kubectl logs job/salt-minion-keygen-3 -n salt      # three replicas
```

The minion sends its public key to the master on first connect; it appears as a
pending key (`salt-key -L`) unless it has already been accepted or the master
auto-accepts.

## Running the chart tests

The chart has [helm-unittest](https://github.com/helm-unittest/helm-unittest) suites
in [`tests/`](tests/). The pull request CI workflow runs them. Locally:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.2.1
helm unittest helm/salt-minion
helm lint helm/salt-minion
```

## Related Documentation

- [Salt Minion Source](../../src/minion/README.md) - image documentation
- [Salt Master Chart](../salt-master/README.md) - master deployment
- [Salt Key Operator](../salt-key-operator/) - declarative key management
- [Complete System Test](../../docs/complete-system-test.md) - integration testing
- [Salt Documentation](https://docs.saltproject.io/) - official Salt resources
