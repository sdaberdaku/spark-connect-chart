# spark-connect-chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public, cloud-agnostic Helm chart for a Spark Connect server, on stock `apache/spark` images, tested on kind, kept current and released automatically.

**Architecture:** One chart in `charts/spark-connect/`. The driver is a Deployment running `start-connect-server.sh` with `SPARK_CONF_DIR` pointing at one ConfigMap (spark-defaults.conf, executor pod template, optional pools/log4j2/metrics files); executors are pods the driver creates. A versions file lists one Spark row per line ≥ 4.0; CI unit-tests the chart and runs an e2e PySpark client on kind per row; Renovate, a daily discovery job and a release workflow move new Spark versions to a published OCI chart without a person.

**Tech Stack:** Helm 4 (chart apiVersion v2, must also work on Helm 3), helm-unittest, helm-docs, helm-values-schema-json plugin, kubeconform, chart-testing (docker image), kind, Envoy Gateway, Python 3 stdlib (scripts), PySpark Connect client (`pyspark-client`), uv, GitHub Actions, Renovate (Mend app), MkDocs Material, GHCR OCI, Artifact Hub.

**Spec:** `docs/superpowers/specs/2026-10-28-spark-connect-chart-design.md` (read it before any task; it is binding).

## Global Constraints

- Repo `sdaberdaku/spark-connect-chart` (already created, public, empty; squash-only merges, branch auto-delete, auto-merge allowed, Actions may create PRs, Renovate app has access). Local path `/home/sebastian/github-sdaberdaku/spark-connect-chart`.
- Git identity in this repo: `Sebastian Daberdaku <sebastiandaberdaku@gmail.com>` (set with `git config user.*` locally, not globally).
- **No AI attribution anywhere**: no `Co-Authored-By` trailers, no "Generated with" lines, in commits, PRs, code, docs. No mention of AI tools, of any employer, or of other repositories as templates in committed text.
- Public prose (README, docs, PR bodies) in plain style: no "X, not just Y", no punchlines, no bold lead-ins, no em dashes.
- `charts/spark-connect/README.md` and `charts/spark-connect/values.schema.json` are generated (`make docs schema`) and gitignored: every target that needs them (lint, unittest, ct-lint, kubeconform, package, docs build) generates them first. Committed copies would go stale on every Renovate PR, and hosted Renovate cannot run post-upgrade commands. This replaces the spec's "checked in CI" README with "generated at build time": same no-drift goal.
- License Apache-2.0. Chart maintainer `Sebastian Daberdaku`, `sebastiandaberdaku@gmail.com`. First chart version `1.0.0`, `appVersion: "4.2.0"`.
- Image default `apache/spark`, tag defaults to `.Chart.AppVersion`; no image-flavour value.
- Supported Spark lines: `X.Y` with `X >= 4` having plain `X.Y.Z` tags on `apache/spark`. Current rows: 4.0.4, 4.1.3, 4.2.0 (checked 2026-10-28).
- Default `sparkConf` contains exactly `spark.sql.execution.pythonUDF.arrow.enabled: "false"`.
- Restricted Pod Security Standard for every pod the chart or the driver creates; UID/GID 185; read-only root filesystem.
- No cloud-specific templates. Cloud examples only in docs.
- Every pinned tool version carries a `# renovate: datasource=<ds> depName=<name>` comment on the line above it (one generic Renovate regex manager reads them).
- Conventional-commit messages (`feat:`, `fix:`, `ci:`, `docs:`, `test:`, `chore:`).

## Review Focus

1. `fullnameOverride`/long release names: every generated name stays ≤ 63 chars and Role/RoleBinding/SA names stay consistent → helm-unittest case with a 50-char release name in Task 2.
2. `sparkConf` values that are numbers or booleans in YAML (`spark.executor.instances: 2`, `...enabled: true`) render as `2`/`true`, not `%!s(float64=2)` or `2e+00` → unittest in Task 1.
3. `auth.enabled` with `auth.existingSecret` set: chart must not create a Secret and must reference the user's key → unittest in Task 3.
4. Exposure enabled for `connect` while `auth.enabled=false`: NOTES.txt prints the warning → unittest in Task 3.
5. `historyServer.enabled=true` with empty `logDirectory`: render fails with a clear message → unittest in Task 5.

---

## File map

```
charts/spark-connect/
  Chart.yaml  values.yaml  values.schema.json  README.md(.gotmpl)  .helmignore
  ci/default-values.yaml  ci/all-on-values.yaml           # ct lint + kubeconform inputs
  templates/_helpers.tpl  NOTES.txt
  templates/configmap.yaml          # spark-defaults.conf, executor-pod-template.yaml, pools.xml, log4j2.properties, metrics.properties
  templates/driver.yaml             # Deployment
  templates/service.yaml
  templates/serviceaccounts.yaml    # driver + executor SAs
  templates/rbac.yaml               # driver Role + RoleBinding
  templates/auth-secret.yaml
  templates/ingress.yaml            # loops over connect/ui/historyServer
  templates/routes.yaml             # GRPCRoute + HTTPRoutes
  templates/history-server.yaml     # Deployment + Service
  templates/restart.yaml            # CronJob + SA + Role + RoleBinding
  templates/monitoring.yaml         # ServiceMonitor + PrometheusRule
  templates/extra-objects.yaml
  tests/*_test.yaml                 # helm-unittest, one per template
spark-versions.json                 # [{"spark": "4.0.4"}, ...] one row per line
Makefile                            # tools (into .bin/), lint, unittest, schema, docs, kubeconform, ct-lint, e2e
e2e/run.sh  e2e/gateway.yaml  e2e/client.py
scripts/discover.py  scripts/ensure_ci.sh  tests/test_discover.py
renovate.json  artifacthub-repo.yml  mkdocs.yml  docs/site/*.md  docs/site/requirements.txt
.github/workflows/ci.yml  discover.yml  release.yml  pages.yml
README.md  LICENSE  .gitignore
```

## Values interface (shared by Tasks 1–6)

