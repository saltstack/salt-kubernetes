# CI Debug

When a GitHub Actions run fails, reproduce the failing step locally. The
pull request workflow is `.github/workflows/ci-cd-pr.yml`; it is the
reference for what runs and in what order.

## Checklist

1. Open the failing run and note the failing step name (for example `Helm lint`).
2. Check out the branch:
   ```bash
   git fetch origin && git checkout <branch>
   ```
3. Run the same command locally:
   ```bash
   # Dockerfile lint (CI scans every Dockerfile under src/)
   find src -name Dockerfile | while read -r f; do
     docker run --rm -i hadolint/hadolint hadolint --verbose - < "$f"
   done

   # Chart dependencies (the master chart depends on salt-key-operator)
   helm dependency update helm/salt-master

   # Chart unit tests (CI uses helm-unittest v1.2.1; only helm/salt-minion has suites)
   helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.2.1
   helm unittest helm/salt-key-operator
   helm unittest --with-subchart=false helm/salt-master
   helm unittest helm/salt-minion

   # Helm lint
   helm lint helm/salt-key-operator --debug
   helm lint helm/salt-master --debug
   helm lint helm/salt-minion --debug

   # Go (operator)
   (cd src/salt-key-operator && go fmt ./... && go vet ./...)

   # Image build, as CI does it
   docker buildx build src/master --file src/master/Dockerfile --load -t salt-master:local
   ```
4. Read the error output for file names and line numbers. For template
   errors, `helm template --debug <release> helm/<chart>` shows the rendered
   output and where it breaks. Some charts fail on purpose without required
   values (for example `agent.replicas > 1` without `agent.masterKeySecretName`
   on the master chart, or no key source on the minion chart).
5. Fix the source file and re-run the same command until it passes.
6. Commit and push; the workflow re-runs on the pull request.

`scripts/ci.sh` is an older local approximation of the CI pipeline and is not
kept in sync with the workflows (it still references paths that no longer
exist). Prefer the commands above.
