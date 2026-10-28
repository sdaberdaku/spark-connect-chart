# spark-connect-chart: design

A Helm chart that runs an Apache Spark Connect server on Kubernetes.

Date: 2026-10-28. Status: approved 2026-10-28.

## Why

Spark Connect lets clients (PySpark, Scala, Go, ...) talk to a long-running Spark driver over gRPC. Running that
driver on Kubernetes needs more than a Deployment: the driver starts its own executor pods, so it needs RBAC, a pod
template, Spark properties that agree with the pod resources, and a way to expose a gRPC port and two web UIs.

This repository is a public, generic chart for that. It is meant to show how a chart is built and maintained:
stock Apache Spark images by default, no dependency on one cloud or ingress controller, tests that run a real
Spark query on a kind cluster, and automation that follows every Spark release without a person in the loop.

It supersedes the `spark-connect` chart (2.0.0) published from `sdaberdaku/charts`, whose templates are the
starting point. That chart stays published and gets a deprecation notice once this one is released.

## Goals

- Install a working Spark Connect server with `helm install` and no values, using the stock `apache/spark` image.
- Expose the Connect endpoint, the Spark UI and the optional history server through Ingress, Gateway API, or both.
- Support every Spark line from 4.0 onwards, each tested end to end on kind.
- When a new Spark version is published (patch, minor or major, including 5.x), a pull request is opened
  automatically, merged automatically when CI passes, and the chart is released automatically.
- Keep every other component (tools, CRDs, test dependencies, Actions) current through Renovate.
- Publish the chart as an OCI artifact on GHCR, list it on Artifact Hub, and document it in a README and a docs site.

## Non-goals

- No catalog configuration block (Iceberg, Glue, Hive metastore). Catalogs are plain Spark properties set through
  `sparkConf`.
- No cloud-specific templates or defaults (load balancer annotations, cloud target-group resources). Those go in
  `extraObjects` or in user values.
- No custom image built in this repository.
- No Spark 3.x.
- The chart does not create a Gateway or GatewayClass and does not install any controller.
- No driver high availability: Spark Connect is one driver per server, so the Deployment has one replica.
- No CRD or operator (this is not a Spark operator).

## Anti-goals

- Defaults that only work on one cloud or with one ingress controller.
- A routine Spark release that needs a manual step to reach users.
- A README or docs page that disagrees with `values.yaml`.

## Facts this design rests on

Checked on 2026-10-28:

- `apache/spark` publishes plain version tags. `4.2.0` is the same image as `4.2.0-scala2.13-java21-python3-ubuntu`;
  `4.1.3` and `4.0.x` are the same image as `<version>-scala2.13-java17-python3-ubuntu`. A plain tag therefore
  includes Python 3 and the default Java of that Spark line. `apache/spark` is pushed by the Spark release managers;
  the Docker official image `spark` carries the same tags but goes through a docker-library PR first.
- The Spark 4.2.0 distribution ships `jars/spark-connect_2.13-4.2.0.jar` and `sbin/start-connect-server.sh`, so the
  Connect server needs no extra packages. The e2e job proves this for every supported line.
- Tags pushed by a workflow with `GITHUB_TOKEN` do not trigger other workflows.
- `ct lint` fails a chart change that does not bump the chart version.

## Repository

