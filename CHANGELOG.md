# Changelog

Changes made by hand are listed here. Releases created by automation (Spark and tooling updates) get their notes from the merged pull requests, which you can read on the [GitHub Releases](https://github.com/sdaberdaku/spark-connect-chart/releases) page and on Artifact Hub.

## 1.1.1 - 2026-10-28

- Add the Artifact Hub repository ID to `artifacthub-repo.yml`, the badge to both READMEs and a link on the docs home page.
- Reword the chart description: executors are static pods started by the driver, not on demand.
- Name the real value path in newline errors (`historyServer.logDirectory`) and say "Spark properties" instead of "spark-defaults.conf".
- Reject newlines in `driver.javaOptions`, `executor.javaOptions` and `packages` entries, with the value path in the error.
- Add unit tests for the auth Secret lookup on a live Secret without data and with a token.
- Docs: local `spark.jars` paths reach executors through the driver file server, and the token works over port-forward and behind a TLS-terminating Ingress or Gateway.

## 1.1.0 - 2026-10-28

- Renovate opens patch pull requests for older Spark rows again.
- The token works over port-forward, and the install notes print the connection string.
- Nested `sparkConf` maps are rejected.
- The driver keeps its Role when an existing ServiceAccount is used.
- Add an executor image override.
- Add scheduling values for the history server and the restart job.
- The release workflow only treats a missing tag as unreleased.
- Docs fixes.

## 1.0.0 - 2026-10-28

- First release: a Helm chart that runs an Apache Spark Connect server on Kubernetes, with the driver as a Deployment and executors as pods in the same namespace.
- Stock `apache/spark` images by default, with the image tag following the chart `appVersion`. Spark 4.0 and later, each line tested end to end on kind.
- Driver and executor sizes are set once in values, and the chart derives the Spark properties and pod resources from them.
- Exposure through Ingress, Gateway API (`GRPCRoute` and `HTTPRoute`), or both, for the Connect endpoint, the Spark UI and the history server.
- Optional pre-shared token for the Connect endpoint.
- Restricted Pod Security Standard, read-only root filesystem, and an executor ServiceAccount without Kubernetes API rights.
