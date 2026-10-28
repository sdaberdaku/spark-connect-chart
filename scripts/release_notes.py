#!/usr/bin/env python3
"""Write release notes for a chart version.

Usage: release_notes.py VERSION PREV_TAG OUT_DIR
Writes OUT_DIR/notes.md (GitHub Release body) and OUT_DIR/changes.yaml (value of the
artifacthub.io/changes annotation). The bullets come from the CHANGELOG.md section of VERSION when
there is one, otherwise from the merged pull request titles since PREV_TAG (empty on the first release).
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REPO = "https://github.com/sdaberdaku/spark-connect-chart"


def section(changelog_text, version):
    m = re.search(rf"^## {re.escape(version)} - [^\n]*\n(.*?)(?=^## |\Z)", changelog_text, re.M | re.S)
    if not m:
        return None
    return [line[2:].strip() for line in m.group(1).splitlines() if line.startswith("- ")]


def pr_titles(subjects):
    prs = [s for s in subjects if re.search(r"\(#\d+\)$", s)]
    return prs or list(subjects)


def main(version, prev_tag, out_dir, changelog_text, subjects):
    bullets = section(changelog_text, version)
    if bullets is None:
        bullets = pr_titles(subjects)
    lines = [f"- {b}" for b in bullets]
    if prev_tag:
        lines += ["", f"Full changelog: {REPO}/compare/{prev_tag}...v{version}"]
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "notes.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    # JSON-style quoting is valid YAML, so every bullet is a safe plain string.
    with open(os.path.join(out_dir, "changes.yaml"), "w") as f:
        f.write("".join(f"- {json.dumps(b)}\n" for b in bullets))


if __name__ == "__main__":
    version, prev_tag, out_dir = sys.argv[1:4]
    with open(os.path.join(ROOT, "CHANGELOG.md")) as f:
        text = f.read()
    rev = f"{prev_tag}..HEAD" if prev_tag else "HEAD"
    log = subprocess.run(["git", "log", "--format=%s", rev], cwd=ROOT, check=True, capture_output=True, text=True)
    main(version, prev_tag, out_dir, text, log.stdout.splitlines())