Top-level keys in `values.yaml`; every key gets a `# --` helm-docs comment. Task 1 writes the whole file; later tasks only fill in their section's defaults if needed.

```yaml
image: {repository: apache/spark, tag: "", pullPolicy: IfNotPresent}
imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""
commonPodAnnotations: {}
commonPodLabels: {}
sparkConf:
  spark.sql.execution.pythonUDF.arrow.enabled: "false"
packages: []                 # Maven coordinates -> spark.jars.packages
pools: []                    # [{name, schedulingMode: FAIR, weight: 1, minShare: 0}] -> pools.xml when non-empty
log4j2: ""                   # full log4j2.properties text; empty = image default
metrics:
  enabled: false
  path: /metrics/prometheus
  serviceMonitor: {enabled: false, labels: {}, interval: 30s, relabelings: [], metricRelabelings: []}
  prometheusRule: {enabled: false, labels: {}, groups: []}
auth: {enabled: false, existingSecret: "", secretKey: token}
driver:
  cores: 1
  cpuRequest: 1000m
  memoryMiB: 1024
  memoryOverheadMiB: 512
  ephemeralStorage: ""        # optional request, e.g. 10Gi
  javaOptions: "-XX:+ExitOnOutOfMemoryError -XX:+UseG1GC"
  podAnnotations: {}
  podLabels: {}
  env: []
  volumes: []
  volumeMounts: []
  nodeSelector: {}
  affinity: {}
  tolerations: []
  topologySpreadConstraints: []
  priorityClassName: ""
  livenessProbe: {initialDelaySeconds: 60, periodSeconds: 30, timeoutSeconds: 10, failureThreshold: 6}
  readinessProbe: {initialDelaySeconds: 30, periodSeconds: 10, timeoutSeconds: 10, failureThreshold: 6}
executor:
  instances: 1
  cores: 1
  cpuRequest: 500m
  memoryMiB: 1024
  memoryOverheadMiB: 512
  ephemeralStorage: ""
  javaOptions: "-XX:+ExitOnOutOfMemoryError -XX:+UseG1GC"
  # podAnnotations podLabels env volumes volumeMounts nodeSelector affinity tolerations
  # topologySpreadConstraints priorityClassName: same shapes as driver
serviceAccount:
  driver: {create: true, name: "", annotations: {}}
  executor: {create: true, name: "", annotations: {}}
podSecurityContext: {runAsNonRoot: true, runAsUser: 185, runAsGroup: 185, fsGroup: 185, seccompProfile: {type: RuntimeDefault}}
securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
dnsConfig: {}
service: {type: ClusterIP, annotations: {}, ports: {connect: 15002, ui: 4040}}
ingress:
  connect:       {enabled: false, className: "", annotations: {}, hosts: [], tls: []}
  ui:            {enabled: false, className: "", annotations: {}, hosts: [], tls: []}
  historyServer: {enabled: false, className: "", annotations: {}, hosts: [], tls: []}
  # hosts: [{host: spark.example.com, paths: [{path: /, pathType: Prefix}]}]
gateway:
  connect:       {enabled: false, annotations: {}, parentRefs: [], hostnames: []}
  ui:            {enabled: false, annotations: {}, parentRefs: [], hostnames: [], matches: [{path: {type: PathPrefix, value: /}}]}
  historyServer: {enabled: false, annotations: {}, parentRefs: [], hostnames: [], matches: [{path: {type: PathPrefix, value: /}}]}
historyServer:
  enabled: false
  logDirectory: ""            # required when enabled
  conf: {}                    # extra spark.history.* properties
  daemonMemory: 1g
  port: 18080
  resources: {}
  # podAnnotations podLabels env volumes volumeMounts nodeSelector affinity tolerations: same shapes as driver
restart:
  enabled: false
  schedule: "0 5 * * 6"
  timeZone: ""
  image: {repository: registry.k8s.io/kubectl, tag: v1.37.2, pullPolicy: IfNotPresent}
extraObjects: []
```

Resource names (helpers in `_helpers.tpl`): `spark-connect.fullname` (Service), `<fullname>-driver` (Deployment, driver SA, Role, RoleBinding), `<fullname>-executor` (executor SA), `<fullname>-conf` (ConfigMap), `<fullname>-auth` (Secret), `<fullname>-connect` / `-ui` / `-history-server` (Ingress and routes), `<fullname>-history-server` (Deployment, Service), `<fullname>-restart` (CronJob, SA, Role, RoleBinding). Component label `app.kubernetes.io/component`: `driver`, `executor`, `history-server`, `restart`.

---

### Task 1: Scaffold, values, helpers and the Spark configuration ConfigMap

**Files:**
- Create: `LICENSE` (Apache-2.0 text), `.gitignore` (`.bin/`, `site/`, `e2e/out/`, `__pycache__/`, `charts/spark-connect/README.md`, `charts/spark-connect/values.schema.json`, `docs/site/values.md`), `README.md` (one-paragraph placeholder, finished in Task 9), `Makefile`, `spark-versions.json`
- Create: `charts/spark-connect/{Chart.yaml,values.yaml,.helmignore}`, `templates/_helpers.tpl`, `templates/configmap.yaml`
- Test: `charts/spark-connect/tests/configmap_test.yaml`

**Interfaces:**
- Produces helpers: `spark-connect.name`, `spark-connect.fullname`, `spark-connect.chart`, `spark-connect.labels`, `spark-connect.selectorLabels`, `spark-connect.image` (`repo:tag|appVersion`), `spark-connect.driverServiceAccountName`, `spark-connect.executorServiceAccountName`, `spark-connect.ownedConf` (dict of owned key → value), `spark-connect.podSecurityContext`, `spark-connect.containerSecurityContext`.
- Produces ConfigMap `<fullname>-conf`, mounted later at `/etc/spark-connect` with `SPARK_CONF_DIR=/etc/spark-connect`.
- Produces Makefile targets `tools`, `lint`, `unittest` (later tasks add more). `make tools` downloads pinned helm, helm-unittest (into `HELM_PLUGINS=.bin/plugins`), kind, kubectl, helm-docs, kubeconform, helm-values-schema-json into `.bin/`; every other target uses `.bin/` binaries.

