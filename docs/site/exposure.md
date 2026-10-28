# Exposure

The chart creates one Service for the driver with the Connect port (15002, `appProtocol: kubernetes.io/h2c`) and the UI port (4040), and, when `historyServer.enabled` is true, a second Service for the history server (18080). Each of the three endpoints (`connect`, `ui`, `historyServer`) can be exposed through an Ingress, through the Gateway API, or both. The chart does not create a Gateway or a GatewayClass and installs no controller.

The Connect endpoint speaks gRPC over HTTP/2 without TLS, so the controller must forward HTTP/2 (h2c) to the backend. The chart is controller agnostic. The examples below show common setups, and each controller's own documentation is the reference. The links were checked on 2026-10-28.

Without a token, an exposed Connect endpoint lets anyone who reaches it run code. Read [Security](security.md) first.

## Ingress with ingress-nginx

ingress-nginx needs TLS on the Ingress for HTTP/2 and the `GRPC` backend protocol ([gRPC example](https://github.com/kubernetes/ingress-nginx/blob/main/docs/examples/grpc/README.md)):

```yaml
auth:
  enabled: true
ingress:
  connect:
    enabled: true
    className: nginx
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    hosts:
      - host: spark.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: spark-example-com-tls
        hosts: [spark.example.com]
```

Clients connect to `sc://spark.example.com:443/;use_ssl=true;token=<token>`.

## Ingress with Traefik

Traefik reads the scheme used to reach the backend from a Service annotation ([Ingress annotations](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)). Set it to `h2c` on the driver Service with `service.annotations`:

```yaml
auth:
  enabled: true
service:
  annotations:
    traefik.ingress.kubernetes.io/service.serversscheme: h2c
ingress:
  connect:
    enabled: true
    className: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hosts:
      - host: spark.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: spark-example-com-tls
        hosts: [spark.example.com]
```

## Gateway API with Envoy Gateway

Create a Gateway with an HTTPS listener (you own the Gateway and the certificate) and point the chart's GRPCRoute at it. This is what the chart's end-to-end test does:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: spark
spec:
  gatewayClassName: eg
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: spark-tls
      allowedRoutes:
        namespaces:
          from: Same
```

```yaml
auth:
  enabled: true
gateway:
  connect:
    enabled: true
    hostnames: [spark.example.com]
    parentRefs:
      - name: eg
        sectionName: https
```

The chart renders a `GRPCRoute` named `<fullname>-connect`, where `<fullname>` is the name of the driver Service, with the driver Service as backend. `gateway.ui` and `gateway.historyServer` render `HTTPRoute` objects and take `matches` as well. `parentRefs` is required whenever a route is enabled.

## AWS Load Balancer Controller

The AWS Load Balancer Controller can serve a Gateway API `GRPCRoute` through an Application Load Balancer. The ALB must be told to use gRPC to the targets and to health check with gRPC. The chart has no template for this, so pass the controller's `TargetGroupConfiguration` through `extraObjects` ([TargetGroupConfiguration](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/targetgroupconfig/), [customization](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/customization/)):

```yaml
auth:
  enabled: true
gateway:
  connect:
    enabled: true
    hostnames: [spark.example.com]
    parentRefs:
      - name: alb
        sectionName: https
extraObjects:
  - apiVersion: gateway.k8s.aws/v1
    kind: TargetGroupConfiguration
    metadata:
      name: "{{ include \"spark-connect.fullname\" . }}"
    spec:
      targetReference:
        name: "{{ include \"spark-connect.fullname\" . }}"
      defaultConfiguration:
        targetType: ip
      routeConfigurations:
        - routeIdentifier:
            kind: GRPCRoute
            namespace: "{{ .Release.Namespace }}"
            name: "{{ include \"spark-connect.fullname\" . }}-connect"
          targetGroupProps:
            protocolVersion: GRPC
            healthCheckConfig:
              healthCheckProtocol: HTTP
              healthCheckPath: /
              matcher:
                grpcCode: "12"
```

The server has no health service, so a gRPC call to path `/` returns status 12 (UNIMPLEMENTED). That answer shows the server is up, so the health check accepts code 12 as healthy. This example was checked against the controller documentation and rendered with Helm, but not run on AWS. `targetType: ip` registers the pod IPs directly, which a ClusterIP Service needs. The gRPC settings sit under `routeConfigurations` for the Connect GRPCRoute, so a UI or history server route on the same load balancer keeps HTTP target groups. The Gateway and its load balancer configuration, the certificate and the DNS record are yours to create as described in the controller documentation.

## Combining Ingress and Gateway API

Both can be enabled for the same endpoint, for example during a migration from an Ingress controller to a Gateway.
