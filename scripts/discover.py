#!/usr/bin/env python3
"""Add new Apache Spark lines found on Docker Hub to spark-versions.json and Chart.yaml.

Prints one line per added Spark line ("spark 4.3"). With --dry-run nothing is written.
DISCOVER_FAKE_TAGS (comma-separated) is appended to the fetched tags, for rehearsals.
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ROWS_FILE = os.path.join(ROOT, "spark-versions.json")
CHART_FILE = os.path.join(ROOT, "charts", "spark-connect", "Chart.yaml")
TAGS_URL = "https://hub.docker.com/v2/repositories/apache/spark/tags?page_size=100"
OLDEST_LINE = (4, 0)


def ver(v):
    return tuple(int(p) for p in v.split("."))


def discover(rows, tags, app_version, chart_version):
    known = {ver(r["spark"])[:2] for r in rows}
    best = {}
    for t in tags:
        if not re.fullmatch(r"\d+\.\d+\.\d+", t):
            continue
        line = ver(t)[:2]
        if line >= OLDEST_LINE and line not in known and ver(t) > best.get(line, (0,)):
            best[line] = ver(t)
    new = [{"spark": ".".join(map(str, best[line]))} for line in sorted(best)]
    added = [f"spark {a}.{b}" for a, b in sorted(best)]
    rows = sorted(rows + new, key=lambda r: ver(r["spark"]))
    top = rows[-1]["spark"]
    if ver(top) > ver(app_version):
        major, minor, _ = ver(chart_version)
        chart_version = f"{major + 1}.0.0" if ver(top)[0] > ver(app_version)[0] else f"{major}.{minor + 1}.0"
        app_version = top
    return rows, app_version, chart_version, added


def serialize(rows):
    return "[\n" + ",\n".join("  " + json.dumps(r) for r in rows) + "\n]\n"


def fetch(url):
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except OSError:
            if attempt == 2:
                raise
            time.sleep(5)


def fetch_tags():
    tags, url = [], TAGS_URL
    while url:
        page = fetch(url)
        tags += [r["name"] for r in page["results"]]
        url = page.get("next")
    return tags + [t for t in os.environ.get("DISCOVER_FAKE_TAGS", "").split(",") if t]


def main():
    with open(ROWS_FILE) as f:
        rows = json.load(f)
    with open(CHART_FILE) as f:
        chart = f.read()
    app = re.search(r'^appVersion: "?([\d.]+)"?', chart, re.M).group(1)
    version = re.search(r"^version: ([\d.]+)", chart, re.M).group(1)
    new_rows, new_app, new_version, added = discover(rows, fetch_tags(), app, version)
    for line in added:
        print(line)
    if added and "--dry-run" not in sys.argv:
        with open(ROWS_FILE, "w") as f:
            f.write(serialize(new_rows))
        chart = re.sub(r"^version: .*$", f"version: {new_version}", chart, count=1, flags=re.M)
        chart = re.sub(r"^appVersion: .*$", f'appVersion: "{new_app}"', chart, count=1, flags=re.M)
        with open(CHART_FILE, "w") as f:
            f.write(chart)


if __name__ == "__main__":
    main()
