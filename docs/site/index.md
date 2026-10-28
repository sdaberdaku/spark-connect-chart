# spark-connect

A Helm chart that runs an Apache Spark Connect server on Kubernetes. The driver runs as a Deployment with one replica and starts its executors as pods in the same namespace, from a pod template the chart renders. Clients (PySpark, Scala, Go and others) connect to it over gRPC.

Install it from the OCI registry:

```console
helm install spark-connect oci://ghcr.io/sdaberdaku/charts/spark-connect
```

The chart is also listed on [Artifact Hub](https://artifacthub.io/packages/helm/spark-connect/spark-connect).

With no values this runs the stock `apache/spark` image of the chart's `appVersion`, with one executor, and the Connect endpoint on port 15002 of a ClusterIP Service.

## What the chart provides

- Stock Apache Spark images by default. The image tag defaults to the chart `appVersion`, which is the Spark version.
- Driver and executor sizes set once in values (cores, CPU request, memory, overhead, ephemeral storage). The chart derives the Spark properties and the pod requests and limits from them.
- Exposure of the Connect endpoint, the Spark UI and the history server through Ingress, Gateway API (`GRPCRoute` and `HTTPRoute`), or both.
- An optional pre-shared token for the Connect endpoint.
- The restricted Pod Security Standard for every pod, a read-only root filesystem, and a separate executor ServiceAccount with no Kubernetes API rights.
- Optional FAIR scheduler pools, log4j2 configuration, Prometheus metrics with a ServiceMonitor and a PrometheusRule, a history server, and a scheduled driver restart.
- `extraObjects` for anything cluster specific.

Every Spark line from 4.0 onwards that has plain `X.Y.Z` tags on `apache/spark` is tested end to end on kind. New Spark releases reach the chart through pull requests that merge and release without manual steps (see [Development](development.md)).

## Where to go next

- [Quickstart](quickstart.md): from a kind cluster to a PySpark query.
- [Configuration](configuration.md): sizing, `sparkConf`, packages, pools, logging and metrics.
- [Exposure](exposure.md): Ingress and Gateway API examples, including gRPC specifics.
- [Python](python.md): matching the client and executor Python, and Arrow.
- [Security](security.md): the token, TLS and Pod Security.
- [Operations](operations.md): upgrades, restarts, metrics and the history server.
- [Values reference](values.md): every value with its default.
