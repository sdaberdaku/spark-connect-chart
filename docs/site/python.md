# Python

## Matching Python versions

Python UDFs run on the executors, and PySpark pickles the function on the client. The client and the executor Python must have the same minor version, otherwise a UDF fails when it is deserialized.

The stock `apache/spark` images are built on Ubuntu 22.04 and ship its `python3`:

| Spark | Image | Python |
| ----- | ----- | ------ |
| 4.0.5 | `apache/spark:4.0.5` | 3.10 |
| 4.1.4 | `apache/spark:4.1.4` | 3.10 |
| 4.2.1 | `apache/spark:4.2.1` | 3.10 |
| 4.3.0 | `apache/spark:4.3.0` | 3.10 |

You can check any image yourself:

```console
docker run --rm --entrypoint python3 apache/spark:4.2.1 --version
```

Run the client on that minor version, for example with `uv run --python "$PY" --with "pyspark-client==$SPARK_VERSION" ...`. The client package version should equal the server's Spark version.

## Spark 4.3 and the stock images

PySpark 4.3 needs Python 3.11 or newer: `pyspark` and `pyspark-client` 4.3.0 on PyPI require `>=3.11`. The stock `apache/spark:4.3.0` images still ship Python 3.10, so no 4.3 client can match the executor Python, and every Python UDF fails with:

```text
[PYTHON_VERSION_MISMATCH] Python in worker has different version: 3.10 than that in driver: 3.11, PySpark cannot run with different minor versions.
```

Queries without Python UDFs work from any Python that PySpark 4.3 supports. For Python UDFs on Spark 4.3, use an image with Python 3.11 or newer and run the client on the same minor; [Arrow and pandas](#arrow-and-pandas) shows how to set the image. Moving the stock images to a newer Ubuntu is discussed in [apache/spark-docker#132](https://github.com/apache/spark-docker/issues/132).

## Arrow and pandas

The stock images contain neither pandas nor pyarrow. Spark 4.2 turns Arrow on for plain Python UDFs, so on a stock image a simple `@udf` would fail with `ModuleNotFoundError: No module named 'pyarrow'`. The chart therefore defaults to:

```yaml
sparkConf:
  spark.sql.execution.pythonUDF.arrow.enabled: "false"
```

The flag only affects plain `@udf` functions. Pandas UDFs and Arrow UDFs need pandas and pyarrow in the executor image whatever the flag says (`toPandas()` does not: the client converts the Arrow data, and `pyspark-client` depends on pandas and pyarrow). Use an image that has them, for example `ghcr.io/sdaberdaku/spark:<spark>-python<minor>`, and set Arrow back to `"true"`:

```yaml
image:
  repository: ghcr.io/sdaberdaku/spark
  tag: 4.2.0-python3.12
sparkConf:
  spark.sql.execution.pythonUDF.arrow.enabled: "true"
```

Those images take the Python minor from the tag, so the client has to run that minor. The tags available are listed in the [spark-images repository](https://github.com/sdaberdaku/spark-images).

## Extra Python packages

Python packages that a UDF imports must be in the executor image. Build your own image on top of the Spark image and set `image.repository` and `image.tag`. The chart does not install packages at start.
