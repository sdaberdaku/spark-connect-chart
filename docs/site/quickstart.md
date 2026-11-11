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

The PySpark client version has to match the Spark version of the server, which is the chart `appVersion`. Read it from the chart:

```console
SPARK_VERSION=$(helm show chart oci://ghcr.io/sdaberdaku/charts/spark-connect | sed -n 's/^appVersion: "\{0,1\}\([0-9.]*\).*/\1/p')
uv run --python 3.13 --with "pyspark-client==$SPARK_VERSION" python - <<'PY'
from pyspark.sql import SparkSession
from pyspark.sql.functions import col

spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
print(spark.range(0, 1000, numPartitions=4).select((col("id") + 1).alias("v")).groupBy().sum("v").collect())
PY
```

This query has no Python UDF, so the client can run on any Python its PySpark version supports; 3.13 works from Spark 4.0 to 4.3. Python UDFs also need the client on the image's Python minor version, see [Python](python.md).

The chart starts its executors together with the driver and keeps them running (`executor.instances`, one by default), so `kubectl -n spark get pods` shows an executor pod next to the driver before and after the query. The result is `[Row(sum(v)=500500)]`.

## Clean up

```console
helm uninstall spark-connect -n spark
kind delete cluster --name spark
```
