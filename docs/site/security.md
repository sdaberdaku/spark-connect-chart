# Security

## Spark Connect has no authentication by default

Anyone who can reach the Connect port can run code on the cluster. The ClusterIP Service is reachable from inside the cluster only. When you expose the endpoint through an Ingress, a Gateway or a LoadBalancer Service, enable the token and put TLS in front of it. `NOTES.txt` prints a warning when the endpoint is exposed without a token.

## The token

```yaml
auth:
  enabled: true
```

This sets `spark.connect.authenticate.token`. The token comes from a Secret:

- With `auth.existingSecret` empty, the chart generates a Secret named `<release>-spark-connect-auth` (the name is shortened to stay within 63 characters; for a release called `spark-connect` it is `spark-connect-auth`). The chart reuses the existing value on upgrade through `lookup`.
- With `auth.existingSecret` set, the chart reads the token from that Secret, from the key `auth.secretKey` (default `token`).

The driver receives the token through an environment variable, never through the rendered properties file.

Read a generated token:

```console
kubectl -n spark get secret spark-connect-auth -o jsonpath='{.data.token}' | base64 -d
```

Tools that render the chart with `helm template` and apply the result (Argo CD, for example) cannot use `lookup`, so they would get a new random token on every render. With such tools create the Secret yourself and set `auth.existingSecret`.

## The token needs TLS in front

The PySpark client turns TLS on whenever a token is set, while the server speaks plaintext gRPC. A client with a token therefore cannot connect to the Service directly, and `kubectl port-forward` cannot carry a token. Terminate TLS at an Ingress or a Gateway and connect with:

```text
sc://<host>:443/;use_ssl=true;token=<token>
```

The [Exposure](exposure.md) page has examples. The chart's end-to-end test does this through Envoy Gateway with an HTTPS listener and a self-signed certificate.

## Pod security

The defaults pass the restricted Pod Security Standard for the driver, the executors and the history server: UID and GID 185 (the `spark` user in the Apache Spark images), `runAsNonRoot`, `seccompProfile: RuntimeDefault`, all capabilities dropped, no privilege escalation and a read-only root filesystem. Scratch space (`spark.local.dir`, the Ivy cache, `/tmp`) is on emptyDir volumes. The end-to-end test runs in a namespace labelled `pod-security.kubernetes.io/enforce=restricted`.

If you change `podSecurityContext` or `securityContext`, the change applies to all three components.

## Service accounts and RBAC

There are two ServiceAccounts. The driver one is bound to a namespaced Role that can manage pods, services, config maps and persistent volume claims, which is what the driver needs to start and clean up executors. The executor one has no Role binding, so user code running in executors has no Kubernetes API rights. Both accept annotations, for example for cloud workload identity. The scheduled restart, when enabled, has its own ServiceAccount with a Role limited to one Deployment.