- [ ] **Step 1:** `git init -b main`, set local identity, `git remote add origin git@github.com:sdaberdaku/spark-connect-chart.git`. Commit the spec and this plan first (`docs: add design and plan`).
- [ ] **Step 2: Write the failing tests** in `tests/configmap_test.yaml` (helm-unittest):
  - `renders owned keys`: default render, `spark-defaults.conf` contains lines `spark.master k8s://https://kubernetes.default.svc`, `spark.kubernetes.namespace NAMESPACE`, `spark.connect.grpc.binding.port 15002`, `spark.ui.port 4040`, `spark.kubernetes.executor.container.image apache/spark:4.2.0`, `spark.kubernetes.authenticate.driver.serviceAccountName RELEASE-NAME-spark-connect-driver`, `spark.kubernetes.authenticate.executor.serviceAccountName RELEASE-NAME-spark-connect-executor`, `spark.kubernetes.executor.podTemplateFile /etc/spark-connect/executor-pod-template.yaml`, `spark.kubernetes.executor.podTemplateContainerName executor`, `spark.driver.memory 1024m`, `spark.driver.memoryOverhead 512m`, `spark.executor.instances 1`, `spark.kubernetes.executor.request.cores 500m`, `spark.local.dir /var/data/spark-local`, `spark.jars.ivy /tmp/.ivy`.
  - `renders default sparkConf`: contains `spark.sql.execution.pythonUDF.arrow.enabled false`.
  - `renders numbers and booleans plainly`: set `sparkConf: {spark.foo.count: 2, spark.foo.on: true, spark.foo.big: 100000000}` → lines `spark.foo.count 2`, `spark.foo.on true`, `spark.foo.big 100000000`.
  - `templates sparkConf values`: `sparkConf: {spark.foo.ns: "{{ .Release.Namespace }}"}` → `spark.foo.ns NAMESPACE`.
  - `sorts sparkConf keys`: two keys given out of order appear sorted.
  - `fails on owned key`: `sparkConf: {spark.driver.memory: 4g}` → `failedTemplate` with message `sparkConf.spark.driver.memory is set by the chart; use driver.memoryMiB instead`.
  - `packages`: `packages: [a:b:1, c:d:2]` → `spark.jars.packages a:b:1,c:d:2`; empty list → no `spark.jars.packages` line.
  - `pools`: one pool → key `pools.xml` with `<pool name="large">`, `<weight>2</weight>`, and `spark.scheduler.allocation.file /etc/spark-connect/pools.xml`; empty → neither.
  - `log4j2`: non-empty → key `log4j2.properties` with the text; empty → no key.
  - `metrics`: `metrics.enabled` → key `metrics.properties` with `*.sink.prometheusServlet.class=org.apache.spark.metrics.sink.PrometheusServlet` and `*.sink.prometheusServlet.path=/metrics/prometheus`.
  - `executor pod template`: key `executor-pod-template.yaml` parses to a Pod with container name `executor`, `automountServiceAccountToken: false`, pod securityContext `runAsUser: 185`, container `readOnlyRootFilesystem: true`, an `emptyDir` mounted at `/tmp`, label `app.kubernetes.io/component: executor`, executor `nodeSelector`/`tolerations`/`affinity` passed through when set.
