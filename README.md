# salt-kubernetes

Container images and Helm charts for running Salt on Kubernetes: a Salt master,
Salt minions that run as pods, and an operator that manages the master's
accepted minion keys declaratively.

Salt version: **3008.5** (pinned in the Dockerfiles, `helm/salt-master/values.yaml`
and `scripts/ci.sh`). The images install Salt with the official
[bootstrap script](https://github.com/saltstack/salt-bootstrap) (onedir).
Each component's `CHANGELOG.md` records which Salt and extension versions a
given release carries.

## Repository layout

| Path | Contents |
| --- | --- |
| `helm/salt-master` | Chart: Salt master as a StatefulSet (classic or cluster mode). |
| `helm/salt-minion` | Chart: Salt minion as a StatefulSet (one minion and one keypair per pod), plus RBAC. |
| `helm/salt-key-operator` | Chart: the `SaltMinionKey` CRD and its controller. Also a dependency of the master chart. |
| `src/master` | Dockerfile and entrypoint for the master image. |
| `src/minion/kubernetes` | Minion image with `saltext.kubernetes`, `saltext.vault` and `kubectl`. |
| `src/minion/vcf` | Minion image with the VCF extensions (configurable extension list) and `saltext.vault`. |
| `src/salt-key-operator` | Go source of the operator. |
| `docs/` | Build, release, test and CI guides (see below). |
| `scripts/` | Release tag helpers and CI/e2e helper scripts. |

There is no Helm chart for the VCF minion image. Use the `salt-minion` chart
and point `agent.image.repository` at the VCF image.

## Components

| Chart | Image | What it does | Details |
| --- | --- | --- | --- |
| `salt-master` | `salt-master` | StatefulSet `salt-master` plus a flat Service and a headless Service. | [chart README](helm/salt-master/README.md), [image README](src/master/README.md) |
| `salt-minion` | `salt-minion` (from `src/minion/kubernetes`) or `salt-minion-vcf` | StatefulSet of minions, RBAC, key generation Job. `authMode: external` creates RBAC only. | [chart README](helm/salt-minion/README.md), [image README](src/minion/README.md) |
| `salt-key-operator` | `salt-key-operator` | Writes `SaltMinionKey` public keys into the master's trusted-minions ConfigMap. | [README](src/salt-key-operator/README.md) |

### Master modes

`agent.cluster.enabled` selects the mode (see the
[master chart README](helm/salt-master/README.md) for all values):

- **Classic** (default, `false`): one replica, or classic multi-master
  (`agent.replicas > 1`) where every replica shares one keypair supplied in
  `agent.masterKeySecretName` (required; the chart refuses to render
  otherwise). Minions list each master through the headless Service
  (`salt-master-<N>.salt-master-headless.<namespace>.svc.cluster.local`).
- **Cluster** (`true`): a Salt master cluster (Salt 3007+, isolated storage
  needs 3008+). Needs `agent.replicas >= 2` (use 3 or more). Each master has
  its own keypair, minions connect to the flat `salt-master` Service, and any
  replica can serve any minion. Opt-in. **Known limitation:** a restarted or
  rescheduled master pod cannot rejoin the cluster, so treat pod restarts as
  unsupported for now (see the master chart README).

The master is a StatefulSet. A release installed from an older chart version
that used a Deployment cannot be upgraded in place: reinstall.

### Minion model

The minion chart runs a StatefulSet named `agent.minion.idPrefix` (default
`salt-minion`). Pods are `<name>-0 ... <name>-N-1` and each pod is its own
minion: the minion ID is the pod name and each pod has its own keypair.
`agent.minion.id` and the single inline `privateKeyB64`/`publicKeyB64` pair
only work with `agent.replicas: 1`. One key source is required in `in_cluster`
mode: `agent.minion.keySecretName`, inline keys, or
`agent.minion.allowSelfGeneratedKey` (a keygen Job that writes Secret
`<release>-keys`; it only runs when `agent.minion.keySecretName` is empty). See the
[minion chart README](helm/salt-minion/README.md).

### Minion acceptance

The master chart installs `salt-key-operator` as a subchart when
`agent.trustedMinions.enabled` is true (the default), and a sidecar in each
master pod copies the trusted-minions ConfigMap into Salt's key directory.
Keys that are not in the ConfigMap are removed from that directory, so with
this enabled you accept minions with a `SaltMinionKey` (one per minion,
i.e. one per minion pod), not with `salt-key -a`. Set
`agent.trustedMinions.enabled=false` to accept with `salt-key` instead. See
[`src/salt-key-operator/README.md`](src/salt-key-operator/README.md).

## Quick start (from a checkout)

The charts default to locally built images, so build them first (see
[`docs/building.md`](docs/building.md)) and make them available to your
nodes, or override the image values.

```bash
# Images
docker build -t salt-master:3008.5 src/master
docker build -t salt-minion:0.1.0 src/minion/kubernetes
docker build -t salt-key-operator:0.1.0 src/salt-key-operator

# Master (also installs the salt-key-operator subchart; the operator image
# defaults to ghcr.io/saltstack/salt-key-operator:0.1.0, override
# with --set salt-key-operator.image.repository=... if you built your own)
helm dependency update helm/salt-master
helm install salt-master helm/salt-master \
  --namespace salt-master --create-namespace

# Minion
helm install salt-minion helm/salt-minion \
  --namespace salt --create-namespace \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.minion.allowSelfGeneratedKey=true
```

The minion chart's default image is
`ghcr.io/saltstack/salt-minion:0.1.0`; set
`agent.image.repository`/`agent.image.tag` to use the image you built. The
master chart's default is the unqualified `salt-master:3008.5`.

Then trust the minion (the key Secret is `<release>-keys`):

```bash
kubectl -n salt get secret salt-minion-keys -o jsonpath='{.data.minion\.pub}' | base64 -d
# put that PEM into a SaltMinionKey named salt-minion-0 in namespace salt-master,
# see src/salt-key-operator/README.md
kubectl -n salt-master exec salt-master-0 -c salt-master -- salt 'salt-minion-0' test.ping
```

[`docs/complete-system-test.md`](docs/complete-system-test.md) has the full
step-by-step version including the operator, multi-master and cluster mode.

## Published artifacts

Release workflows publish to GHCR on component tags (see
[`docs/releasing.md`](docs/releasing.md) for tag patterns and exact paths).
Which versions exist depends on which tags have been pushed.

## Testing

Pull requests to `main` run `.github/workflows/ci-cd-pr.yml`:

- hadolint on every Dockerfile under `src/`
- `helm unittest` on the three charts (only `helm/salt-minion` has test
  suites, in `helm/salt-minion/tests`)
- `helm lint` on the three charts
- `go fmt` and `go vet` for the operator
- builds of all four images (nothing is pushed) and Trivy scans in log-only
  mode (vulnerabilities do not fail the build)
- `helm package` of the three charts

The same workflow without the unit tests runs again after merge
(`post-merge.yml`). To run the chart unit tests locally:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest helm/salt-minion
```

There are no unit tests for the master or key operator charts and no Go unit
tests run in CI (`go test` is not part of the workflow). The cluster-level
test procedure is in [`docs/complete-system-test.md`](docs/complete-system-test.md).

## Documentation

- [`docs/building.md`](docs/building.md): build images and charts from source
- [`docs/releasing.md`](docs/releasing.md), [`docs/release-prep.md`](docs/release-prep.md): publishing
- [`docs/helm-test.md`](docs/helm-test.md): try a chart on a real cluster with a private registry
- [`docs/complete-system-test.md`](docs/complete-system-test.md): end-to-end test of all components
- [`docs/kubernetes-compliance-guide.md`](docs/kubernetes-compliance-guide.md): CIS assessment workflow
- [`docs/ci-debug.md`](docs/ci-debug.md): reproduce CI failures locally

## License

See [`LICENSE`](LICENSE).
