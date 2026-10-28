# spark-connect

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/spark-connect)](https://artifacthub.io/packages/search?repo=spark-connect)

A Helm chart that runs an Apache Spark Connect server on Kubernetes. The driver runs as a Deployment and starts its executors as pods in the same namespace. Clients such as PySpark connect to it over gRPC.

Documentation: https://sdaberdaku.github.io/spark-connect-chart/

## Install

```console
helm install spark-connect oci://ghcr.io/sdaberdaku/charts/spark-connect \
  --namespace spark --create-namespace
```

With no values this runs the stock `apache/spark` image of the chart's `appVersion`. To try it on a local kind cluster and run a query, follow the [quickstart](https://sdaberdaku.github.io/spark-connect-chart/quickstart/).

## Features

- Stock Apache Spark images by default. The image tag defaults to the chart `appVersion`, which is the Spark version. Spark 4.0 and later, each line tested end to end on kind.
- Driver and executor sizes set once in values. The chart derives the Spark properties and the pod resources from them.
- Exposure through Ingress, Gateway API (`GRPCRoute` and `HTTPRoute`), or both, for the Connect endpoint, the Spark UI and the history server.
- Optional pre-shared token for the Connect endpoint. It works over port-forward and behind a TLS-terminating Ingress or Gateway, and both are tested.
- Restricted Pod Security Standard, read-only root filesystem, and an executor ServiceAccount without Kubernetes API rights.
- Optional FAIR scheduler pools, log4j2, Prometheus metrics with ServiceMonitor and PrometheusRule, history server, scheduled driver restart, and `extraObjects`.
- New Spark releases reach the chart through automatic pull requests that merge and release when CI passes.

## Documentation

- [Quickstart](https://sdaberdaku.github.io/spark-connect-chart/quickstart/)
- [Configuration](https://sdaberdaku.github.io/spark-connect-chart/configuration/)
- [Exposure](https://sdaberdaku.github.io/spark-connect-chart/exposure/)
- [Python](https://sdaberdaku.github.io/spark-connect-chart/python/)
- [Security](https://sdaberdaku.github.io/spark-connect-chart/security/)
- [Operations](https://sdaberdaku.github.io/spark-connect-chart/operations/)
- [Development and release](https://sdaberdaku.github.io/spark-connect-chart/development/)
- [Values reference](https://sdaberdaku.github.io/spark-connect-chart/values/)

## License

Apache-2.0, see [LICENSE](LICENSE).
