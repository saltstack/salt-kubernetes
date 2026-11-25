# Task Shortcut Reference

Some documents in this directory are written as step lists that an AI coding
assistant (or a person) can follow end to end. Point the assistant at the file
instead of re-describing the task.

## Available shortcuts

- **[`helm-test.md`](helm-test.md)**: build an image, push it to a private
  registry, and install a chart on a real cluster.
- **[`ci-debug.md`](ci-debug.md)**: reproduce CI failures locally (lint, chart
  unit tests, image builds) and fix them.
- **[`release-prep.md`](release-prep.md)**: checklist for preparing a component
  release before tagging (see also [`releasing.md`](releasing.md)).
- **[`complete-system-test.md`](complete-system-test.md)**: end-to-end test of
  master, operator and minions on a cluster.

## Using one

```
Please run the steps in docs/helm-test.md against my cluster.
```

Give the assistant the parameters the document leaves open (registry, project,
namespace, image tag). Review any command that changes the cluster or pushes
tags before it runs.

## Adding a new one

1. Add a `*.md` file under `docs/`.
2. Use a clear title, numbered steps, and list required parameters.
3. Only include commands you have run against the current charts.