- [ ] **Step 3:** `make tools unittest` → the tests fail (templates missing).
- [ ] **Step 4: Implement.** `Chart.yaml` (`apiVersion: v2`, `name: spark-connect`, `type: application`, `version: 1.0.0`, `appVersion: "4.2.0"` with a `# renovate: datasource=docker depName=apache/spark` comment above it, `kubeVersion: ">=1.29.0-0"`, description, home `https://sdaberdaku.github.io/spark-connect-chart/`, sources, maintainers, keywords, annotations `artifacthub.io/license: Apache-2.0`). `values.yaml` exactly as the Values interface. Owned keys (each mapped to the value path named in the failure message): `spark.master`, `spark.kubernetes.namespace`, `spark.connect.grpc.binding.port` (service.ports.connect), `spark.ui.port` (service.ports.ui), `spark.driver.host`, `spark.kubernetes.driver.pod.name`, `spark.kubernetes.container.image`, `spark.kubernetes.executor.container.image` (image.*), `spark.kubernetes.container.image.pullPolicy`, `spark.kubernetes.authenticate.driver.serviceAccountName`, `spark.kubernetes.authenticate.executor.serviceAccountName` (serviceAccount.*), `spark.kubernetes.executor.podTemplateFile`, `spark.kubernetes.executor.podTemplateContainerName`, `spark.driver.cores`, `spark.driver.memory`, `spark.driver.memoryOverhead`, `spark.driver.extraJavaOptions` (driver.*), `spark.executor.cores`, `spark.executor.memory`, `spark.executor.memoryOverhead`, `spark.executor.extraJavaOptions`, `spark.executor.instances`, `spark.kubernetes.executor.request.cores` (executor.*), `spark.jars.packages` (packages), `spark.jars.ivy`, `spark.local.dir`, `spark.scheduler.allocation.file` (pools), `spark.connect.authenticate.token` (auth.*). Render values with `tpl (toString $v)` but convert floats that are whole numbers with `int64` first so `2` stays `2`. `spark-versions.json`: `[\n  {"spark": "4.0.4"},\n  {"spark": "4.1.3"},\n  {"spark": "4.2.0"}\n]` (one row per line; Renovate's regex depends on it). `.helmignore` excludes `tests/` and `ci/`.
- [ ] **Step 5:** `make unittest` → all pass; `make lint` (`helm lint charts/spark-connect`) → 0 failures.
- [ ] **Step 6:** Commit `feat: chart scaffold and Spark configuration`.

### Task 2: Driver Deployment, Service, ServiceAccounts, RBAC

**Files:**
- Create: `templates/driver.yaml`, `templates/service.yaml`, `templates/serviceaccounts.yaml`, `templates/rbac.yaml`, `templates/NOTES.txt` (port-forward instructions only; Task 3 adds the warning)
- Test: `tests/driver_test.yaml`, `tests/service_test.yaml`, `tests/rbac_test.yaml`

**Interfaces:**
- Consumes: Task 1 helpers and ConfigMap `<fullname>-conf`.
- Produces: Deployment `<fullname>-driver` with container named `driver`, env names `SPARK_DRIVER_POD_IP`, `SPARK_DRIVER_POD_NAME`; Service `<fullname>` with ports named `connect` (appProtocol `kubernetes.io/h2c`) and `ui`; selector labels plus `app.kubernetes.io/component: driver`.

- [ ] **Step 1: Write the failing tests:**
  - driver: `replicas: 1`, `strategy.type: Recreate`; `command: [/opt/entrypoint.sh]`, `args: [/opt/spark/sbin/start-connect-server.sh, --conf, spark.driver.host=$(SPARK_DRIVER_POD_IP), --conf, spark.kubernetes.driver.pod.name=$(SPARK_DRIVER_POD_NAME)]`; env contains `SPARK_CONF_DIR=/etc/spark-connect`, `SPARK_NO_DAEMONIZE=true`, `SPARK_LOG_DIR=/tmp/spark-logs`, `SPARK_PID_DIR=/tmp`; volume mounts `/etc/spark-connect` (ConfigMap, readOnly), `/tmp`, `/var/data/spark-local`, `/opt/spark/work-dir` (emptyDirs); resources `requests.cpu: 1000m`, `requests.memory: 1536Mi`, `limits.memory: 1536Mi`, no cpu limit; `ephemeral-storage` request only when `driver.ephemeralStorage` set; liveness and readiness `httpGet` on port `ui` path `/` with the values' timings; `preStop` exec `/opt/spark/sbin/stop-connect-server.sh`; pod annotation `checksum/config` present and changes when `sparkConf` changes; pod and container security contexts equal the values; `serviceAccountName: RELEASE-NAME-spark-connect-driver`; `driver.env`, `volumes`, `volumeMounts`, `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `priorityClassName`, `dnsConfig`, `imagePullSecrets`, common and driver pod labels/annotations passed through; no `affinity` key by default.
  - long names: release name of 50 chars → every rendered `metadata.name` ≤ 63 chars, RoleBinding `subjects[0].name` equals the driver SA name and `roleRef.name` equals the Role name.
  - service: type ClusterIP, ports `connect` 15002 → targetPort `connect` with `appProtocol: kubernetes.io/h2c`, `ui` 4040 → `ui`; annotations passed through.
  - serviceaccounts: two SAs; driver `automountServiceAccountToken: true`; executor `automountServiceAccountToken: false`; `create: false` on either → that SA not rendered and the helper returns `name` (or `default`).
  - rbac: Role rules exactly: `pods` [create get list watch delete deletecollection patch], `services` [create get list watch delete deletecollection], `configmaps` [create get list watch delete deletecollection], `persistentvolumeclaims` [create get list watch delete deletecollection]; no `*` verbs; bound only to the driver SA; not rendered when `serviceAccount.driver.create=false`.
- [ ] **Step 2:** `make unittest` → new tests fail.
- [ ] **Step 3:** Implement the four templates and NOTES.txt (`kubectl port-forward svc/<fullname> 15002:15002` and `sc://localhost:15002`). Pod memory = `memoryMiB + memoryOverheadMiB` Mi. The driver also passes `spark.kubernetes.authenticate.submission.caCertFile` and `oauthTokenFile` from the mounted SA token path only if the e2e in Task 7 shows they are needed; do not add them speculatively.
- [ ] **Step 4:** `make unittest lint` → pass. `helm template x charts/spark-connect | .bin/kubeconform -strict -summary` → valid.
- [ ] **Step 5:** Commit `feat: driver deployment, service, service accounts and RBAC`.

### Task 3: Connect token

**Files:**
- Create: `templates/auth-secret.yaml`; Modify: `templates/driver.yaml`, `templates/NOTES.txt`
- Test: `tests/auth_test.yaml`

**Interfaces:**
- Consumes: driver container `driver`.
- Produces: Secret `<fullname>-auth` with key `auth.secretKey` (default `token`); driver env `SPARK_CONNECT_AUTHENTICATE_TOKEN` from `secretKeyRef`.

- [ ] **Step 1: Write the failing tests:**
  - `auth.enabled=false` → no Secret, no `SPARK_CONNECT_AUTHENTICATE_TOKEN` env.
  - `auth.enabled=true` → Secret `RELEASE-NAME-spark-connect-auth` with a 32-char token under `token`; driver env `SPARK_CONNECT_AUTHENTICATE_TOKEN` → `secretKeyRef {name: RELEASE-NAME-spark-connect-auth, key: token}`; `spark-defaults.conf` does not contain `authenticate.token`.
  - `auth.enabled=true, existingSecret: mine, secretKey: k` → no Secret rendered, env references `mine`/`k`.
  - NOTES: `ingress.connect.enabled=true` (or `gateway.connect.enabled=true`) with `auth.enabled=false` → output contains `WARNING: the Spark Connect endpoint is exposed without authentication`; with auth on → no warning, and a line explaining the client needs TLS in front (`sc://<host>:443/;use_ssl=true;token=...`).
- [ ] **Step 2:** `make unittest` → fail.
- [ ] **Step 3:** Implement. Generated token: reuse the existing Secret's value via `lookup` when present, else `randAlphaNum 32`. The server reads the env var (the 4.2.0 jar's `Connect$` references `SPARK_CONNECT_AUTHENTICATE_TOKEN`). If Task 7's e2e shows a Spark line that ignores the env var, add `--conf spark.connect.authenticate.token=$(SPARK_CONNECT_AUTHENTICATE_TOKEN)` to the args when auth is on (Kubernetes expands it at start; the pod spec keeps the literal) and update this test.
- [ ] **Step 4:** `make unittest` → pass.
- [ ] **Step 5:** Commit `feat: optional Spark Connect token`.

