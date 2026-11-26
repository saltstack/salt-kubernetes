# Changelog (salt-key-operator chart)

Records what each chart release defaults to. The release tag is
`chart-salt-key-operator-vX.Y.Z` (see [`docs/releasing.md`](../../docs/releasing.md));
headings below use the older `salt-key-operator-chart/vX.Y.Z` naming. The chart's own
version is independent of the image version it happens to default to —
check here, not the tag number.

## Unreleased
- **`watchNamespace` now defaults to the release namespace** (empty), not the fixed `salt-master`,
  and cluster-wide watching is the explicit `clusterWide: true` (it used to be `watchNamespace: ""`).
  The Deployment goes into the release namespace but the Role and RoleBinding went into
  `watchNamespace`, so installing the salt-master chart, which bundles this chart, into any other
  namespace failed with `namespaces "salt-master" not found` and left a half-installed release.
  Found by installing the master chart with its defaults on a real cluster. Installing into a
  namespace named `salt-master` behaves as before.
- The default image repository is now `ghcr.io/saltstack/salt-key-operator`, where the image
  workflow publishes. The previous default, `ghcr.io/saltstack/salt-kubernetes/salt-key-operator`,
  does not exist.

## salt-key-operator-chart/v0.1.0
- Default image: `salt-key-operator:0.1.0` (see
  [`src/salt-key-operator/CHANGELOG.md`](../../src/salt-key-operator/CHANGELOG.md) for what that image version carries).
- Installs the `SaltMinionKey` CRD (`crds/salt.saltstack.io_saltminionkeys.yaml`).
- Deliberately lightweight defaults: `replicas: 1`, `leaderElection.enabled: false`,
  20m/32Mi resource requests - no control-plane HA for a controller that
  does nothing but occasionally patch one ConfigMap per namespace.
- `watchNamespace: salt-master` by default, matching
  `salt-master`'s own default namespace - scopes RBAC to a
  namespaced `Role`/`RoleBinding` in just that namespace rather than a
  cluster-wide `ClusterRole`. Recommended install: same namespace as the
  target `salt-master` release (`helm install ... -n salt-master`). The `salt-master` chart also installs this chart
  as a subchart when `agent.trustedMinions.enabled` is true (the default).
