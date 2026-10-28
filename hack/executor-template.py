"""Print the executor pod template from a rendered chart (stdin, multi-document YAML)."""
import sys
import yaml

for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get("kind") == "ConfigMap" and "executor-pod-template.yaml" in (doc.get("data") or {}):
        print(doc["data"]["executor-pod-template.yaml"])