### Task 4: Ingress and Gateway API exposure

**Files:**
- Create: `templates/ingress.yaml`, `templates/routes.yaml`
- Test: `tests/ingress_test.yaml`, `tests/routes_test.yaml`

**Interfaces:**
- Consumes: Service `<fullname>` ports `connect`/`ui` (Task 2); history server Service `<fullname>-history-server` port `http` = `historyServer.port` (Task 5 creates it; the routes reference it by name and port number).
- Produces: Ingress `<fullname>-<endpoint>`, GRPCRoute `<fullname>-connect`, HTTPRoute `<fullname>-ui` / `<fullname>-history-server`.

- [ ] **Step 1: Write the failing tests:**
  - Everything off by default → no Ingress, GRPCRoute or HTTPRoute.
  - Ingress per endpoint: `className` → `ingressClassName`; annotations, hosts/paths (default `pathType: Prefix` when absent), tls passed through; backend `connect` → service `RELEASE-NAME-spark-connect` port name `connect`; `ui` → port name `ui`; `historyServer` → service `RELEASE-NAME-spark-connect-history-server` port name `http`.
  - GRPCRoute: `apiVersion: gateway.networking.k8s.io/v1`, `parentRefs` incl. `sectionName` passed through verbatim, `hostnames`, annotations, one rule with `backendRefs: [{name: RELEASE-NAME-spark-connect, port: 15002}]`.
  - HTTPRoutes: `matches` from values, backendRefs `ui` → 4040, `historyServer` → 18080.
  - Both Ingress and GRPCRoute enabled for `connect` → both rendered.
  - `gateway.connect.enabled=true` with empty `parentRefs` → `failedTemplate` with `gateway.connect.parentRefs is required`.
- [ ] **Step 2:** `make unittest` → fail.
- [ ] **Step 3:** Implement with one `range` over the three endpoints per file; no controller-specific annotations anywhere.
- [ ] **Step 4:** `make unittest` → pass.
- [ ] **Step 5:** Commit `feat: Ingress and Gateway API exposure`.

### Task 5: History server, scheduled restart, monitoring, extraObjects

**Files:**
- Create: `templates/history-server.yaml`, `templates/restart.yaml`, `templates/monitoring.yaml`, `templates/extra-objects.yaml`
- Test: `tests/history_server_test.yaml`, `tests/restart_test.yaml`, `tests/monitoring_test.yaml`, `tests/extra_objects_test.yaml`

**Interfaces:**
- Consumes: helpers, executor SA (history server uses it: storage identity, no API rights).
- Produces: Service `<fullname>-history-server` port name `http` = `historyServer.port`.

- [ ] **Step 1: Write the failing tests:**
  - history server off by default. On with `logDirectory: file:/spark-events` → Deployment (container `history-server`, command `/opt/entrypoint.sh /opt/spark/sbin/start-history-server.sh`, env `SPARK_NO_DAEMONIZE=true`, `SPARK_LOG_DIR=/tmp/spark-logs`, `SPARK_PID_DIR=/tmp`, `SPARK_DAEMON_MEMORY=1g`, `SPARK_HISTORY_OPTS` containing `-Dspark.history.fs.logDirectory=file:/spark-events -Dspark.history.ui.port=18080` plus each `historyServer.conf` entry sorted), restricted security contexts, `/tmp` emptyDir, `serviceAccountName` = executor SA, probes on port `http`, volumes/volumeMounts/env passed through; Service port `http` 18080. On with empty `logDirectory` → `failedTemplate` `historyServer.logDirectory is required`.
  - restart off by default. On → CronJob `RELEASE-NAME-spark-connect-restart` with `schedule: "0 5 * * 6"`, `timeZone` only when set, `concurrencyPolicy: Forbid`, image `registry.k8s.io/kubectl:v1.37.2`, args `[rollout, restart, deployment/RELEASE-NAME-spark-connect-driver]`, restricted security contexts; Role with one rule `apps/deployments`, `resourceNames: [RELEASE-NAME-spark-connect-driver]`, verbs `[get, patch]`; SA + RoleBinding.
  - monitoring: ServiceMonitor only when `metrics.enabled` and `metrics.serviceMonitor.enabled`; endpoint `port: ui`, `path: /metrics/prometheus`, interval, relabelings; selector = driver selector labels. PrometheusRule only when its `enabled` and `groups` passed verbatim.
  - extraObjects: a list with one ConfigMap whose name is `'{{ include "spark-connect.fullname" . }}-x'` renders `RELEASE-NAME-spark-connect-x`.
- [ ] **Step 2:** `make unittest` → fail.
- [ ] **Step 3:** Implement. Put the kubectl `tag` under a `# renovate: datasource=docker depName=registry.k8s.io/kubectl` comment in `values.yaml`.
- [ ] **Step 4:** `make unittest lint` → pass.
- [ ] **Step 5:** Commit `feat: history server, scheduled restart, monitoring and extra objects`.

### Task 6: Static checks: schema, generated README, kubeconform, chart-testing

**Files:**
- Create: `charts/spark-connect/README.md.gotmpl` (README and `values.schema.json` are generated, not committed), `charts/spark-connect/ci/default-values.yaml` (empty map), `charts/spark-connect/ci/all-on-values.yaml`, `ct.yaml`
- Modify: `Makefile`, `values.yaml` (schema annotations only where inference is wrong)

**Interfaces:**
- Produces Makefile targets: `schema`, `docs` (helm-docs), `kubeconform`, `ct-lint`, `package`, `check` (= lint unittest kubeconform versions-check, each depending on `schema docs`). `versions-check` asserts `appVersion` equals the highest `spark` in `spark-versions.json`.

