# Image sources

This directory holds the source for each container image. Each subdirectory is
the Docker build context for its image.

| Directory | Image | Notes |
| --- | --- | --- |
| [`master`](master) | `salt-master` | Salt master. See [`master/README.md`](master/README.md). |
| [`minion/kubernetes`](minion/kubernetes) | `salt-minion` | Minion with `saltext.kubernetes`, `saltext.vault` and `kubectl`. See [`minion/README.md`](minion/README.md). |
| [`minion/vcf`](minion/vcf) | `salt-minion-vcf` | Minion with configurable extensions (VCF by default). See [`minion/README.md`](minion/README.md). |
| [`salt-key-operator`](salt-key-operator) | `salt-key-operator` | Go operator for the `SaltMinionKey` CRD. See [`salt-key-operator/README.md`](salt-key-operator/README.md). |

Build commands are in [`../docs/building.md`](../docs/building.md). The Helm charts
are in [`../helm`](../helm).
