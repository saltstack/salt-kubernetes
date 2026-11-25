# Building From Source

Build from source when you need a patched or local image, a Salt version
other than the pinned one, or a build with no route to GHCR. For published
artifacts see [`releasing.md`](releasing.md).

## Prerequisites

- Docker with BuildKit (the default in current Docker). The Dockerfiles use
  `--mount=type=secret` and `TARGETARCH`, which need BuildKit.
- Helm 3 for the charts.

## Docker images

Each image builds with its own directory as the build context:

```bash
docker build -t salt-master:3008.5 src/master
docker build -t salt-minion:0.1.0 src/minion/kubernetes
docker build -t salt-minion-vcf:0.1.0 src/minion/vcf
docker build -t salt-key-operator:0.1.0 src/salt-key-operator
```

Image names and tags are your choice. The chart defaults are
`salt-master:3008.5` (master), `ghcr.io/saltstack/salt-kubernetes/salt-minion:0.1.0`
(minion) and `ghcr.io/saltstack/salt-kubernetes/salt-key-operator:0.1.0` (operator), so
override the image values when you use your own build (see below).

### Build arguments

| Argument | Images | Default | Purpose |
| --- | --- | --- | --- |
| `SALT_VERSION` | master, both minions | `3008.5` | Salt version. `latest` is also accepted. |
| `SALT_UID`, `SALT_GID` | both minions | `10001` | Numeric user and group of the non-root `salt` user. (The master image uses a fixed `10001:10001`.) |
| `INCLUDE_KUBECTL`, `KUBECTL_VERSION` | both minions | `true`, `v1.30.2` | Bundle `kubectl` (checksum verified). |
| `EXTRA_SALT_EXTENSIONS` | both minions | empty | Extra pip requirements, space separated, installed after `salt-extensions.txt`. |
| `PIP_INDEX_URL`, `PIP_TRUSTED_HOST`, `PIP_ONLY_BINARY` | both minions | empty | Install the Salt extensions through a PyPI mirror. |
| `APT_MIRROR` | both minions | empty | Alternative Ubuntu apt mirror. |
| `SALT_GPG_KEY_URL`, `SALT_APT_REPO_URL` | both minions | public Salt package repository | Override for restricted networks. |

Both minion Dockerfiles also have `SALT_HOME` and `SALT_SHELL`. Read the
Dockerfiles for the authoritative list. The master Dockerfile only takes
`SALT_VERSION`.

Extensions installed by default are listed in
`src/minion/kubernetes/salt-extensions.txt` (`saltext.kubernetes`,
`saltext.vault`) and `src/minion/vcf/salt-extensions.txt` (the same plus
`saltext.vcf` and `saltext.bmc`). The extension step constrains `salt` to the
installed onedir version, so pip does not replace it.

Examples:

```bash
# Different Salt version
docker build --build-arg SALT_VERSION=3007.1 -t salt-master:3007.1 src/master

# Extensions through an internal PyPI mirror
docker build \
  --build-arg PIP_INDEX_URL=<your-mirror-pypi-simple-url> \
  --build-arg PIP_TRUSTED_HOST=<your-mirror-host> \
  --build-arg PIP_ONLY_BINARY=:all: \
  -t salt-minion:0.1.0 src/minion/kubernetes

# Private CA needed while downloading build dependencies (BuildKit secret,
# not kept in the final image)
docker build --secret id=build_ca,src=/path/to/ca.crt -t salt-master:3008.5 src/master
```

See [`../src/master/README.md`](../src/master/README.md) and
[`../src/minion/README.md`](../src/minion/README.md) for more.

### Getting a locally built image onto a cluster

- **With a registry:** tag and push, then set the chart's
  `agent.image.repository` and `agent.image.tag`. A registry that organises
  images in projects (such as Harbor) needs the project in the path:
  `<registry>/<project>/<image>:<tag>`. See [`helm-test.md`](helm-test.md).
- **Without a registry:** `docker save` the image and import it into every
  node's containerd store (`ctr -n k8s.io images import`), then set
  `agent.image.pullPolicy=Never`.

## Helm charts

The charts need no build step. Install from a checkout. The master chart
bundles the operator as a dependency, so fetch it first:

```bash
helm dependency update helm/salt-master
helm install salt-master helm/salt-master --namespace salt-master --create-namespace \
  --set agent.image.repository=<your-registry>/<project>/salt-master
helm install salt-minion helm/salt-minion --namespace salt --create-namespace \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set agent.minion.allowSelfGeneratedKey=true \
  --set agent.image.repository=<your-registry>/<project>/salt-minion
```

To produce distributable `.tgz` files (what CI runs as a packaging check):

```bash
helm dependency update helm/salt-master
helm package helm/salt-master helm/salt-minion helm/salt-key-operator
```

## Publishing

Building locally publishes nothing. To push under a real version tag, see
[`releasing.md`](releasing.md).