- [ ] **Step 1:** Write `ci/all-on-values.yaml`: auth on, every Ingress and Gateway endpoint on (parentRefs `[{name: eg, sectionName: https}]`, a host), history server on (`logDirectory: file:/spark-events`), restart on, metrics + ServiceMonitor + PrometheusRule (one dummy rule) on, pools one entry, `log4j2` set, one `extraObjects` ConfigMap.
- [ ] **Step 2:** Add targets. `schema`: helm-values-schema-json plugin generating `values.schema.json` from `values.yaml` (draft 7, `additionalProperties: false` at the top level only). `docs`: `helm-docs --chart-search-root charts`, then copy the chart README to `docs/site/values.md`. `lint`, `unittest`, `kubeconform`, `ct-lint` and `package` depend on `schema docs`. `kubeconform`: render default and all-on values, validate with `-strict -summary -kubernetes-version` for each of the last three Kubernetes minors available in the kubeconform schema repo, `-schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'`. `ct-lint`: `docker run` the pinned `quay.io/helmpack/chart-testing` image with `ct lint --config ct.yaml` (`chart-dirs: [charts]`, `target-branch: main`, `validate-maintainers: false`, `check-version-increment: true`).
- [ ] **Step 3:** README.md.gotmpl: title, description, no version or appVersion badges (the generated file must not depend on versions), Artifact Hub badge added in Task 10, install line `helm install spark-connect oci://ghcr.io/sdaberdaku/charts/spark-connect --version <version>`, link to the docs site, then `{{ template "chart.valuesSection" . }}`.
- [ ] **Step 4:** `make check` → passes (schema rejects `{"foo": 1}` at the top level: verify with `helm template x charts/spark-connect --set foo=1` → error mentioning `additional properties`).
- [ ] **Step 5:** Commit `chore: schema, generated README and static checks`.

### Task 7: End-to-end test on kind

**Files:**
- Create: `e2e/run.sh`, `e2e/gateway.yaml`, `e2e/client.py`; Modify: `Makefile` (`e2e` target), maybe templates/tests per Step 5.

**Interfaces:**
- Consumes: the chart; `spark-versions.json`.
- Produces: `SPARK_VERSION=<x.y.z> make e2e` (default: appVersion); env `KEEP_CLUSTER=1` keeps the cluster; on failure dumps pods, events, describe and logs to `e2e/out/`.

- [ ] **Step 1: Write `e2e/client.py`** (stdlib + pyspark): args `--remote <url>` and `--expect-auth-failure`. Normal run: `spark.range(0, 1000, numPartitions=4)`, a plain `@udf("long")` adding 1, assert `sum == 500500`; print `E2E OK`. With `--expect-auth-failure`: the first action must raise an exception whose text contains `UNAUTHENTICATED` (or `Unauthenticated`); exit 0 only then.
- [ ] **Step 2: Write `e2e/run.sh`** (bash, `set -euo pipefail`, trap that dumps on failure):
  1. Pinned values with Renovate comments: `KIND_NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5`, `ENVOY_GATEWAY_VERSION=v1.9.3`.
  2. `docker pull apache/spark:$SPARK_VERSION`; read the image's Python minor with `docker run --rm --entrypoint python3 apache/spark:$SPARK_VERSION -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")'`.
  3. `kind create cluster --name spark-connect-e2e --image $KIND_NODE_IMAGE --wait 120s`; `kind load docker-image apache/spark:$SPARK_VERSION`.
  4. `helm install eg oci://docker.io/envoyproxy/gateway-helm --version $ENVOY_GATEWAY_VERSION -n envoy-gateway-system --create-namespace --wait`.
  5. Namespace `spark` labelled `pod-security.kubernetes.io/enforce=restricted`. Self-signed cert with SAN `DNS:localhost` (openssl) → TLS secret `e2e-tls` in `spark`. Apply `e2e/gateway.yaml`: GatewayClass `eg` (`gateway.envoyproxy.io/gatewayclass-controller`), Gateway `eg` in `spark` with listener `https` port 443 protocol HTTPS, TLS terminate with `e2e-tls`, no hostname. Wait for `Programmed`.
  6. Release without token: `helm install sc charts/spark-connect -n spark --set image.tag=$SPARK_VERSION --wait --timeout 10m`. Port-forward `svc/sc-spark-connect 15002`. Run the client with `uv run --python <minor> --with pyspark-client==$SPARK_VERSION e2e/client.py --remote sc://localhost:15002`. Assert at least one pod with `spark-role=executor` exists in `spark`.
  7. `helm upgrade sc ... --set auth.enabled=true --set gateway.connect.enabled=true --set 'gateway.connect.parentRefs[0].name=eg' --set 'gateway.connect.parentRefs[0].sectionName=https' --wait`. Find the Envoy Service by label `gateway.envoyproxy.io/owning-gateway-name=eg` in `envoy-gateway-system`; port-forward it to `localhost:8443`. Read the token from Secret `sc-spark-connect-auth`. With `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=<cert>`, run the client against `sc://localhost:8443/;use_ssl=true;token=<token>` (expects `E2E OK`) and against `sc://localhost:8443/;use_ssl=true` with `--expect-auth-failure`.
  8. Delete the cluster unless `KEEP_CLUSTER=1` or `CI` is set.
- [ ] **Step 3:** `SPARK_VERSION=4.2.0 make e2e` locally → passes. Then `SPARK_VERSION=4.0.4 make e2e` → passes (oldest line, checks the token env var path).
- [ ] **Step 4:** Fix what the e2e reveals in the chart, never by loosening the restricted profile or `readOnlyRootFilesystem` (add emptyDir mounts instead), and pin each fix with a unittest. Likely spots: writable paths for `spark-daemon.sh` and Python workers, Role verbs, the token on 4.0.
- [ ] **Step 5:** `make check` still passes. Commit `test: end-to-end test on kind with Envoy Gateway`.

