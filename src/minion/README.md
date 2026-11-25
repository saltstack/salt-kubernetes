# Salt Minion Images

This directory contains the Dockerfiles for the Salt Minion images used by the
[`salt-minion` Helm chart](../../helm/salt-minion/README.md).

Two flavors are provided. They share the same entrypoint behaviour, runtime identity and
build arguments and differ in the Salt extensions they carry:

1. **Kubernetes Minion** (`kubernetes/`) - `saltext.kubernetes` and `saltext.vault`
2. **VCF Minion** (`vcf/`) - the same plus `saltext.vcf` (VMware Cloud Foundation) and
   `saltext.bmc`

The extension sets live in `kubernetes/salt-extensions.txt` and
`vcf/salt-extensions.txt`. See [CHANGELOG.md](../../helm/salt-minion/CHANGELOG.md) for the
Salt and extension versions in each image release, and
[`docs/building.md`](../../docs/building.md) for building and publishing.

## Kubernetes Minion

A Salt Minion Docker image built from the official Salt onedir distribution using Salt's
[bootstrap script](https://github.com/saltstack/salt-bootstrap).

It is designed for running inside Kubernetes clusters and includes:
- Salt's Kubernetes execution module (`saltext.kubernetes`)
- HashiCorp Vault integration for secrets management (`saltext.vault`)
- Bundled `kubectl` (`INCLUDE_KUBECTL=true`, version `KUBECTL_VERSION`)
- Support for CIS Kubernetes compliance assessments via kube-bench

The image:

- Uses Salt `3008.5` by default (`SALT_VERSION`; `latest` is also accepted)
- Installs the extensions without replacing the onedir Salt: `salt` is constrained to the
  installed version while pip installs the extensions (see
  [CHANGELOG.md](../../helm/salt-minion/CHANGELOG.md))
- Runs as the non-root `salt` user with UID/GID `10001` (`SALT_UID`/`SALT_GID`)
- Supports an optional extra CA during the image build and does not keep it in the
  final image
- Communicates with the Salt Master on ports `4505` (publish) and `4506` (request/return)
- Can pre-seed the minion keypair from environment variables, or use a key already
  present in `/etc/salt/pki/minion`
- Supports multiple masters (a comma-separated `SALT_MASTER`)
- Has no Docker `HEALTHCHECK`; the Helm chart supplies Kubernetes probes

### Build

From the root of the repository:

```bash
docker build \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

Add `--platform linux/arm64` (or `linux/amd64`) to build for a specific architecture.
`TARGETARCH` is set by BuildKit and selects the `kubectl` download.

### Build behind a corporate TLS proxy

If HTTPS downloads need an extra root certificate, pass it as the optional `build_ca`
build secret. It is trusted only while the build downloads Salt, the extensions and
`kubectl`, and is removed again afterwards:

```bash
docker build \
  --secret id=build_ca,src=./corporate-root-ca.crt \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

The `build_ca` secret is supported by the Kubernetes Dockerfile only; the VCF Dockerfile
does not read it.

### Build arguments

Both Dockerfiles take the same arguments:

| Argument | Default | Purpose |
| --- | --- | --- |
| `SALT_VERSION` | `3008.5` | Salt version to install (`latest` is accepted) |
| `SALT_UID`, `SALT_GID` | `10001` | Numeric user and group of the `salt` account the container runs as |
| `SALT_HOME` | `/opt/saltstack/salt` | Home directory of the `salt` user |
| `SALT_SHELL` | `/usr/sbin/nologin` | Login shell of the `salt` user |
| `INCLUDE_KUBECTL` | `true` | Install `kubectl` into the image |
| `KUBECTL_VERSION` | `v1.30.2` | `kubectl` version to download |
| `EXTRA_SALT_EXTENSIONS` | empty | Extra pip requirements (space separated), installed after `salt-extensions.txt`, with the same `salt` constraint |
| `PIP_INDEX_URL` | empty | Install the extensions from this PyPI index (for example an internal mirror) |
| `PIP_TRUSTED_HOST` | empty | Passed to pip as `--trusted-host` |
| `PIP_ONLY_BINARY` | empty | Passed to pip as `--only-binary` |
| `APT_MIRROR` | empty | Replaces the `URIs:` of the Ubuntu apt sources |
| `SALT_GPG_KEY_URL`, `SALT_APT_REPO_URL` | Broadcom Salt package repository | Declared in the Dockerfiles but not used by the current build steps |

Example:

```bash
docker build \
  --build-arg SALT_VERSION=3008.5 \
  --build-arg EXTRA_SALT_EXTENSIONS="saltext.example==1.0.0" \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

The salt user and group IDs must match the `fsGroup` the chart uses
(`agent.podSecurityContext.fsGroup`, default `10001`) if you change them.

### Verify the image

```bash
docker image inspect salt-minion:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'
```

Verify the Salt version and that the onedir launcher is intact:

```bash
docker run --rm --entrypoint salt-minion salt-minion:local --version
docker run --rm --entrypoint salt-pip salt-minion:local list
```

The first command prints `salt-minion 3008.5 (Argon)` for the default build. The second
should list one `salt` package, at the same version, plus the extensions.

Verify runtime identity and permissions:

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c '
    id
    ls -ldn \
      /etc/salt \
      /etc/salt/minion.d \
      /etc/salt/pki/minion \
      /var/cache/salt/minion
  '
```

Expected: `uid=10001(salt) gid=10001(salt)`, and the listed directories owned by
`10001 10001`.

### Run

Start Salt Minion connecting to a master:

```bash
docker run --rm \
  --name salt-minion \
  --env SALT_MASTER=salt-master.example.com \
  salt-minion:local
```

### Environment variables

The entrypoint turns these variables into minion configuration or uses them for key
provisioning:

| Variable | Effect |
| --- | --- |
| `SALT_MASTER` | Master address (required unless `/etc/salt/minion.d/10-master.conf` is mounted). A comma-separated list becomes a YAML list: Salt multi-master mode, one simultaneous connection per master. |
| `SALT_MASTER_PORT` | Request/return port (`master_port`). Default `4506`. Must be numeric. |
| `SALT_PUBLISH_PORT` | Publish port (`publish_port`). Default `4505`. Must be numeric. |
| `SALT_MINION_ID` | Minion ID. If empty, `POD_NAME` is used, then the container hostname. The Helm chart sets `POD_NAME` to the pod name. |
| `POD_NAME` | Used as the minion ID when `SALT_MINION_ID` is empty. |
| `SALT_MASTER_FINGER` | Master fingerprint (`master_finger`), legacy. Ignored when `SALT_MASTER_PUBKEY_B64` is set. |
| `SALT_MASTER_PUBKEY_B64` | Base64-encoded master public key, written to `/etc/salt/pki/minion/minion_master.pub` so the minion trusts the master without a fingerprint. |
| `SALT_MINION_PRIVATE_KEY_B64`, `SALT_MINION_PUBLIC_KEY_B64` | Base64-encoded minion keypair, written to `/etc/salt/pki/minion/minion.pem` (`0400`) and `minion.pub` (`0644`). Applied only when both are set and `minion.pem` does not already exist. |
| `SALT_LOG_LEVEL` | Minion log level. Default `info`. Logs go to stdout. |
| `SALT_AUTH_TIMEOUT` | `auth_timeout` in seconds. Default `60`. |
| `SALT_MASTER_ALIVE_INTERVAL` | `master_alive_interval` in seconds. Default `60`. |
| `SALT_RECON_DEFAULT` | `recon_default` in ms. Default `1000`. |
| `SALT_RECON_MAX` | `recon_max` in ms. Default `5000`. |
| `SALT_RECON_RANDOMIZE` | `recon_randomize`, jitters reconnects. Default `True`. |
| `SALT_FIPS_MODE` | Writes `15-fips.conf` with `fips_mode: True` and the algorithms below. Default `true`. |
| `SALT_ENCRYPTION_ALGORITHM`, `SALT_SIGNING_ALGORITHM` | FIPS algorithms. Defaults `OAEP-SHA224` and `PKCS1v15-SHA224`. |
| `VAULT_ADDR` | Vault server address; enables the `vault` and sdb configuration. |
| `VAULT_AUTH_METHOD` | `approle` (default) or `token`. |
| `VAULT_ROLE_ID` | AppRole role ID. |
| `VAULT_SECRET_ID` | AppRole secret ID. |
| `VAULT_SECRET_ID_FILE` | Path to a file whose content is used as the secret ID, if it exists. |
| `VAULT_TOKEN` | Vault token (for `token` auth). |
| `VAULT_TOKEN_FILE` | Path to a file whose content is used as the token, if it exists. |
| `VAULT_SDB_PROFILE` | Name of the sdb profile that uses the vault driver. Default `vault_sdb`. |

The entrypoint always sets `master_tries: -1` and `retry_dns: 30`. Extra Salt
configuration can be mounted read-only under `/etc/salt/minion.d/`. If `SALT_MASTER` is
not set, the entrypoint requires `/etc/salt/minion.d/10-master.conf` to be mounted and
exits with status 64 otherwise.

### Smoke test

```bash
docker run --rm --entrypoint salt-minion salt-minion:local --version
```

```bash
docker run --rm \
  --env SALT_MASTER=127.0.0.1 \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'salt-call --local test.ping'
```

## VCF Minion

The VCF image has the same entrypoint, identity and build arguments as the Kubernetes
image. It carries `saltext.vcf` (VMware Cloud Foundation 9.x automation: vCenter, NSX,
SDDC Manager, VCF Operations, and more) and `saltext.bmc` in addition to
`saltext.kubernetes` and `saltext.vault`.

```bash
docker build \
  --tag salt-minion-vcf:local \
  ./src/minion/vcf
```

There is no separate VCF chart. Use the `salt-minion` chart and point
`agent.image.repository` and `agent.image.tag` at the VCF image.

## Kubernetes and Helm

The [`salt-minion` chart](../../helm/salt-minion/README.md) runs either image. It supports
two deployment modes:

- **in_cluster** (default): the minions run as a StatefulSet inside the cluster. Each pod
  is its own minion, with the pod name as the minion ID and its own keypair.
- **external**: RBAC only, for a minion running outside the cluster.

```bash
# Lint and render
helm lint ./helm/salt-minion --set agent.saltMasterHost=salt-master.example.com \
  --set agent.minion.allowSelfGeneratedKey=true
helm template salt-minion ./helm/salt-minion \
  --set agent.saltMasterHost=salt-master.example.com \
  --set agent.minion.allowSelfGeneratedKey=true \
  | kubectl apply --dry-run=client --validate=true -f -

# Install
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com \
  --set agent.minion.allowSelfGeneratedKey=true
```

The chart supplies the keys through a Secret and an init container, not through the
`SALT_MINION_*_KEY_B64` variables. It sets `POD_NAME`, so the minion ID is the pod name
unless `agent.minion.id` is set. See the chart README for the key layouts and the
multi-replica model.

## Configuration

### Minion Identity

The minion ID is chosen in this order:

1. `SALT_MINION_ID`, if set. The chart sets it from `agent.minion.id` (one replica only).
2. `POD_NAME`. The chart sets it from the pod name; in a StatefulSet that is a stable name
   such as `salt-minion-0`.
3. The container hostname.

### Key Management

Keys live in `/etc/salt/pki/minion/` (declared as a `VOLUME`):

- `minion.pem` - private key (mode 0400)
- `minion.pub` - public key (mode 0644)

#### Self-generated keys (development)

If no key is supplied and none exists in the directory, Salt generates a keypair when the
minion first starts. Without a volume on `/etc/salt/pki/minion` the key is lost when the
container is removed, and the master sees a new, unaccepted minion each time.

```bash
docker run --rm \
  --env SALT_MASTER=localhost \
  salt-minion:local
```

#### Pre-seeded keys

```bash
# Encode an existing keypair
PRIVATE_KEY=$(base64 -w0 < /path/to/minion.pem)
PUBLIC_KEY=$(base64 -w0 < /path/to/minion.pub)

docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env SALT_MINION_PRIVATE_KEY_B64="$PRIVATE_KEY" \
  --env SALT_MINION_PUBLIC_KEY_B64="$PUBLIC_KEY" \
  salt-minion:local
```

On macOS `base64` has no `-w0`; use `base64 -i <file>` (it does not wrap lines).

### Multi-Master Setup

Connect to several independent masters simultaneously (Salt's native multi-master mode,
not failover):

```bash
docker run --rm \
  --env SALT_MASTER="master-0.example.com,master-1.example.com,master-2.example.com" \
  salt-minion:local
```

The comma-separated list becomes a YAML list in the minion configuration. Every master
has to accept the minion key. For a Salt master cluster, give the minion the single
address of the cluster instead.

### Vault Integration

```bash
docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env VAULT_ADDR=https://vault.example.com:8200 \
  --env VAULT_AUTH_METHOD=approle \
  --env VAULT_ROLE_ID=my-role-id \
  --env VAULT_SECRET_ID_FILE=/run/secrets/vault_secret_id \
  --volume /path/to/secret:/run/secrets/vault_secret_id:ro \
  salt-minion:local
```

Or in Helm values:

```yaml
agent:
  vault:
    addr: https://vault.example.com:8200
    authMethod: approle
    roleId: my-role-id
    secretId: my-secret-id
```

### FIPS Compliance

FIPS mode is enabled by default (`fips_mode: True`, `OAEP-SHA224` encryption and
`PKCS1v15-SHA224` signing). Disable it only if the master is not FIPS-enforced:

```bash
docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env SALT_FIPS_MODE=false \
  salt-minion:local
```

The Helm chart has no value for this, so chart-deployed minions always run with the
default.

## Security Design

- The Salt Minion runs as non-root UID/GID `10001` (numeric `USER`, so Kubernetes'
  `runAsNonRoot` can verify it)
- The `salt` user has no login shell and no created home directory
- The directories the minion writes to (`/etc/salt`, `/var/cache/salt`, `/var/log/salt`)
  are owned by that user
- The extra build CA, if used, is not retained in the final image
- Minion keys are never accepted automatically by the image; acceptance happens on the
  master
- Pre-seeded keys support a declarative trust model

The chart adds no privilege escalation, drops all Linux capabilities, mounts the key
Secret read-only with mode `0440` and sets `fsGroup: 10001`.

## Health Checks

The images define no Docker `HEALTHCHECK`. The Helm chart gives the minion container two
exec probes that run `salt-call --local test.ping`:

| Probe | Initial delay | Period | Timeout | Failure threshold |
| --- | --- | --- | --- | --- |
| Liveness | 30s | 60s | 10s | 3 |
| Readiness | 15s | 30s | 10s | 3 |

The command checks the local minion installation, not the master connection.

## Related Documentation

- [Salt Minion Helm Chart](../../helm/salt-minion/README.md) - Kubernetes deployment details
- [Building images](../../docs/building.md) - build arguments and publishing
- [Complete System Test Guide](../../docs/complete-system-test.md) - integration testing procedures
- [Salt Project Documentation](https://docs.saltproject.io/) - Salt configuration and modules

## Troubleshooting

### Minion not connecting to master

Check master hostname resolution:

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'nslookup salt-master.example.com'
```

Check network connectivity:

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'nc -zv salt-master.example.com 4506'
```

View minion logs:

```bash
docker logs salt-minion
```

### `salt-minion: not found` or the wrong Salt version

An image built before the extension-constraint fix could have its onedir Salt replaced
by a pip-installed `salt`, which removes the `salt-minion` launcher. Rebuild with the
current Dockerfile. `salt-pip list` in the image should show a single `salt`.

### Entrypoint exits with "Salt Master configuration is missing"

Set `SALT_MASTER`, or mount `/etc/salt/minion.d/10-master.conf`.

### Cannot write keys or cache with a mounted volume

The container user is `10001:10001`. A volume mounted on `/etc/salt/pki/minion` or
`/var/cache/salt/minion` has to be writable by that user (in Kubernetes, `fsGroup: 10001`).

### FIPS mode issues

If the master is not FIPS-enforced, disable FIPS:

```bash
--env SALT_FIPS_MODE=false
```

Default algorithms: `OAEP-SHA224` and `PKCS1v15-SHA224`.
