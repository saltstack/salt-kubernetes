# Changelog (salt-minion)

Image and chart in this directory publish under separate release tags (see
[`docs/releasing.md`](../../docs/releasing.md)) but neither tag encodes the Salt/extension
versions it carries — check here.

## Image releases (`salt-minion-image/vX.Y.Z`)

### Unreleased
Applies to both `src/minion/kubernetes` and `src/minion/vcf`.
- **Fix: installing the Salt extensions no longer replaces the onedir Salt.** The
  extensions (for example `saltext.kubernetes`) require `salt>=3006`, and pip does not
  count the bootstrap-installed onedir Salt as satisfying that, so it downloaded
  another `salt` from the index and installed it over the onedir one, which removed the
  `salt-minion` launcher. The extension step now reads the installed version with
  `salt-pip list --format=freeze` and passes it to pip as a constraint, so pip only adds
  the extensions and their other dependencies. The build fails if no `salt==` entry is
  found.
- The runtime identity is now a build-time choice: `SALT_UID`/`SALT_GID` (default
  `10001`), `SALT_HOME` (`/opt/saltstack/salt`) and `SALT_SHELL` (`/usr/sbin/nologin`).
  The `salt` user and group are created before Salt is installed, and `USER` is the
  numeric `10001:10001`. (The VCF image previously ran as `999:999`.)
- Build arguments `INCLUDE_KUBECTL`, `KUBECTL_VERSION`, `EXTRA_SALT_EXTENSIONS`,
  `PIP_INDEX_URL`, `PIP_TRUSTED_HOST`, `PIP_ONLY_BINARY` and `APT_MIRROR` are
  documented in [`src/minion/README.md`](../../src/minion/README.md).
- Salt is pinned to 3008.5 in both Dockerfiles (`SALT_VERSION=3008.5`); `latest` is
  also accepted.
- Extensions are unchanged: `saltext.kubernetes==2.1.0`, `saltext.vault==1.8.0` in both
  images, plus `saltext.vcf==1.0.0` and `saltext.bmc==0.0.1` in the VCF image.

- Removed the unused `SALT_GPG_KEY_URL` and `SALT_APT_REPO_URL` build arguments, and corrected
  comments that still named the old chart and file paths.

### salt-minion-image/v0.1.2
- Salt: 3008.5 (no other change)