### Task 8: CI, Renovate, discovery; first push and branch protection

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/discover.yml`, `scripts/discover.py`, `scripts/ensure_ci.sh`, `tests/test_discover.py`, `renovate.json`

**Interfaces:**
- Produces: required check `ci-ok`; `python3 scripts/discover.py [--dry-run]` prints one line per added Spark line (`spark 4.3`) and edits `spark-versions.json` and, when the newest line changes, `Chart.yaml` (`appVersion` and `version`).

- [ ] **Step 1: Write the failing tests** `tests/test_discover.py` (unittest, pure functions, no network): `discover(rows, tags, app_version, chart_version) -> (rows, app_version, chart_version, added)`.
  - `new minor line`: rows 4.0.4/4.1.3/4.2.0, tags include `4.3.0`, `4.3.1` → row `4.3.1` appended, app `4.3.1`, chart `1.0.0 → 1.1.0`, added `["spark 4.3"]`.
  - `new major line`: tags include `5.0.0` → row `5.0.0`, app `5.0.0`, chart `1.4.2 → 2.0.0`.
  - `two new lines`: `4.3.0` and `5.0.0` → both rows, app `5.0.0`, chart major bump once.
  - `patch of known line ignored`: `4.2.1` → no change (Renovate's job).
  - `old or odd tags ignored`: `3.5.9`, `4.3.0-python3`, `latest`, `4.3.0-scala2.13-java17-ubuntu` → no change.
  - `new line older than default`: rows without 4.1, tags `4.1.3` → row added, app and chart unchanged.
  - `serialize`: one row per line, matches the Task 1 layout exactly.
- [ ] **Step 2:** `python3 -m unittest discover -s tests` → fail.
- [ ] **Step 3: Implement `scripts/discover.py`** (stdlib): fetch `https://hub.docker.com/v2/repositories/apache/spark/tags?page_size=100` with pagination and one retry; plain tags `^\d+\.\d+\.\d+$`; lines `>= (4, 0)` not in rows; edit `Chart.yaml` by regex on the `version:` and `appVersion:` lines only (keep comments); env hook `DISCOVER_FAKE_TAGS` (comma-separated) appended to fetched tags for rehearsals.
- [ ] **Step 4: `ci.yml`** (triggers: pull_request opened/synchronize/reopened/ready_for_review, push to main, workflow_dispatch; concurrency per ref, cancel on PRs; `permissions: contents: read`):
  - `plan`: skipped for draft PRs; outputs the matrix from `spark-versions.json`.
  - `static` (needs plan): checkout with `fetch-depth: 0`, `make tools check`, `python3 -m unittest discover -s tests`, and on pull_request or workflow_dispatch from a non-main ref `make ct-lint`.
  - `docs` (needs plan): `make tools docs`, `pip install -r docs/site/requirements.txt` and `mkdocs build --strict` (Task 9 adds the site; until then the job runs `test ! -f mkdocs.yml || mkdocs build --strict`).
  - `e2e` (needs plan, matrix rows, `fail-fast: false`, timeout 45 min): `make tools`, `astral-sh/setup-uv`, `SPARK_VERSION=${{ matrix.spark }} make e2e`, upload `e2e/out` on failure.
  - `ci-ok` (`needs: [static, docs, e2e]`, `if: always()`): fails unless all results are `success`.
  - Pin every action to its current major; tool versions come from the Makefile.
