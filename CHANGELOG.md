# Changelog

Changes made by hand are listed here, one line per bullet. Releases created by automation (Spark and tooling updates) get their notes from the merged pull requests, which you can read on the [GitHub Releases](https://github.com/sdaberdaku/spark-connect-chart/releases) page and on Artifact Hub.

## 1.1.1 - 2026-10-28

- Add the Artifact Hub repository ID to `artifacthub-repo.yml`, the badge to both READMEs and a link on the docs home page.
- Change the chart description to say that the driver starts the executor pods.
- Name the real value path in newline errors (`historyServer.logDirectory`) and say "Spark properties" instead of "spark-defaults.conf".
- Reject newlines in `driver.javaOptions`, `executor.javaOptions` and `packages` entries, with the value path in the error.
- Add unit tests for the auth Secret lookup on a live Secret without data and with a token.
- Fix the docs: local `spark.jars` paths reach executors through the driver file server, and the token works over port-forward and behind a TLS-terminating Ingress or Gateway.

## 1.1.0 - 2026-10-28

- Open Renovate patch pull requests for older Spark rows again.
- Make the token work over port-forward, and print the connection string in the install notes.
- Reject nested `sparkConf` maps.
- Keep the driver Role when an existing ServiceAccount is used.
- Require `serviceAccount.driver.name` when `serviceAccount.driver.create` is false; the render fails without it.
- Fail the render when an enabled Ingress has no hosts or no paths.
- Fail the render when a `sparkConf` value contains a newline.
- Add an executor image override.
- Add scheduling values for the history server and the restart job.
- Make the release workflow treat only a missing tag as unreleased.
- Fix the docs.

## 1.0.0 - 2026-10-28

- First release: a Helm chart that runs an Apache Spark Connect server on Kubernetes, with the driver as a Deployment and executors as pods in the same namespace.
- Stock `apache/spark` images by default, with the image tag following the chart `appVersion`. Spark 4.0 and later, each line tested end to end on kind.
- Driver and executor sizes are set once in values, and the chart derives the Spark properties and pod resources from them.
- Exposure through Ingress, Gateway API (`GRPCRoute` and `HTTPRoute`), or both, for the Connect endpoint, the Spark UI and the history server.
- Optional pre-shared token for the Connect endpoint.
- Restricted Pod Security Standard, read-only root filesystem, and an executor ServiceAccount without Kubernetes API rights.
