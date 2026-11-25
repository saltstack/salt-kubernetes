# Release Preparation Checklist

Prepare a release of one component (an image or a chart) before tagging it.
How tagging and publishing work, and the tag patterns, are in
[`releasing.md`](releasing.md). The release workflows build and push for you:
you do not push images or chart packages by hand.

## 1. Decide what is being released

Images and charts are versioned independently. A chart that should ship a new
image needs its `values.yaml` image tag changed in a commit (the workflow does
not do that), and the image has to be released first.

## 2. Change the sources

- Image: edit the Dockerfile (`ARG SALT_VERSION`) or `salt-extensions.txt` under
  `src/`.
- Chart: edit `Chart.yaml` (`version`) and `values.yaml` under `helm/<chart>/`.
  The release workflow overwrites `version` and `appVersion` on the runner with
  the tag's version, so keep `Chart.yaml` equal to the version you are about to
  tag (the key operator chart workflow requires this, see `releasing.md`).
- Add the entry to the component's `CHANGELOG.md`: `src/master/CHANGELOG.md`,
  `helm/salt-master/CHANGELOG.md`, `helm/salt-minion/CHANGELOG.md` (image and
  chart), `src/salt-key-operator/CHANGELOG.md`,
  `helm/salt-key-operator/CHANGELOG.md`. Record the Salt and extension versions
  for images and the default image for charts.
- Update the documentation that names versions (root `README.md`, chart
  READMEs, `docs/`).

## 3. Verify locally

```bash
helm dependency update helm/salt-master
helm lint helm/salt-master helm/salt-minion helm/salt-key-operator
helm unittest helm/salt-minion        # needs the helm-unittest plugin
docker build -t salt-master:test src/master   # and the other images you changed
```

Pull request CI runs the same checks plus hadolint, Go vet, image builds and
Trivy scans. Merge the change to `main` first and wait for CI.

## 4. Tag

Push the component's tag from the merge commit (see `releasing.md`):

```bash
git tag salt-master-v1.1.0
git push origin salt-master-v1.1.0
```

## 5. Verify the release

- The workflow run succeeded and created a GitHub Release.
- The package is visible and public on GHCR (first release of a component:
  change the package visibility, see `releasing.md`).
- Install the published chart and image on a test cluster, for example with the
  steps in [`complete-system-test.md`](complete-system-test.md).