- [ ] **Step 5: `discover.yml`** (daily `cron: "0 5 * * *"`, workflow_dispatch with input `dry_run`; `permissions: contents write, pull-requests write, actions write`): (1) if `v$(chart version on main)` is not a tag, `gh workflow run release.yml --ref main` (skip silently while `release.yml` does not exist yet); (2) repair an open `discover/*` PR (rebase when BEHIND, close and redo when DIRTY and all commits are the bot's, else fail), run `scripts/ensure_ci.sh <branch>`, enable auto-merge, and stop; (3) otherwise run `discover.py`; if it added lines, commit on `discover/<yyyymmdd>` as `github-actions[bot]`, push, open the PR (`feat: add Spark <lines>`; body says CI decides and the PR merges itself when green), run `ensure_ci.sh`, `gh pr merge --auto --squash --delete-branch`. `scripts/ensure_ci.sh`: wait up to 90 s for a `ci.yml` run on the PR head SHA, else `gh workflow run ci.yml --ref <branch>`.
- [ ] **Step 6: `renovate.json`:** `extends: ["config:recommended"]`, `enabledManagers: ["github-actions", "pip_requirements", "custom.regex"]`, `platformAutomerge: true`, `automerge: true` for all update types (CI is the gate), `labels: ["dependencies"]`, `schedule: ["before 6am on monday"]` except `apache/spark` (no schedule). Custom regex managers: (a) generic `# renovate: datasource=(?<datasource>\S+) depName=(?<depName>\S+)( versioning=(?<versioning>\S+))?\n[^\n]*?(?<currentValue>v?\d[\w.+-]*)(@(?<currentDigest>sha256:[a-f0-9]+))?` over `Makefile`, `e2e/run.sh`, `charts/spark-connect/Chart.yaml`, `charts/spark-connect/values.yaml`, `.github/workflows/*.yml`; (b) `spark-versions.json` rows `"spark": "(?<currentValue>\d+\.\d+\.\d+)"`, datasource docker, depName `apache/spark`. Package rule for `apache/spark`: only `patch` updates enabled (lines come from discovery), `groupName: "spark"` so `appVersion` and its `spark-versions.json` row move in one PR (the versions check requires it). Chart version bump: `bumpVersions` with `filePatterns: ["{{packageFileDir}}/Chart.yaml"]`, `matchStrings: ["version:\\s(?<version>\\S+)"]`, `bumpType: patch`, which only fires when the updated file sits next to `Chart.yaml` (appVersion, the kubectl tag); check the option against the current Renovate docs and run `npx --yes --package renovate -- renovate-config-validator renovate.json` → valid.
- [ ] **Step 7:** `make check` and `python3 -m unittest discover -s tests` pass locally. Commit `ci: CI, discovery and Renovate`.
- [ ] **Step 8: First push.** `git push -u origin main`. Watch the `ci` run on main (`gh run watch`) until every e2e row and `ci-ok` are green; fix forward with commits pushed to main until green (protection is not on yet).
- [ ] **Step 9: Protect `main`** with the same settings as the owner's other repos: required status check `ci-ok` (strict), linear history, enforce admins, force pushes allowed for the owner only, no required reviews (`gh api -X PUT repos/sdaberdaku/spark-connect-chart/branches/main/protection ...`). From here on every change goes through a PR that merges on green.
- [ ] **Step 10:** Rehearse discovery: `gh workflow run discover.yml -f dry_run=true` → run succeeds and logs nothing to add.

### Task 9: Documentation site and README

**Files:**
- Create: `mkdocs.yml`, `docs/site/requirements.txt` (`mkdocs`, `mkdocs-material`, pinned), `docs/site/{index,quickstart,configuration,exposure,python,security,operations,development}.md`, `.github/workflows/pages.yml`; Modify: `README.md`, `ci.yml` (docs job as final).

- [ ] **Step 1:** Write pages per the spec's Documentation section. Exposure includes: ingress-nginx and Traefik gRPC Ingress examples, an Envoy Gateway GRPCRoute example, and the AWS Load Balancer Controller `TargetGroupConfiguration` (gRPC health check, `matcher.grpcCode: "12"`, path `/`) passed through `extraObjects`. Python page: Python versions of the stock images per line (read them from the images), the arrow default and when to flip it, `ghcr.io/sdaberdaku/spark` as the image with pandas/pyarrow. Security: token, TLS in front, port-forward stays unauthenticated, executor SA without API rights, restricted PSS. Operations: upgrades (Recreate), restart CronJob, metrics, history server on a shared PVC (example with `driver.volumes`/`sparkConf` `spark.eventLog.*` and `historyServer.volumes`), and that object stores need connector jars in the image. Development: `make` targets, the release flow. The values reference page `values.md` is the generated chart README (`make docs` before `mkdocs build`, in CI and Pages).
- [ ] **Step 2:** `pages.yml`: on push to main touching `docs/site/**`, `mkdocs.yml`, `charts/spark-connect/README.md`, and on workflow_dispatch; build with `--strict`, deploy with `actions/upload-pages-artifact` + `actions/deploy-pages`. Enable Pages with the workflow source: `gh api -X POST repos/sdaberdaku/spark-connect-chart/pages -f build_type=workflow`.
- [ ] **Step 3:** Root `README.md`: what it is, install from OCI, a kind quickstart pointer, feature list, docs and Artifact Hub links, license.
- [ ] **Step 4:** `mkdocs build --strict` locally (uv) → no warnings. Commit `docs: documentation site`, open a PR, wait for `ci-ok`, merge (squash). Pages run succeeds; `https://sdaberdaku.github.io/spark-connect-chart/` loads.

### Task 10: Release workflow and first release 1.0.0

**Files:**
- Create: `.github/workflows/release.yml`, `artifacthub-repo.yml`; Modify: `charts/spark-connect/Chart.yaml` annotations, `README.md.gotmpl` badge (only after the repo is registered on Artifact Hub; until then no badge).

**Interfaces:**
- Produces: tag `v<version>`, OCI artifact `oci://ghcr.io/sdaberdaku/charts/spark-connect:<version>`, GitHub Release with `spark-connect-<version>.tgz`, OCI tag `artifacthub.io` holding `artifacthub-repo.yml`.

- [ ] **Step 1: `release.yml`** (on push to main, push of tags `v*`, workflow_dispatch; concurrency `release`, no cancel; `permissions: contents: write, packages: write, actions: write`): read `version` from `Chart.yaml` at the ref; on a tag push require `tag == v<version>`; on other events exit 0 when tag `v<version>` exists, else create and push it. Then `make tools schema docs package` (the package carries the generated README and schema), `helm registry login ghcr.io` with `GITHUB_TOKEN`, `helm push spark-connect-<version>.tgz oci://ghcr.io/sdaberdaku/charts`, `oras push ghcr.io/sdaberdaku/charts/spark-connect:artifacthub.io --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml`, `gh release create v<version> spark-connect-<version>.tgz --generate-notes` (skip when it exists), `gh workflow run pages.yml --ref main`.
- [ ] **Step 2:** `artifacthub-repo.yml` with `owners: [{name: Sebastian Daberdaku, email: sebastiandaberdaku@gmail.com}]` (no `repositoryID` until registration). Chart annotations: `artifacthub.io/license`, `artifacthub.io/links` (source, docs).
- [ ] **Step 3:** PR `ci: release workflow`, wait for `ci-ok`, merge. The merge push runs `release.yml` and publishes `1.0.0`.
- [ ] **Step 4: Verify the release:** tag `v1.0.0` exists; GitHub Release has the `.tgz`; `helm show chart oci://ghcr.io/sdaberdaku/charts/spark-connect --version 1.0.0` works without login (package public). If GHCR made the package private, report it to the owner (visibility can only be changed in the UI) and continue. Install the published chart on a fresh kind cluster (`helm install sc oci://ghcr.io/sdaberdaku/charts/spark-connect --version 1.0.0 -n spark --create-namespace --wait`) and run `e2e/client.py` over port-forward → `E2E OK`.
- [ ] **Step 5:** Docs site shows the values page; README links resolve.

### Task 11: Wrap-up (drafts only, nothing pushed outside this repo)

- [ ] **Step 1:** Draft (do not push) for `sdaberdaku/charts`: `spark-connect` 2.0.1 with `deprecated: true` in `Chart.yaml` and a README note pointing to `oci://ghcr.io/sdaberdaku/charts/spark-connect`. Save as a patch in the scratchpad and describe it to the owner.
- [ ] **Step 2:** Draft (do not push) a profile README line for `spark-connect-chart`.
- [ ] **Step 3:** Owner's manual follow-ups to report: register the repo on Artifact Hub (then add `repositoryID` to `artifacthub-repo.yml` and the badge in a PR), GHCR visibility if it came out private.