### salt-minion-image/v0.1.1
- Salt: 3008.2
- Extensions: saltext.kubernetes==2.1.0, saltext.vault==1.8.0
- Base: ubuntu:24.04
- Bundles: kubectl v1.30.2
- `docker-entrypoint.sh` now (a) pre-seeds the minion's own keypair from
  `SALT_MINION_PRIVATE_KEY_B64`/`SALT_MINION_PUBLIC_KEY_B64` if present -
  previously this image had no such mechanism at all, unlike
  `salt-minion-vcf` - and (b) renders a comma-separated `SALT_MASTER` as a
  YAML list (Salt's native multi-master mode). No change to the Salt/
  extension versions above.

### salt-minion-image/v0.1.0
- Salt: 3008.2
- Extensions: saltext.kubernetes==2.1.0, saltext.vault==1.8.0
- Base: ubuntu:24.04
- Bundles: kubectl v1.30.2

## Chart releases (`salt-minion-chart/vX.Y.Z`)

### Unreleased
**Breaking - reinstall rather than `helm upgrade` from any earlier release.**
- `Deployment` -> `StatefulSet` (`templates/deployment.yaml` is now `templates/statefulset.yaml`),
  so every replica gets a stable, unique identity. The StatefulSet is named
  `agent.minion.idPrefix` (default `salt-minion`) and uses `podManagementPolicy: Parallel`.
  A Deployment cannot be converted in place.
- Previously `agent.replicas > 1` made every pod register as one and the same minion, all
  sharing one keypair. Now each pod is its own minion (the pod name is the ID, taken from
  `POD_NAME`) with its own keypair. New `agent.minion.idPrefix` names the StatefulSet and
  the pods. A default single-replica install registers as `salt-minion-0`.
- With `agent.replicas > 1` the chart rejects `agent.minion.id` and
  `agent.minion.privateKeyB64`/`publicKeyB64` (single-identity settings). `keySecretName`
  then points at a Secret holding `<pod>.pem`/`<pod>.pub` pairs; each pod mounts only its
  own (Secret `items` plus `subPathExpr: $(POD_NAME)`).
- The keygen Job generates one keypair per replica, only adds missing pairs when scaling up
  (existing pairs are never regenerated), and is named `<release>-keygen-<replicas>` when
  `replicas > 1`. Its Role gains `patch`. Scaling down leaves the extra pairs in the Secret.
- With `agent.replicas: 1` the Secret layout (`minion.pem`/`minion.pub`) and `agent.minion.id`
  behave as before.
- Key handling and security (from the earlier PKI preparation fix):
  - Keys always come from a Secret and are copied by the `prepare-minion-keys` init
    container into an `emptyDir` PKI volume. The init container runs as the minion's
    own non-root user with `agent.containerSecurityContext` (no root init container).
  - `agent.podSecurityContext` defaults gain `fsGroup: 10001`; the key Secret is mounted
    with mode `0440`; private key `0400`, public key `0644`.
  - `agent.persistence.*` (PVC/hostPath PKI storage) and
    `agent.initContainers.fixPkiPerms` are removed. Remove them from your values.
  - A key source is required in in_cluster mode (`keySecretName`, inline keys, or
    `allowSelfGeneratedKey`). `privateKeyB64` and `publicKeyB64` must be set together.
    Inline keys fail the install if an unmanaged Secret of that name exists. The keygen
    Job only runs when `keySecretName` and inline keys are empty.
- Images are configurable: `agent.image.{repository,tag,pullPolicy,imagePullSecrets}` and
  `keygen.image.{repository,tag,pullPolicy,imagePullSecrets}` (default `bitnami/kubectl:latest`).
- Documentation: the README now describes the StatefulSet identity model and key
  layouts, and how to run the helm-unittest suites (`helm unittest helm/salt-minion`).

- The key generation Job now runs with a restricted security context (new
  `keygen.podSecurityContext` and `keygen.containerSecurityContext`: non-root, `RuntimeDefault`
  seccomp, no privilege escalation, all capabilities dropped). Checked on a real cluster.
- Removed `agent.minion.grains` and `agent.minion.masterId`, and the `<release>-minion-config`
  ConfigMap they were written to: nothing mounted that ConfigMap, so they never had any effect.
- The default image repository is now `ghcr.io/saltstack/salt-minion`, where the image workflow
  publishes. The previous default, `ghcr.io/saltstack/salt-kubernetes/salt-minion`, does not
  exist. The `0.1.0` tag at the new path exists only once the Kubernetes minion image has been
  released (the workflow now triggers on `salt-minion-kubernetes-v*`; see `docs/releasing.md`).
- Removed the unused `scripts/` copies of the entrypoint scripts and `salt-extensions.txt` from the
  chart (the images read the files under `src/minion/`). `Chart.yaml` now describes a StatefulSet.

### salt-minion-chart/v1.0.0
**Breaking - defaults change on `helm upgrade` from any prior release:**
- `agent.minion.keySecretName` is now **required** - the chart fails fast
  otherwise. Set `agent.minion.allowSelfGeneratedKey: true` to explicitly
  opt back into the old self-generated-keypair behavior.
  `agent.persistence.enabled` was already `false` by default - no change
  there, but a self-generated key now needs that explicit opt-out too, not
  just an empty `keySecretName`.
- `agent.saltMasterHost` now also accepts a YAML list, for Salt's native
  [multi-master mode](https://docs.saltproject.io/en/3008/topics/tutorials/multimaster.html) -
  point it at every replica address of an active-active
  `salt-master-kubernetes` release instead of a single master.
- Default image: `salt-minion:0.1.1` (see "Image releases" above for what that
  version carries)

### salt-minion-chart/v0.1.0
- Default image: `salt-minion:0.1.0` (see "Image releases" above for what that
  version carries)
