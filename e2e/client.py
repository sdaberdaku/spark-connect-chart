"""Spark Connect smoke client. Usage: client.py --remote <url> [--expect-auth-failure]"""
import argparse
import sys

from pyspark.sql import SparkSession
from pyspark.sql.functions import col


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--remote", required=True)
    p.add_argument("--expect-auth-failure", action="store_true")
    args = p.parse_args()

    try:
        spark = SparkSession.builder.remote(args.remote).getOrCreate()
        total = spark.range(0, 1000, numPartitions=4).select((col("id") + 1).alias("v")).groupBy().sum("v").collect()[0][0]
    except Exception as e:  # noqa: BLE001
        if args.expect_auth_failure and "unauthenticated" in str(e).lower():
            print("E2E OK (auth refused as expected)")
            return 0
        print(f"E2E FAILED: {e}")
        return 1
    if args.expect_auth_failure:
        print("E2E FAILED: request without a token was accepted")
        return 1
    assert total == 500500, total
    print("E2E OK")
    return 0


sys.exit(main())
