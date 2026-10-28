# Development and release

## Make targets

All tools are pinned in the `Makefile` and downloaded into `.bin/` by `make tools`, so nothing needs to be installed globally except Docker, Python 3 and (for the end-to-end run) uv.

| Target | What it does |
| ------ | ------------ |
| `make tools` | Download the pinned helm, helm plugins, kind, kubectl, helm-docs, kubeconform and yq. |
| `make schema` | Generate `values.schema.json` from `values.yaml`. |
| `make docs` | Generate the chart README with helm-docs and copy it to `docs/site/values.md`. |
| `make lint` | `helm lint`. |
| `make unittest` | helm-unittest suites. |
| `make kubeconform` | Validate the rendered manifests and the executor pod template for the default and all-on values, on the last three Kubernetes minors. |
| `make ct-lint` | chart-testing lint in Docker (it enforces the chart version bump against `main`). |
| `make versions-check` | Check that `appVersion` equals the highest Spark version in `spark-versions.json`. |
| `make check` | `lint`, `unittest`, `kubeconform` and `versions-check`. |
| `make package` | Package the chart into `dist/`. |
| `make e2e` | End-to-end run on kind for `SPARK_VERSION` (default: the chart `appVersion`). |

The generated files (`charts/spark-connect/README.md`, `charts/spark-connect/values.schema.json`, `docs/site/values.md`) are not committed. Every target that needs them generates them first, so they cannot go stale.

Python helper tests run with `python3 -m unittest discover -s tests`.

## Build the docs site

```console
make tools docs
pip install -r docs/site/requirements.txt
mkdocs build --strict
```

`mkdocs serve` previews the site locally.

## End-to-end test

`make e2e SPARK_VERSION=4.2.0` creates a kind cluster, loads the Spark image, installs Envoy Gateway, and runs a PySpark client of the same Spark version on the Python minor of the image's `python3`. The client runs a query that needs an executor and a Python UDF, twice:

- over `kubectl port-forward` against a release without a token;
- through a Gateway with an HTTPS listener (self-signed certificate) against a release with a token, and once more without the token, which must be refused.

The release namespace is labelled `pod-security.kubernetes.io/enforce=restricted`. `KEEP_CLUSTER=1` keeps the cluster afterwards.

## Pull requests

`main` is protected: changes go through a pull request that merges when the `ci-ok` check passes. CI has three parts:

- `static`: `make check`, the Python tests and `ct lint`;
- `docs`: `make tools docs` and `mkdocs build --strict`;
- `e2e`: one job per row of `spark-versions.json`.

Draft pull requests skip CI, so `ci-ok` stays red on a draft on purpose. A change to the packaged chart (templates, values, `Chart.yaml`) needs a chart version bump, which `ct lint` enforces. The author picks the bump.

## Spark versions and automation

`spark-versions.json` has one row per Spark line at its latest patch. CI tests every row, and `appVersion` is the highest one.

- Renovate opens pull requests for Spark patch updates (minor and major updates of `apache/spark` are left to the discovery job), for the tools pinned in the `Makefile`, the end-to-end script and the workflows, for the kubectl image used by the restart job, the docs requirements and the GitHub Actions. They merge automatically once `ci-ok` is green. A Spark patch of the default line moves `appVersion` and bumps the chart patch version; a patch of an older line only changes its CI row, since the packaged chart does not change.
- A daily discovery workflow lists the plain `X.Y.Z` tags on `apache/spark`. For any line `X.Y` with `X >= 4` that is newer than the newest row, it adds a row at the latest patch, moves `appVersion`, bumps the chart minor (or the major, for a new Spark major) and opens a pull request with auto-merge. A new Spark major needs no code change. If CI fails the pull request stays open for a person to look at.
- On every push to `main`, a release workflow compares the chart version in `Chart.yaml` with the existing tags. If `v<version>` does not exist yet, the same run creates the tag, packages the chart, pushes it to `oci://ghcr.io/sdaberdaku/charts/spark-connect`, and creates a GitHub Release with the packaged chart and generated notes. The release check also runs daily, because a pull request merged by the discovery bot does not start workflows.

Nothing in this flow is run by hand. A person only steps in when CI fails on an automatic pull request.
