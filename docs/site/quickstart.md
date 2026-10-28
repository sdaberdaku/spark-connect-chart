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

```console
kubectl -n spark port-forward svc/spark-connect 15002:15002
```

## Run a query

The PySpark client version has to match the Spark version of the server (the chart `appVersion`, shown by `helm show chart`). The Python minor version has to match the image's Python for Python UDFs: the stock images ship Python 3.10 (see [Python](python.md)).

```console
uv run --python 3.10 --with "pyspark-client==4.2.0" python - <<'PY'
from pyspark.sql import SparkSession
from pyspark.sql.functions import udf

spark = SparkSession.builder.remote("sc://localhost:15002").getOrCreate()
add_one = udf(lambda x: x + 1, "long")
print(spark.range(0, 1000, numPartitions=4).select(add_one("id").alias("v")).groupBy().sum("v").collect())
PY
```

The query needs an executor, so `kubectl -n spark get pods` shows an executor pod next to the driver while it runs. The result is `[Row(sum(v)=500500)]`.

## Clean up

```console
helm uninstall spark-connect -n spark
kind delete cluster --name spark
```
