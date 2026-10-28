# Configuration

The full list of values is in the [values reference](values.md). This page covers the parts that need an explanation.

## Sizing

Driver and executor sizes are set once:

```yaml
driver:
  cores: 2
  cpuRequest: 1000m
  memoryMiB: 4096
  memoryOverheadMiB: 1024
  ephemeralStorage: 10Gi
executor:
  instances: 4
  cores: 2
  cpuRequest: 1500m
  memoryMiB: 8192
  memoryOverheadMiB: 2048
```

The chart renders `spark.driver.cores`, `spark.driver.memory`, `spark.driver.memoryOverhead` and the matching executor properties from these values, and sets the pod resource requests and limits from the same numbers. The memory request and limit are both heap plus overhead. There is no CPU limit, and the CPU request is separate from the core count, so a pod can be scheduled with a smaller CPU request than the number of cores Spark uses.

`executor.instances` is a fixed number of executors (`spark.executor.instances`). For dynamic allocation, set the `spark.dynamicAllocation.*` properties in `sparkConf` and `spark.dynamicAllocation.shuffleTracking.enabled: "true"`, since executors on Kubernetes have no external shuffle service.

## sparkConf

`sparkConf` is a map of Spark property to value, rendered sorted into `spark-defaults.conf`. String values go through `tpl`, so `{{ .Release.Namespace }}` works.

```yaml
sparkConf:
  spark.sql.execution.pythonUDF.arrow.enabled: "false"
  spark.sql.shuffle.partitions: "64"
  spark.sql.catalog.lake: org.apache.iceberg.spark.SparkCatalog
```

The chart owns some properties itself (master URL, namespace, ports, driver host, image, service accounts, pod template, the sizes above, `spark.jars.packages`, the scheduler allocation file and the token). If `sparkConf` sets one of them, the render fails with a message that names the value to use instead, or says that the property cannot be overridden.

Property names contain dots, and Helm reads a dot in `--set` as a level of nesting. Escape the dots of the key on the command line:

```console
helm upgrade spark-connect oci://ghcr.io/sdaberdaku/charts/spark-connect --reuse-values \
  --set 'sparkConf.spark\.sql\.shuffle\.partitions=64'
```

Without the escapes the chart's schema refuses the value, because it would be a map. Values must be strings, numbers or booleans. Backslashes in a value are escaped for you, and a value with a newline fails the render. `historyServer.conf` follows the same rules.

The default `sparkConf` contains one entry, `spark.sql.execution.pythonUDF.arrow.enabled: "false"`. See [Python](python.md) for why. If you set `sparkConf` in your own values, Helm merges maps, so the default stays unless you override it.

## Packages and jars

`packages` is a list of Maven coordinates, rendered as `spark.jars.packages`. The driver resolves them at start and ships them to executors.

```yaml
image:
  tag: 4.1.3
packages:
  - org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.12.0
```

The Spark minor in the Iceberg artifact name has to be the Spark minor of the server. Iceberg publishes runtimes for Spark 4.0 and 4.1 and none for 4.2 yet (checked on 2026-10-28), so the example runs Spark 4.1.3. See [Running Spark 4.0 or 4.1](#running-spark-40-or-41).

The Ivy cache is on an emptyDir under `/tmp`, so resolution happens again on every driver start and needs network access to Maven Central or your mirror.

For jars you do not want to download at start, build an image, or mount them. Mounting a jar into the driver is not enough: Spark only loads jars that are on the class path, so also list it in `spark.jars` (or add it to `spark.driver.extraClassPath`). The driver runs in client mode and serves local `spark.jars` paths to the executors through its file server, so a jar mounted on the driver and listed in `spark.jars` reaches the executors without an executor mount or a shared URL.

## Running Spark 4.0 or 4.1

The chart version follows the newest Spark line, so `appVersion` is the Spark 4.2 release. To run an older line set the image tag, and use a PySpark client of the same version:

```yaml
image:
  tag: 4.1.3
```

The chart is tested against the newest patch of every supported line, which are the rows of `spark-versions.json` in the repository. Install the client with `pyspark-client==4.1.3` to match.

## FAIR scheduler pools

`pools` renders a `pools.xml` and sets `spark.scheduler.allocation.file`:

```yaml
sparkConf:
  spark.scheduler.mode: FAIR
pools:
  - name: interactive
    schedulingMode: FAIR
    weight: 2
    minShare: 2
  - name: batch
    schedulingMode: FAIR
    weight: 1
    minShare: 0
```

Pools only take effect when `spark.scheduler.mode` is `FAIR`, which the chart does not set for you. Clients choose a pool per session with `spark.conf.set("spark.scheduler.pool", "interactive")`.

## Logging

`log4j2` takes the full text of a `log4j2.properties` file. An empty value keeps the image default.

## Metrics

`metrics.enabled` writes a `metrics.properties` with the Prometheus servlet sink, served on the UI port at `metrics.path` (default `/metrics/prometheus`). `metrics.serviceMonitor.enabled` creates a ServiceMonitor for the driver Service, and `metrics.prometheusRule.enabled` creates a PrometheusRule from the rule groups you give in `metrics.prometheusRule.groups`. Both need the Prometheus Operator CRDs.

## Placement and extras

The driver, executors and history server each take `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `priorityClassName`, `podAnnotations`, `podLabels`, `env`, `volumes` and `volumeMounts`. The scheduled restart takes `resources`, `nodeSelector` and `tolerations`. Executors use the driver image unless `executor.image.repository` or `executor.image.tag` is set. `commonPodAnnotations` and `commonPodLabels` apply to every pod. There is no default affinity.

`extraObjects` is a list of extra manifests, each a map or a string, rendered with `tpl`:

```yaml
extraObjects:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: "{{ .Release.Name }}-extra"
    data:
      key: value
```
