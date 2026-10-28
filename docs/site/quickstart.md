# Quickstart

This runs the chart on a local kind cluster and executes a query from PySpark. You need Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Helm 3.8 or later (for OCI charts) and [uv](https://docs.astral.sh/uv/).

## Create a cluster and install the chart

```console
kind create cluster --name spark
helm install spark-connect oci://ghcr.io/sdaberdaku/charts/spark-connect \
  --namespace spark --create-namespace --wait --timeout 10m
```

The release is named `spark-connect`, so the Service is also named `spark-connect`. The first start pulls the Spark image, which takes a few minutes.

## Reach the server

In a second terminal:

```console
kubectl -n spark port-forward svc/spark-connect 15002:15002
```

## Run a query

The PySpark client version has to match the Spark version of the server, which is the chart `appVersion`. The Python minor version has to match the image's Python for Python UDFs (see [Python](python.md)). Read both from the chart and the image:

```console
SPARK_VERSION=$(helm show chart oci://ghcr.io/sdaberdaku/charts/spark-connect | sed -n 's/^appVersion: "\{0,1\}\([0-9.]*\).*/\1/p')
PY=$(docker run --rm --entrypoint python3 apache/spark:$SPARK_VERSION -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
uv run --python "$PY" --with "pyspark-client==$SPARK_VERSION" python - <<'PY'
from pyspark.sql import SparkSession
from pyspark.sql.functions import udf

spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
add_one = udf(lambda x: x + 1, "long")
print(spark.range(0, 1000, numPartitions=4).select(add_one("id").alias("v")).groupBy().sum("v").collect())
PY
```

The chart starts its executors together with the driver and keeps them running (`executor.instances`, one by default), so `kubectl -n spark get pods` shows an executor pod next to the driver before and after the query. The result is `[Row(sum(v)=500500)]`.

## Clean up

```console
helm uninstall spark-connect -n spark
kind delete cluster --name spark
```
