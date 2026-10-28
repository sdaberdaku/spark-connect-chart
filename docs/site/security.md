# Security

## Spark Connect has no authentication by default

Anyone who can reach the Connect port can run code on the cluster. The ClusterIP Service is reachable from inside the cluster only. When you expose the endpoint through an Ingress, a Gateway or a LoadBalancer Service, enable the token and put TLS in front of it. `NOTES.txt` prints a warning when the endpoint is exposed without a token.

## The token

```yaml
auth:
  enabled: true
```

This sets `spark.connect.authenticate.token`. The token comes from a Secret:

- With `auth.existingSecret` empty, the chart generates a Secret named `<fullname>-auth`, where `<fullname>` is the name of the driver Service (release `foo` gives `foo-spark-connect-auth`, release `my-spark-connect` gives `my-spark-connect-auth`). The chart reuses the existing value on upgrade through `lookup`.
- With `auth.existingSecret` set, the chart reads the token from that Secret, from the key `auth.secretKey` (default `token`).

The driver receives the token through an environment variable, never through the rendered properties file.

Read a generated token:

```console
kubectl -n spark get secret <fullname>-auth -o jsonpath='{.data.token}' | base64 -d
```

Tools that render the chart with `helm template` and apply the result (Argo CD, for example) cannot use `lookup`, so they would get a new random token on every render. With such tools create the Secret yourself and set `auth.existingSecret`.

## The token and TLS

The server speaks plaintext gRPC. The PySpark client sends a token over TLS, with one exception: for the host `localhost` it uses local channel credentials and sends the token over plaintext gRPC. This is in `toChannel` in `pyspark/sql/connect/client/core.py`, which is the same in Spark 4.0, 4.1 and 4.2, and the end-to-end test checks it on every supported row.

This gives two ways to connect with a token:

- Over `kubectl port-forward` to the driver Service. The client sees `localhost`, so no TLS is needed:

  ```text
  sc://localhost:15002/;token=<token>
  ```

- Through TLS termination at an Ingress or a Gateway:

  ```text
  sc://<host>:443/;use_ssl=true;token=<token>
  ```

A client that connects to any other host name with a token, for example the address of a LoadBalancer or NodePort Service, tries TLS and fails against the plaintext port. Put a TLS-terminating proxy or load balancer in front of such a Service.

The [Exposure](exposure.md) page has examples. The chart's end-to-end test checks both forms: a token over a port-forward, and a token through Envoy Gateway with an HTTPS listener and a self-signed certificate. Both also run once without the token, which must be refused.

## Pod security

The defaults pass the restricted Pod Security Standard for the driver, the executors, the history server and the restart job: UID and GID 185 (the `spark` user in the Apache Spark images), `runAsNonRoot`, `seccompProfile: RuntimeDefault`, all capabilities dropped, no privilege escalation and a read-only root filesystem. Scratch space (`spark.local.dir`, the Ivy cache, `/tmp`) is on emptyDir volumes. The end-to-end test runs in a namespace labelled `pod-security.kubernetes.io/enforce=restricted`.

If you change `podSecurityContext` or `securityContext`, the change applies to all four components (the restart job only when `restart.enabled` is true).

## Service accounts and RBAC

There are two ServiceAccounts. The driver one is bound to a namespaced Role that can manage pods, services, config maps and persistent volume claims, which is what the driver needs to start and clean up executors. The executor one has no Role binding, so user code running in executors has no Kubernetes API rights. Both accept annotations, for example for cloud workload identity. The scheduled restart, when enabled, has its own ServiceAccount with a Role limited to one Deployment.

With `serviceAccount.driver.create: false` the chart does not create the driver ServiceAccount, but it still creates the Role and the RoleBinding and binds them to the ServiceAccount named in `serviceAccount.driver.name`. That name is required in this case, and the render fails without it. The ServiceAccount has to be one the driver can use for its own pods, since the driver needs the Role to start executors. The driver pod mounts its ServiceAccount token (`automountServiceAccountToken: true`).

## Use a dedicated namespace

Anyone who can run queries through the Connect endpoint can run code in the driver, and the driver can create, patch and delete pods, services, config maps and persistent volume claims in its namespace. Install the chart in a namespace of its own, so that the Role reaches nothing else, and keep other workloads and their secrets elsewhere.

## The Spark UI

The Spark UI on port 4040 has kill links for stages and jobs, and it shows SQL text and configuration. It has no authentication of its own, and the Connect token does not cover it. Exposing it through an Ingress or a Gateway lets anyone who reaches it cancel running jobs, so put your own authentication in front of it or leave it unexposed and use `kubectl port-forward`.
