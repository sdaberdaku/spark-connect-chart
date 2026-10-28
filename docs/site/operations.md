# Operations

## Upgrades

The driver is a Deployment with one replica and the `Recreate` strategy, so two Connect servers never run at the same time. An upgrade stops the old driver, then starts the new one. Client sessions end during that window and executors are recreated by the new driver. Plan upgrades for a quiet time, and expect sessions to reconnect from scratch.

Changes to `sparkConf`, pools, log4j2 or the metrics configuration change checksum annotations on the pod template, so the driver restarts on `helm upgrade` when they change.

The chart version has its own semver. A new Spark patch of the default line is a chart patch, a new Spark minor line is a chart minor, and a new Spark major line is a chart major, since upgrading the chart then moves the server to a new Spark major. Clients need the matching `pyspark-client` version.

## Scheduled restart

A long-running Connect server accumulates state (session class loaders, JIT code cache). A CronJob that restarts the driver clears it:

```yaml
restart:
  enabled: true
  schedule: "0 5 * * 6"
  timeZone: Europe/Rome
```

The job runs `kubectl rollout restart` on the driver Deployment. It has its own ServiceAccount and a Role limited to that one Deployment. The kubectl image is `restart.image`.

## Metrics and alerts

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    labels:
      release: prometheus
  prometheusRule:
    enabled: true
    groups:
      - name: spark-connect
        rules:
          - alert: SparkConnectDown
            expr: up{job="spark-connect"} == 0
            for: 5m
```

The metrics come from the Prometheus servlet on the UI port. The ServiceMonitor selects the driver Service. The rules are yours: the chart ships none. The label that makes your Prometheus select the ServiceMonitor (`release: prometheus` above) depends on your installation.

## History server

The history server reads event logs from `historyServer.logDirectory`. With stock images, the supported path is a ReadWriteMany PersistentVolumeClaim shared by the driver and the history server. Create the claim yourself, then:

```yaml
sparkConf:
  spark.eventLog.enabled: "true"
  spark.eventLog.dir: /spark-events
driver:
  volumes:
    - name: events
      persistentVolumeClaim:
        claimName: spark-events
  volumeMounts:
    - name: events
      mountPath: /spark-events
historyServer:
  enabled: true
  logDirectory: /spark-events
  volumes:
    - name: events
      persistentVolumeClaim:
        claimName: spark-events
  volumeMounts:
    - name: events
      mountPath: /spark-events
```

The pods run as UID and GID 185 with `fsGroup: 185`, so a volume that honours `fsGroup` is writable by the driver. The history server only reads.

Object stores (S3, GCS, Azure) as the log directory need the connector jars on the history server's classpath. `packages` only reaches `spark-submit`, not the history server daemon, so build an image that contains the connector jars and set `image.repository` and `image.tag`. The same applies to the driver and executors when they read from an object store: use `packages` for the connector, or bake the jars into the image.

To open the history server, port-forward its Service (`svc/<fullname>-history-server`, where `<fullname>` is the driver Service name, port 18080) or expose it through `ingress.historyServer` or `gateway.historyServer`.
