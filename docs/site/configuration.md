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

The chart owns some properties itself (master URL, namespace, ports, driver host, image, service accounts, pod template, the sizes above, `spark.jars.packages`, the scheduler allocation file and the token). If `sparkConf` sets one of them, the render fails with a message that names the value to use instead.

The default `sparkConf` contains one entry, `spark.sql.execution.pythonUDF.arrow.enabled: "false"`. See [Python](python.md) for why. If you set `sparkConf` in your own values, Helm merges maps, so the default stays unless you override it.

## Packages and jars

`packages` is a list of Maven coordinates, rendered as `spark.jars.packages`. The driver resolves them at start and ships them to executors.

```yaml
packages:
  - org.apache.iceberg:iceberg-spark-runtime-4.0_2.13:1.10.0
```

The Ivy cache is on an emptyDir under `/tmp`, so resolution happens again on every driver start and needs network access to Maven Central or your mirror. For jars you do not want to download at start, build an image or mount them with `driver.volumes` and `driver.volumeMounts`.

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

The driver, executors and history server each take `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints` (driver and executor), `priorityClassName` (driver and executor), `podAnnotations`, `podLabels`, `env`, `volumes` and `volumeMounts`. `commonPodAnnotations` and `commonPodLabels` apply to every pod. There is no default affinity.

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
