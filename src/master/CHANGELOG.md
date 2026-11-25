# Changelog (salt-master image)

Records what each `salt-master-image/vX.Y.Z` release tag (see
[`docs/releasing.md`](../../docs/releasing.md)) actually carries. The tag itself is an
independent semver for this image — it does not encode the Salt version, so check here before
assuming.

## salt-master-image/v1.1.0
- Salt: 3008.5
- `entrypoint.sh` renders master cluster config when `SALT_CLUSTER_ID` is set
  (`SALT_CLUSTER_PEERS`, `SALT_CLUSTER_SECRET`, `SALT_CLUSTER_PKI_DIR`,
  `SALT_CLUSTER_POOL_PORT`, `SALT_CLUSTER_ISOLATED_FILESYSTEM`).

## salt-master-image/v1.0.0
- Salt: 3008.2
- Base: ubuntu:24.04
- Install method: salt-bootstrap (onedir)
