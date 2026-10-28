#!/usr/bin/env bash
# End-to-end test: chart on kind, plain port-forward, then through Envoy Gateway with a token.
# Env: SPARK_VERSION (required), KEEP_CLUSTER=1 keeps the cluster, CI skips deletion.
# The script uses its own kubeconfig (in a temp dir), so it never touches your current context.
# With KEEP_CLUSTER=1, run `kind export kubeconfig --name spark-connect-e2e` to reach the cluster afterwards.
set -euo pipefail

# renovate: datasource=docker depName=kindest/node
KIND_NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
# renovate: datasource=docker depName=envoyproxy/gateway-helm
ENVOY_GATEWAY_VERSION=v1.9.3

SPARK_VERSION=${SPARK_VERSION:?set SPARK_VERSION}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/e2e/out
CLUSTER=spark-connect-e2e
NS=spark
IMAGE=apache/spark:$SPARK_VERSION
PIDS=()
TMP=$(mktemp -d)

dump() {
  [ -f "$KUBECONFIG" ] || return 0
  mkdir -p "$OUT"
  kubectl get pods,events,svc,gateway,grpcroute -A -o wide >"$OUT/resources.txt" 2>&1 || true
  kubectl describe pods -n "$NS" >"$OUT/describe.txt" 2>&1 || true
  kubectl get events -A --sort-by=.lastTimestamp >"$OUT/events.txt" 2>&1 || true
  for p in $(kubectl get pods -n "$NS" -o name 2>/dev/null); do
    kubectl logs -n "$NS" "$p" --all-containers >"$OUT/$(basename "$p").log" 2>&1 || true
  done
  echo "failure dump written to $OUT" >&2
}

cleanup() {
  rc=$?
  for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done
  [ $rc -ne 0 ] && dump
  if [ -z "${KEEP_CLUSTER:-}" ] && [ -z "${CI:-}" ]; then kind delete cluster --name "$CLUSTER" || true; fi
  rm -rf "${TMP:-}"
  exit $rc
}
trap cleanup EXIT
export KUBECONFIG="$TMP/kubeconfig"

# wait_port PORT PID: the port must be open and the port-forward process (PID) still alive, so a foreign listener cannot pass.
wait_port() {
  for _ in $(seq 60); do
    kill -0 "$2" 2>/dev/null || { echo "port-forward for $1 exited (port already in use?)" >&2; return 1; }
    (echo >/dev/tcp/127.0.0.1/"$1") 2>/dev/null && { sleep 1; kill -0 "$2" 2>/dev/null && return 0; }
    sleep 1
  done
  echo "port $1 not up" >&2; return 1
}

docker pull "$IMAGE"
PYMINOR=$(docker run --rm --entrypoint python3 "$IMAGE" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
echo "image python: $PYMINOR"
client() { timeout 600 uv run --python "$PYMINOR" --with "pyspark-client==$SPARK_VERSION" "$ROOT/e2e/client.py" "$@"; }

kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER" --image "$KIND_NODE_IMAGE" --wait 120s
# docker save of a single platform: with the containerd image store, "kind load docker-image" fails on multi-arch indexes
# ("content digest ... not found").
docker save --platform "linux/$(docker info --format '{{.Architecture}}' | sed 's/x86_64/amd64/;s/aarch64/arm64/')" -o "$TMP/image.tar" "$IMAGE"
kind load image-archive "$TMP/image.tar" --name "$CLUSTER"
rm -f "$TMP/image.tar"

# Standard-channel Gateway API CRDs plus the Envoy Gateway CRDs, then the controller without its bundled CRDs.
helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm --version "$ENVOY_GATEWAY_VERSION" \
  --set crds.gatewayAPI.enabled=true --set crds.gatewayAPI.channel=standard --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -
helm install eg oci://docker.io/envoyproxy/gateway-helm --version "$ENVOY_GATEWAY_VERSION" --skip-crds \
  -n envoy-gateway-system --create-namespace --wait

kubectl create namespace "$NS"
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" 2>/dev/null
kubectl create secret tls e2e-tls -n "$NS" --cert="$TMP/tls.crt" --key="$TMP/tls.key"
kubectl apply -f "$ROOT/e2e/gateway.yaml"
kubectl wait gateway/eg -n "$NS" --for=condition=Programmed --timeout=180s

# 1. plain release, port-forward
helm install sc "$ROOT/charts/spark-connect" -n "$NS" --set image.tag="$SPARK_VERSION" --wait --timeout 10m
kubectl port-forward -n "$NS" svc/sc-spark-connect 15002:15002 >/dev/null &
PIDS+=($!)
wait_port 15002 $!
client --remote sc://localhost:15002
kubectl get pods -n "$NS" -l spark-role=executor --no-headers | grep -q . || { echo "no executor pod" >&2; exit 1; }

# 2. token and Gateway
helm upgrade sc "$ROOT/charts/spark-connect" -n "$NS" --set image.tag="$SPARK_VERSION" --wait --timeout 10m \
  --set auth.enabled=true --set gateway.connect.enabled=true \
  --set 'gateway.connect.parentRefs[0].name=eg' --set 'gateway.connect.parentRefs[0].sectionName=https'
kubectl wait grpcroute/sc-spark-connect-connect -n "$NS" --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True --timeout=60s
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=eg -o jsonpath='{.items[0].metadata.name}')
kubectl wait deploy -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=eg --for=condition=Available --timeout=120s
kubectl port-forward -n envoy-gateway-system "svc/$ENVOY_SVC" 8443:443 >/dev/null &
PIDS+=($!)
wait_port 8443 $!
TOKEN=$(kubectl get secret sc-spark-connect-auth -n "$NS" -o jsonpath='{.data.token}' | base64 -d)
export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=$TMP/tls.crt
client --remote "sc://localhost:8443/;use_ssl=true;token=$TOKEN"
client --remote "sc://localhost:8443/;use_ssl=true" --expect-auth-failure
echo "ALL E2E PASSED ($SPARK_VERSION)"
