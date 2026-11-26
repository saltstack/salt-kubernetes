# Changelog (salt-master image)

Records what each image release (release tag `salt-master-vX.Y.Z`, see
[`docs/releasing.md`](../../docs/releasing.md); the headings below use the older
`salt-master-image/vX.Y.Z` form) actually carries. The tag itself is an
independent semver for this image — it does not encode the Salt version, so check here before
assuming.

## salt-master-image/v1.1.0
- Salt: 3008.5 (was 3008.2). Base and install method unchanged.
- `entrypoint.sh` renders master cluster configuration (`/etc/salt/master.d/98-cluster.conf`)
  when `SALT_CLUSTER_ID` is set: `cluster_id`, `cluster_pki_dir`, `cluster_pool_port`,
  `cluster_secret`, `cluster_peers`, optionally `cluster_isolated_filesystem`, `keys.cache_driver`,
  `cluster_auto_replace_voters` and `cluster_min_voters`.
  Variables: `SALT_CLUSTER_ID`, `SALT_CLUSTER_PEERS`, `SALT_CLUSTER_SECRET`,
  `SALT_CLUSTER_PKI_DIR`, `SALT_CLUSTER_POOL_PORT`, `SALT_CLUSTER_ISOLATED_FILESYSTEM`,
  `SALT_CLUSTER_NODE_ADDRESS`, `SALT_CLUSTER_KEYS_CACHE_DRIVER`,
  `SALT_CLUSTER_AUTO_REPLACE_VOTERS`, `SALT_CLUSTER_MIN_VOTERS`, `SALT_CLUSTER_PEER_WAIT_SECONDS`.
- Cluster behaviour found by testing on a real cluster: Salt refuses a cluster member with no
  peers, so the entrypoint waits (default 120 seconds) for the other masters' DNS names to resolve,
  resolves them to IPs for `cluster_peers` (dropping its own entry), and exits with an error if
  none resolve. `SALT_CLUSTER_NODE_ADDRESS` is written as `interface:` and, unless
  `SALT_MASTER_ID` is set, also as the master `id:` (Salt uses `interface` as the consensus node
  identity).
- The entrypoint identifies itself by `POD_NAME` (falling back to the hostname) and also drops any
  peer that resolves to its own `SALT_CLUSTER_NODE_ADDRESS`, so it never lists itself as a peer.
  This matters with `hostNetwork`, where the container's hostname is the node's, not the pod's.
- Known limitation: with the pod IP as cluster identity, a restarted master cannot rejoin its
  cluster; the chart's `agent.cluster.hostNetwork` makes the identity a stable node IP (see the chart
  CHANGELOG). Classic (non-cluster) use is unaffected.
- Behaviour without `SALT_CLUSTER_ID` is unchanged (user 10001, health check on ports
  4505/4506).

## salt-master-image/v1.0.0
- Salt: 3008.2
- Base: ubuntu:24.04
- Install method: salt-bootstrap (onedir)
