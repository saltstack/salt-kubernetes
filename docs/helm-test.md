# Helm Test Workflow

A reproducible way to test a chart on a real Kubernetes cluster with an image
built from this checkout and pushed to a private registry. The example uses the
master chart; for the minion chart use `src/minion/kubernetes`,
`helm/salt-minion` and the values shown in
[`complete-system-test.md`](complete-system-test.md).

## Prerequisites

- `kubectl` configured for the target cluster, Helm 3, and Docker.
- A registry the cluster can pull from and you can push to.
- Registry layout: `<registry>/<project>/<image>:<tag>`. Registries that use
  projects (Harbor, for example) reject a push to `<registry>/<image>` with no
  project, so create the project first and always include it.
- If the registry uses a certificate from a private CA, that CA must be trusted
  in two places:
  - the container runtime on **every node** that will pull the image (for
    containerd, a `certs.d/<registry>/` directory with the CA file or a
    `hosts.toml`), and
  - the Docker daemon you push from (`/etc/docker/certs.d/<registry>/ca.crt`, or
    the equivalent in Docker Desktop and Rancher Desktop).
  The master chart has no `imagePullSecrets` value (the minion chart has
  `agent.image.imagePullSecrets`), so for the master use a project that nodes can
  pull anonymously or configure registry credentials in the node's containerd.

## Steps

1. **Build the image**
   ```bash
   docker build -t salt-master:ci-test src/master
   ```
2. **Tag and push**
   ```bash
   REGISTRY=registry.example.com
   PROJECT=salt
   IMAGE=salt-master
   TAG=ci-test
   docker login ${REGISTRY}
   docker tag ${IMAGE}:${TAG} ${REGISTRY}/${PROJECT}/${IMAGE}:${TAG}
   docker push ${REGISTRY}/${PROJECT}/${IMAGE}:${TAG}
   ```
3. **Fetch chart dependencies and render (sanity check)**
   ```bash
   helm dependency update helm/salt-master
   helm template test helm/salt-master \
     --namespace salt-master \
     --set agent.image.repository=${REGISTRY}/${PROJECT}/${IMAGE} \
     --set agent.image.tag=${TAG} \
     --set agent.trustedMinions.enabled=false
   ```
4. **Install or upgrade**
   ```bash
   helm upgrade --install salt-master-test helm/salt-master \
     --namespace salt-master --create-namespace \
     --set agent.image.repository=${REGISTRY}/${PROJECT}/${IMAGE} \
     --set agent.image.tag=${TAG} \
     --set agent.trustedMinions.enabled=false \
     --wait --timeout 5m
   ```
   `agent.trustedMinions.enabled=false` skips the bundled `salt-key-operator`
   subchart (whose image is pulled from GHCR by default) and keeps
   `salt-key -a` working. Leave it out to test with the operator.
5. **Verify**
   ```bash
   kubectl -n salt-master get pods -l app=salt-master -o wide
   kubectl -n salt-master exec salt-master-0 -c salt-master -- salt-key -L
   ```
   The pod is `salt-master-0`: the StatefulSet is named `salt-master`
   regardless of the release name.
6. **Clean up**
   ```bash
   helm uninstall salt-master-test -n salt-master
   ```
   The master key Secret (`<release>-master-keys`) created by the keygen Job is
   not owned by the release and remains; delete it before reinstalling under the
   same release name if you want a new master identity. PVCs created from
   `volumeClaimTemplates` also remain.
