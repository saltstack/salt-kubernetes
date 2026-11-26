# Releasing

This is a monorepo with independently versioned images and charts. There is
no repo-wide release tag: pushing a tag scoped to one component fires only
that component's workflow (`.github/workflows/release-*.yml`).

Everything publishes to GHCR under the repository owner (`ghcr.io/<owner>/...`,
`ghcr.io/saltstack/...` for the upstream repository).

## What the workflows do

The workflows do **not** read `CHANGELOG.md`, `Chart.yaml` or any version file
to decide what to publish: the version is whatever follows the tag prefix.
Keep the changelog entry in the same pull request that changes the component,
and add the release heading before tagging; nothing enforces it.

### Docker images

| Component | Source | Tag to push | Published as |
| --- | --- | --- | --- |
| Master | `src/master` | `salt-master-vX.Y.Z` | `ghcr.io/<owner>/salt-master:X.Y.Z` and `:latest` |
| Minion (Kubernetes) | `src/minion/kubernetes` | `salt-minion-vX.Y.Z` | `ghcr.io/<owner>/salt-minion:X.Y.Z` and `:latest` |
| Minion (VCF) | `src/minion/vcf` | `salt-minion-vcf-vX.Y.Z` | `ghcr.io/<owner>/salt-minion-vcf:X.Y.Z` and `:latest` |
| Key operator | `src/salt-key-operator` | `salt-key-operator-vX.Y.Z` | `ghcr.io/<owner>/salt-key-operator:X.Y.Z` and `:latest` |

Each run builds the image for `linux/amd64`, scans it with Trivy (log-only: a
finding does not stop the release), pushes `linux/amd64` and `linux/arm64`
images, and creates a GitHub Release for the tag. Salt and extension
versions come from the Dockerfile (`ARG SALT_VERSION`, currently `3008.5`) and
`salt-extensions.txt`, not from the tag. The tag is the image's own semver, so
read the component's `CHANGELOG.md` for what a tag carries.

### Helm charts

| Chart | Tag to push | Published as |
| --- | --- | --- |
| `helm/salt-master` | `chart-salt-master-vX.Y.Z` | `oci://ghcr.io/<owner>/helm/salt-master:X.Y.Z` |
| `helm/salt-minion` | `chart-salt-minion-vX.Y.Z` | `oci://ghcr.io/<owner>/helm/salt-minion:X.Y.Z` |
| `helm/salt-key-operator` | `chart-salt-key-operator-vX.Y.Z` | `oci://ghcr.io/<owner>/helm/salt-key-operator:X.Y.Z` |

On the runner, the workflow rewrites `version:` and `appVersion:` in the
chart's `Chart.yaml` to the tag's version, packages the chart and pushes it
(the master workflow runs `helm dependency build` first so the operator
subchart is bundled). The rewritten `Chart.yaml` is not committed, so the
`version:` in the repository can differ from what was published. The image
tags a chart defaults to come from `values.yaml` and are not changed by the
workflow: update `values.yaml` in a commit before tagging.

### Scheduled and manual runs

Every release workflow also has a weekly `schedule` (Mondays, UTC) and
`workflow_dispatch`. Without a tag the Docker workflows build and push
`:latest`, and the chart workflows push version `0.0.0-snapshot`. They create
no GitHub Release in that case.

## Cutting a release

1. Update the component: `Chart.yaml`/`values.yaml` (chart) or the
   Dockerfile/`salt-extensions.txt` (image), and add the `CHANGELOG.md` entry.
2. Merge to `main`. Pull request CI (see the root `README.md`) must pass.
3. Tag the merge commit and push the tag, for example:
   ```bash
   git tag salt-master-v1.1.0
   git push origin salt-master-v1.1.0
   ```
   or use the interactive helpers `scripts/release-docker-tags.sh` and
   `scripts/release-helm-tags.sh`. Both scripts check out and pull `main`, and **delete and
   re-create** a tag that already exists, locally and on the remote. Read their
   prompts before confirming.
4. Watch the workflow run on GitHub.

Installing a published chart:

```bash
helm install salt-master oci://ghcr.io/<owner>/helm/salt-master \
  --version X.Y.Z --namespace salt-master --create-namespace \
  --set agent.image.repository=ghcr.io/<owner>/salt-master \
  --set agent.image.tag=<image version>
```

## First-time setup

GHCR packages created with `GITHUB_TOKEN` are private on first push. After the
first release of each image or chart, set the package visibility to public in
the organisation's package settings and link it to this repository. Otherwise
anonymous `docker pull` and `helm pull` fail.

## Tag names and default images

- Image and chart tags use the package name: `salt-minion-vX.Y.Z` for the image and
  `chart-salt-minion-vX.Y.Z` for the chart (likewise `salt-master-`, `salt-key-operator-`
  and `salt-minion-vcf-`). The Kubernetes minion workflow matches `salt-minion-v[0-9]*`:
  a digit has to follow the `v`, so a `salt-minion-vcf-vX.Y.Z` tag starts only the VCF
  workflow. Each tag therefore starts exactly one workflow.
  `scripts/release-docker-tags.sh` and `scripts/release-helm-tags.sh` create these same
  tag names.
- The default image repositories in the charts point at where the image
  workflows publish: `ghcr.io/saltstack/salt-minion`, `ghcr.io/saltstack/salt-minion-vcf`
  and `ghcr.io/saltstack/salt-key-operator`. A default only works once an image
  with that tag has been released (and its package made public, see above); the
  master chart's default repository is the unqualified `salt-master` on purpose, so a
  locally built image can be used as is.
- The tag `salt-minion-kubernetes-v0.1.0` that already exists on the remote matches no
  workflow, so no Kubernetes minion image was ever published for it. Release the
  Kubernetes minion image with a new `salt-minion-vX.Y.Z` tag (for example
  `salt-minion-v0.1.2`, see the minion image changelog).
