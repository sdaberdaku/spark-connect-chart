#!/usr/bin/env python3
"""Write docs/site/changelog.md from the GitHub Releases, or from CHANGELOG.md when the fetch fails."""
import json
import os
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "docs", "site", "changelog.md")
URL = "https://api.github.com/repos/sdaberdaku/spark-connect-chart/releases?per_page=100"
HEAD = (
    "# Changelog\n\n"
    "Hand-made changes are listed in [CHANGELOG.md](https://github.com/sdaberdaku/spark-connect-chart/blob/main/CHANGELOG.md). "
    "Every release is on the [Releases page](https://github.com/sdaberdaku/spark-connect-chart/releases).\n"
)


def render(releases):
    page = HEAD
    for r in releases:
        if r.get("draft"):
            continue
        page += f"\n## {r.get('name') or r['tag_name']}\n\n{r['published_at'][:10]}\n\n{(r.get('body') or '').strip()}\n"
    return page


def fetch():
    req = urllib.request.Request(URL, headers={"Accept": "application/vnd.github+json"})
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


if __name__ == "__main__":
    try:
        page = render(fetch())
    except (OSError, ValueError, KeyError) as e:
        print(f"::warning::changelog_page: could not read the GitHub Releases, using CHANGELOG.md ({e})")
        with open(os.path.join(ROOT, "CHANGELOG.md")) as f:
            page = f.read()
    with open(OUT, "w") as f:
        f.write(page)