- `sdaberdaku/spark-connect-chart`, public, Apache-2.0.
- The chart lives in `charts/spark-connect/` (chart-testing's default layout). The chart name is `spark-connect`.
- `main` is protected: changes only through PRs, required check `ci-ok`, linear history, squash merges only,
  branches deleted on merge. CI skips draft PRs.
- Manual one-time steps for the owner: install the Renovate app on the repo, enable "Allow GitHub Actions to create
  and approve pull requests", register the repository on Artifact Hub.

## The chart

### Driver and executors

- The driver is a Deployment with one replica and the `Recreate` strategy, so two Connect servers never run at once
  during an upgrade. It runs `/opt/entrypoint.sh /opt/spark/sbin/start-connect-server.sh` with
  `SPARK_NO_DAEMONIZE=true`, `spark.driver.host` set to the pod IP, and a `preStop` hook that calls
  `stop-connect-server.sh`.
- Executors are started by the driver through Spark's Kubernetes scheduler backend, from a pod template held in a
  ConfigMap. They use the same image as the driver unless overridden.
- Driver and executor sizes are set once in values (cores, CPU request, memory, memory overhead, ephemeral storage).
  The chart derives both the Spark properties and the pod requests and limits from them, so the two cannot disagree.
- Scratch space (`spark.local.dir`, the Ivy cache, `/tmp`, the work dir) is on `emptyDir` volumes, which also lets
  the root filesystem be read-only.
- Liveness and readiness probes hit the Spark UI port; their timings are values.
- Per component (driver, executor, history server): annotations, labels, extra env, nodeSelector, affinity,
  tolerations, topology spread constraints, priority class. There is no default affinity.

### Spark configuration

- `sparkConf` is a map of Spark property to value. It is rendered, sorted, into the properties file the driver
  starts with. String values go through `tpl`, so `{{ .Release.Namespace }}` and similar work.
- The chart sets the properties it owns: master URL, namespace, ports, driver host, image, service account, pod
  template, and the sizes from the previous section. If `sparkConf` sets one of those keys, rendering fails with a
  message naming the value to use instead. That keeps pod resources and Spark settings in step.
- The default `sparkConf` sets `spark.sql.execution.pythonUDF.arrow.enabled: "false"`. Spark 4.2 turns Arrow on for
  Python UDFs by default, and the stock images have no `pyarrow`, so a plain `@udf` fails with
  `ModuleNotFoundError: No module named 'pyarrow'` (checked on 4.2.0). It is a default, not a chart-owned key: users
  with pyarrow in their image set it back to `"true"`.
- `packages` (list of Maven coordinates) becomes `spark.jars.packages`. With stock images this is how users add
  Delta Lake, Iceberg or cloud connectors.
- Driver and executor JVM options are values, with defaults `-XX:+ExitOnOutOfMemoryError -XX:+UseG1GC`.
- Optional, each behind its own value:
  - FAIR scheduler pools (list of pools rendered to `pools.xml`, and `spark.scheduler.allocation.file` set).
  - A custom `log4j2.properties`.
  - Metrics: `metrics.properties` with the Prometheus servlet, a ServiceMonitor, and a PrometheusRule whose rules
    are user-supplied.
- Config changes restart the driver through checksum annotations on the pod template.
- `values.schema.json` validates the values.

### Services and exposure

- One Service for the driver with the Connect port (15002, `appProtocol: kubernetes.io/h2c`) and the UI port
  (4040). The history server has its own Service (18080).
- Each endpoint (`connect`, `ui`, `historyServer`) can be exposed through:
  - Ingress: `enabled`, `className`, `annotations`, `hosts` with paths, `tls`. No controller-specific defaults.
  - Gateway API: a `GRPCRoute` (v1) for `connect`, an `HTTPRoute` (v1) for `ui` and `historyServer`, with
    `parentRefs` (including `sectionName`), `hostnames`, `annotations`, and extra rule matches for the HTTPRoutes.
- Ingress and Gateway API can be enabled together for the same endpoint.

### Security

- Defaults pass the `restricted` Pod Security Standard for the driver, the executors and the history server:
  non-root (UID 185, the `spark` user in the `apache/spark` images), `seccompProfile: RuntimeDefault`, all
  capabilities dropped, no privilege escalation, read-only root filesystem.
- Two ServiceAccounts (create toggles, annotations for cloud workload identity): one for the driver, bound to the
  Role below, and one for executors with no Role binding. Executors run user code, so they get no Kubernetes API
  rights.
- A namespaced Role with only what the driver needs to manage executor pods and their services, config maps and
  PVCs. The e2e tests prove the list is enough.
- Connect authentication: an optional pre-shared token (`spark.connect.authenticate.token`), off by default. The
  token comes from a Secret the user names, or from a Secret the chart generates (kept across upgrades with
  `lookup`), and reaches the driver through an env var, never through the rendered properties file. The PySpark
  client switches to TLS whenever a token is set while the server speaks plaintext gRPC, so with a token the
  endpoint is usable only behind TLS termination at the Ingress or Gateway, not over `kubectl port-forward`.
  `NOTES.txt` and the docs warn that an exposed endpoint without a token lets anyone who reaches it run code.

### Optional extras

- History server: a Deployment, off by default, reading `spark.history.fs.logDirectory` from its own values. Storage
  for event logs is the user's. The supported path with stock images is a PVC shared with the driver. Stock images
  have no cloud storage connectors, and `packages` only reaches spark-submit, not the history server daemon, so the
  docs say object-store logs need an image with the connector jars.
- Every component accepts extra volumes, volume mounts and env, for things like extra jars or certificates.
- Scheduled driver restart: a CronJob, off by default, that runs `kubectl rollout restart` on the driver Deployment,
  with its own ServiceAccount and a Role limited to that Deployment. The kubectl image is a value tracked by Renovate.
  This exists because a long-running Connect server accumulates state (session class loaders, JIT code cache) that a
  periodic restart clears.
- `extraObjects`: a list of extra manifests, rendered with `tpl`, for anything cluster-specific.

## Versions

- `appVersion` is the Spark version. `image.repository` defaults to `apache/spark` and `image.tag` defaults to
  `appVersion`. There is no separate image flavour value; users who want another flavour set `image.tag`.
- Supported Spark lines: every `X.Y` with `X >= 4` that has plain `X.Y.Z` tags on `apache/spark`. A file in the
  repo lists one row per line at its latest patch; CI tests every row. The default `appVersion` is the newest row.
- The chart's version follows its own semver, starting at 1.0.0, with these rules for Spark changes:
  - a Spark patch on any row: chart patch;
  - a new Spark minor line (which becomes the default): chart minor;
  - a new Spark major line (which becomes the default): chart major, since upgrading the chart then moves users to
    a new Spark major.
  - Template or values changes made by hand: the author picks the bump in the PR.

## Tests

On every PR:

- `helm lint` and `ct lint` (which enforces the version bump).
- helm-unittest suites for every template, covering each toggle and each exposure combination (off, Ingress only,
  Gateway only, both), the `sparkConf` collision failure, and the derived resources.
- kubeconform on the rendered manifests for the last three Kubernetes minors, with schemas for the Gateway API and
  Prometheus Operator CRDs.
- The chart README (helm-docs) and `values.schema.json` are generated at build time and not committed, so they
  cannot drift; committed copies would go stale on every Renovate PR (planning-time call, 2026-10-28).
- End to end on kind, one job per Spark row:
  - Install the Gateway API CRDs (standard channel), Envoy Gateway and a Gateway.
  - Label the release namespace `pod-security.kubernetes.io/enforce=restricted`.
  - Install the chart with the GRPCRoute enabled and the row's Spark version.
  - Run a PySpark Connect client of the same Spark version, on the same Python minor as the image's `python3`
    (read from the image), twice:
    - over `kubectl port-forward` against a release without a token;
    - through the Gateway with an HTTPS listener (self-signed certificate made in the job) against a release with a
      token, which proves authentication and the TLS path together.
  - Each run executes a query that needs an executor and a plain Python UDF under the chart's defaults, which proves
    executor pods start and that the executor Python works.
- A single `ci-ok` job that depends on all of the above.

The same scripts run locally through `make` targets (create the kind cluster, install, run the e2e client, tear
down), with the kind cluster config in the repo.

## Automation

### Renovate

- Spark patches: each row of the Spark versions file, and `appVersion` for the default row, patch updates only.
  The same PR bumps the chart patch version (Renovate `bumpVersions` or an equivalent post-upgrade step).
- Everything else the repo uses: kind and its node images, Helm, helm-unittest, chart-testing, kubeconform,
  helm-docs, the Gateway API CRDs, the Envoy Gateway chart, the kubectl image in values, the docs site's Python
  requirements, and GitHub Actions. Updates that change the packaged chart (the kubectl image) also bump the chart
  patch version; tooling-only updates do not.
- All Renovate PRs auto-merge once `ci-ok` passes.

### Discovery of new Spark lines

A scheduled workflow (daily) lists the plain `X.Y.Z` tags on `apache/spark`. For any line `X.Y` newer than the
newest row, with `X >= 4`, it adds a row at the latest patch, sets `appVersion`, bumps the chart minor or major as
above, and opens a PR with auto-merge enabled. It must handle 5.0.0 and later majors with no code change. If CI
fails, the PR stays open for a person to look at.

### Release

On every push to `main` (and on demand), a workflow compares the chart version in `Chart.yaml` with the existing
tags. If `v<version>` does not exist, the same run:

1. creates the tag;
2. packages the chart and pushes it to `oci://ghcr.io/sdaberdaku/charts` (package `charts/spark-connect`);
3. creates a GitHub Release with the `.tgz` and generated notes;
4. publishes the Artifact Hub repository metadata.

Tagging and releasing happen in one run because a tag pushed with `GITHUB_TOKEN` would not start a second workflow.

The same limit applies to the discovery PR: a PR opened with `GITHUB_TOKEN` does not start CI, and a merge done by
auto-merge on that PR does not start the release workflow. So the discovery workflow dispatches CI on its PR branch
itself (the dispatched run reports `ci-ok` for the PR head), and the release check also runs on a daily schedule,
before discovery, so a version merged by the bot is released at the latest the next day. Renovate PRs come from the
Renovate app and trigger CI and the release normally.
The GHCR package must be public; if it does not come out public automatically, the owner flips it once.

### Docs site

MkDocs (Material) on GitHub Pages, deployed from `main` when docs change and after each release.

## Documentation

- README: what the chart does, quickstart, the exposure options, a link to the docs site, and the values table
  generated by helm-docs.
- Docs site pages:
  - Quickstart on kind, from cluster creation to a PySpark client running a query.
  - Configuration: sizing, `sparkConf`, packages, pools, metrics.
  - Exposure: Ingress examples for a few controllers and Gateway API examples, including gRPC specifics. One
    example is the AWS Load Balancer Controller's `TargetGroupConfiguration` (gRPC health checks) passed through
    `extraObjects`; the chart itself has no template for it (owner agreed 2026-10-28).
  - Python version matching: Python UDFs need the executor Python to match the client's minor version; which Python
    each stock image ships; stock images have no pyarrow or pandas, so pandas UDFs and Arrow-optimized UDFs need
    an image that has them (such as `ghcr.io/sdaberdaku/spark`) and `spark.sql.execution.pythonUDF.arrow.enabled`
    set back to `"true"`.
  - Security: the token, why it needs TLS termination in front, and the risk of exposing the endpoint without it.
  - Operations: upgrades, the scheduled restart, metrics and alerts, the history server.
  - Development and release: tests, the automation above, how a release happens.

## After the first release

- Release a last version of `spark-connect` in `sdaberdaku/charts` with `deprecated: true` and a README pointer to
  this repository (draft shown to the owner before pushing).
- Add the chart to the profile README (draft first).

## Left to the builder

- File layout inside the chart, helper names, how the unittest suites are split.
- Value names and structure, within the shape described here.
- The exact Role rules (the minimum that passes e2e).
- Script language for discovery and e2e, and the Renovate syntax.
- Which kind node images to test on, and the chart's `kubeVersion` constraint.
- Whether the e2e jobs also cover the history server, if that is cheap on a one-node kind cluster.

## Decided by the owner (2026-10-28)

- A generic public showcase, not a migration of any existing deployment.
- Both Ingress and Gateway API supported.
- No catalog configuration block.
- The chart stays cloud agnostic: no cloud-specific templates; cloud examples (such as the AWS
  `TargetGroupConfiguration`) live in the documentation only.
- Stock Spark images; no image flavour in the tag, use the plain `X.Y.Z` tags.
- Spark 4.0 and later only.
- New Spark versions, including a new major, go from PR to published chart automatically when tests pass.
- The `spark-connect` chart in `sdaberdaku/charts` is the starting point.
- Arrow for Python UDFs off by default in `sparkConf`, so plain UDFs work on stock images.
- Optional Connect token, off by default, tested through a TLS Gateway listener.

## Calls made during design (owner to check)

- Repository name `spark-connect-chart`.
- `apache/spark` over the Docker official `spark` image.
- Chart version rules: Spark patch, minor and major map to chart patch, minor and major.
- `sparkConf` as a map, with rendering failing on keys the chart owns.
- Restricted Pod Security Standard by default, tested in e2e.
- History server and scheduled restart included, both off by default; `extraObjects` included.
- Envoy Gateway as the Gateway implementation in e2e; Ingress covered by unit tests only.
- OCI on GHCR plus Artifact Hub, no classic `index.yaml` Helm repository.
- MkDocs on GitHub Pages for the docs site; GitHub Releases as the changelog.
- First version 1.0.0.
- Separate executor ServiceAccount with no API rights.
- History server event logs on a shared PVC with stock images; object stores need a custom image.
- Generic extra volumes, mounts and env on every component.
- Discovery dispatches its own CI; the release check also runs daily.
