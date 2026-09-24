# Salt Master image

A Salt Master Docker image built from the official Salt onedir distribution using Salt's
[bootstrap script](https://github.com/saltstack/salt-bootstrap).

This is the master-only counterpart to the Salt Minion images. It does not install Salt
extensions or bundle `kubectl`, because execution and state modules run on minions. The
long-running Salt Master container does not communicate with the Kubernetes API directly.

The image:

- Uses Salt `3008.2` by default.
- Runs as the non-root `salt` user with UID/GID `10001`.
- Supports an optional corporate CA during image build.
- Does not retain the build-time corporate CA in the final image.
- Exposes Salt ports `4505` and `4506`.
- Includes a Docker health check for both Salt ports.
- Supports externally supplied or Kubernetes-managed master keys.

See [CHANGELOG.md](CHANGELOG.md) for the Salt version included in each image release.

## Build

From the root of the `salt-kubernetes` repository:

```bash
docker build \
  --platform linux/arm64 \
  --tag salt-master:local \
  ./src/master
```

### Build behind a corporate TLS proxy

If HTTPS downloads require a corporate root certificate, export the trusted root certificate
from the macOS Keychain:

```bash
security find-certificate \
  -a \
  -c "Cloud Services Root CA" \
  -p \
  "${HOME}/Library/Keychains/login.keychain-db" \
  /Library/Keychains/System.keychain \
  /System/Library/Keychains/SystemRootCertificates.keychain \
  > /private/tmp/cloud-services-root-ca.crt
```

Verify the certificate:

```bash
openssl x509 \
  -in /private/tmp/cloud-services-root-ca.crt \
  -noout \
  -subject \
  -issuer \
  -dates
```

Build the image with the certificate supplied as a BuildKit secret:

```bash
docker build \
  --platform linux/arm64 \
  --secret id=build_ca,src=/private/tmp/cloud-services-root-ca.crt \
  --tag salt-master:local \
  ./src/master
```

The certificate is available only during the build. It is removed after Salt is installed and
is not persisted in the final runtime image.

### Build arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `SALT_VERSION` | `3008.2` | Salt version to install. Set it to another supported version or `latest` for the newest stable onedir release. |

Example:

```bash
docker build \
  --platform linux/arm64 \
  --build-arg SALT_VERSION=3008.2 \
  --tag salt-master:local \
  ./src/master
```

## Verify the image

```bash
docker image inspect salt-master:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'
```

Expected on an Apple Silicon Mac:

```text
Image=[salt-master:local] Architecture=arm64 OS=linux
```

Verify the installed Salt version:

```bash
docker run --rm \
  --platform linux/arm64 \
  salt-master:local \
  salt-master --version
```

Expected:

```text
salt-master 3008.2 (Argon)
```

Verify the runtime identity:

```bash
docker run --rm \
  --platform linux/arm64 \
  --entrypoint /bin/sh \
  salt-master:local \
  -c '
    id
    ls -ldn \
      /etc/salt \
      /etc/salt/master.d \
      /etc/salt/pki \
      /var/cache/salt/master
  '
```

Expected runtime user:

```text
uid=10001(salt) gid=10001(salt)
```

## Run

Start Salt Master and expose ports `4505` and `4506`:

```bash
docker run --rm \
  --name salt-master \
  --publish 4505:4505 \
  --publish 4506:4506 \
  salt-master:local
```

With no command arguments, the entrypoint starts `salt-master` in the foreground under `tini`.

For a local development environment where all minion keys can be accepted automatically:

```bash
docker run --rm \
  --name salt-master \
  --publish 4505:4505 \
  --publish 4506:4506 \
  --env SALT_AUTO_ACCEPT=true \
  salt-master:local
```

Do not enable automatic acceptance in production.

### Persist the master identity

Use a Docker volume to retain the master key pair between container restarts:

```bash
docker volume create salt-master-pki
```

```bash
docker run --rm \
  --name salt-master \
  --publish 4505:4505 \
  --publish 4506:4506 \
  --volume salt-master-pki:/etc/salt/pki/master \
  salt-master:local
```

### Environment variables

The entrypoint translates these variables into `/etc/salt/master.d/99-env.conf` or uses them to
initialize the master key pair:

| Variable | Effect |
| --- | --- |
| `SALT_AUTO_ACCEPT` | Sets Salt's `auto_accept` option. Leave unset or set to `false` when using Salt Key Operator. |
| `SALT_MASTER_ID` | Sets the Salt Master `id`. The pod hostname is used when it is not supplied. |
| `SALT_PRESENCE_EVENTS` | Enables or disables Salt presence events. Defaults to `True`. |
| `SALT_MASTER_PRIVATE_KEY_B64` | Optional base64-encoded master private key used when `master.pem` does not already exist. |
| `SALT_MASTER_PUBLIC_KEY_B64` | Optional base64-encoded master public key used when `master.pub` does not already exist. |

Additional configuration, pillar and state trees can be mounted as read-only volumes:

```bash
docker run --rm \
  --publish 4505:4505 \
  --publish 4506:4506 \
  --volume ./pillar:/srv/pillar:ro \
  --volume ./states:/srv/salt:ro \
  salt-master:local
```

## Health check

The image health check verifies that the running Salt Master is listening on both required TCP
ports:

- `4505`: Salt publish port
- `4506`: Salt request/return port

Start a detached test container:

```bash
docker run --detach \
  --name salt-master-health-test \
  salt-master:local
```

Wait for the health check:

```bash
sleep 40
```

Inspect the health state:

```bash
docker inspect salt-master-health-test \
  --format 'Status={{.State.Status}} Health={{.State.Health.Status}}'
```

Expected:

```text
Status=running Health=healthy
```

Verify the ports directly:

```bash
docker exec salt-master-health-test \
  /bin/sh -c '
    nc -z 127.0.0.1 4505
    nc -z 127.0.0.1 4506
  '
```

Remove the test container:

```bash
docker rm --force salt-master-health-test
```

## Smoke test

```bash
docker run --rm \
  salt-master:local \
  salt-master --version
```

```bash
docker run --rm \
  salt-master:local \
  salt-run test.arg testing
```

## Kubernetes and Helm

The Salt Master Helm chart is located at:

```text
helm/salt-master
```

When trusted-minion management is enabled, the chart installs Salt Key Operator as a conditional
dependency. Salt Key Operator does not need to be installed as a separate Helm release.

### Build the local images

Build Salt Key Operator:

```bash
docker build \
  --platform linux/arm64 \
  --tag salt-key-operator:local \
  ./src/salt-key-operator
```

Build Salt Master:

```bash
docker build \
  --platform linux/arm64 \
  --secret id=build_ca,src=/private/tmp/cloud-services-root-ca.crt \
  --tag salt-master:local \
  ./src/master
```

### Prepare and validate the chart

```bash
helm dependency update ./helm/salt-master
```

```bash
helm lint ./helm/salt-key-operator
helm lint ./helm/salt-master
```

Render the complete release:

```bash
helm template salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --include-crds \
  --set namespace=salt-master \
  --set agent.image.repository=salt-master \
  --set agent.image.tag=local \
  --set agent.image.pullPolicy=Never \
  --set agent.trustedMinions.enabled=true \
  --set salt-key-operator.image.repository=salt-key-operator \
  --set salt-key-operator.image.tag=local \
  --set salt-key-operator.image.pullPolicy=Never \
  --set salt-key-operator.watchNamespace=salt-master \
  > /tmp/salt-master-rendered.yaml
```

Validate the rendered Kubernetes resources:

```bash
kubectl apply \
  --dry-run=client \
  --validate=true \
  -f /tmp/salt-master-rendered.yaml
```

### Install

```bash
helm upgrade --install salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --create-namespace \
  --set namespace=salt-master \
  --set agent.image.repository=salt-master \
  --set agent.image.tag=local \
  --set agent.image.pullPolicy=Never \
  --set agent.trustedMinions.enabled=true \
  --set salt-key-operator.image.repository=salt-key-operator \
  --set salt-key-operator.image.tag=local \
  --set salt-key-operator.image.pullPolicy=Never \
  --set salt-key-operator.watchNamespace=salt-master \
  --wait \
  --wait-for-jobs \
  --timeout 5m
```

Verify the installation:

```bash
kubectl get pods,jobs,secrets,configmaps,services \
  --namespace salt-master
```

Expected pod state:

```text
salt-key-operator   1/1   Running
salt-master         2/2   Running
```

Verify Salt Master:

```bash
kubectl exec deployment/salt-master \
  --namespace salt-master \
  --container salt-master \
  -- salt-key -L
```

## Master key management

On a fresh Helm installation, the master-key generation Job creates a 2048-bit RSA key pair and
stores it in a Kubernetes Secret containing:

```text
master.pem
master.pub
```

The Secret is mounted read-only. An init container copies the key pair into a writable
`emptyDir`, applies the required ownership and permissions, and then exits.

The long-running Salt Master container runs as UID/GID `10001` and does not require Kubernetes
API access.

The key-generation Job is the only component that requires a service-account token. The normal
Salt Master ServiceAccount has automatic token mounting disabled.

The master key Secret is reused across pod restarts, allowing the Salt Master to retain the same
identity.

Verify that the Secret and running pod use the same public key:

```bash
kubectl get secret salt-master-master-keys \
  --namespace salt-master \
  -o jsonpath='{.data.master\.pub}' \
  | base64 --decode \
  | shasum -a 256
```

```bash
kubectl exec deployment/salt-master \
  --namespace salt-master \
  --container salt-master \
  -- sha256sum /etc/salt/pki/master/master.pub
```

The two hashes must match.

## Trusted minion management

When the following value is enabled:

```yaml
agent:
  trustedMinions:
    enabled: true
```

minion acceptance is managed declaratively through Salt Key Operator.

Do not use `salt-key -a` in this mode. Create a `SaltMinionKey` resource instead:

```yaml
apiVersion: salt.saltstack.io/v1alpha1
kind: SaltMinionKey
metadata:
  name: example-minion
  namespace: salt-master
spec:
  minionId: example-minion
  publicKey: |
    -----BEGIN PUBLIC KEY-----
    ...
    -----END PUBLIC KEY-----
```

Salt Key Operator writes accepted keys to the `salt-master-trusted-minions` ConfigMap.

Kubernetes exposes ConfigMap entries through symbolic links. Salt 3008 intentionally rejects
symlinked PKI keys, so the `trusted-minions-sync` sidecar copies each key into a writable
`emptyDir` as a regular file.

The sidecar also:

- Removes matching keys from `minions_pre`.
- Removes matching keys from `minions_rejected`.
- Removes accepted keys when the corresponding `SaltMinionKey` is deleted.

ConfigMap updates are asynchronous. Propagation may take approximately one minute for the kubelet
refresh plus the configured sidecar polling interval, which defaults to 15 seconds.

List accepted keys:

```bash
kubectl exec deployment/salt-master \
  --namespace salt-master \
  --container salt-master \
  -- salt-key -L
```

## Security design

The image and Helm chart apply the following security controls:

- Salt Master runs as non-root UID/GID `10001`.
- The long-running containers disable privilege escalation.
- The long-running containers drop all Linux capabilities.
- The temporary init container receives only the capabilities required to copy and secure the
  master keys.
- The master private key is stored in a Kubernetes Secret.
- The private key is written with mode `0400`.
- The public key is written with mode `0644`.
- The Secret source volume remains read-only.
- The normal Salt Master pod does not automatically receive a Kubernetes service-account token.
- The key-generation Job receives a service-account token only because it must create the Secret.
- The corporate CA is supplied as a temporary BuildKit secret and is not retained in the final
  image.
- Automatic minion acceptance is disabled by default for the Helm deployment.
- Trusted keys are managed through `SaltMinionKey` resources when Salt Key Operator is enabled.

## Why the runtime changes were required

The Salt onedir installation may create the `salt` user with a distribution-assigned UID that is
different from the UID declared by the image. The image therefore normalizes the `salt` user and
group to UID/GID `10001` and assigns ownership of Salt's writable directories to that identity.

Kubernetes Secret volumes are read-only, but Salt Master must create and update directories under
`/etc/salt/pki/master`. The Helm chart therefore mounts the Secret separately and uses an init
container to copy the master key pair into a writable volume.

Kubernetes ConfigMap files are symbolic links, while Salt 3008 rejects symlinked key files as a
PKI hardening measure. The trusted-minions sidecar converts the mounted ConfigMap entries into
regular files before Salt reads them.

The Docker health check observes the existing Salt Master process by checking ports `4505` and
`4506`. It does not start a second Salt Master daemon.

## Validation performed

The following validations were completed successfully:

- Helm linting for Salt Master and Salt Key Operator.
- Kubernetes client-side validation of the rendered Helm resources.
- ARM64 builds of both local images.
- Salt Master version check.
- Non-root UID/GID and directory ownership check.
- Build-time corporate CA removal check.
- Docker health check for ports `4505` and `4506`.
- Clean Helm installation into a new namespace.
- Master-key generation Job completion.
- Master-key hash comparison between the Secret and running pod.
- Master identity persistence after a Deployment restart.
- Declarative acceptance of a generated test key named `integration-test-minion`.
- Propagation of the accepted key into Salt as a regular file.
- Removal of the accepted key after deleting its `SaltMinionKey`.

The minion-key validation used a generated RSA test key. It did not start a real Salt Minion or
run an end-to-end command such as:

```bash
salt '*' test.ping
```

A real Salt Minion connectivity test can be added as a separate integration test.