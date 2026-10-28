import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from changelog_page import render  # noqa: E402

RELEASES = [
    {"name": "spark-connect 1.1.0", "tag_name": "v1.1.0", "published_at": "2026-10-28T19:43:28Z", "body": "- b"},
    {"name": "", "tag_name": "v1.0.0", "published_at": "2026-10-28T18:57:10Z", "body": None},
]


class RenderTest(unittest.TestCase):
    def test_order_headings_and_dates(self):
        page = render(RELEASES)
        self.assertTrue(page.startswith("# Changelog\n"))
        self.assertLess(page.index("## spark-connect 1.1.0"), page.index("## v1.0.0"))
        self.assertIn("2026-10-28\n\n- b", page)

    def test_missing_body(self):
        self.assertIn("## v1.0.0\n\n2026-10-28\n", render(RELEASES))

    def test_draft_skipped(self):
        draft = {"name": "x", "tag_name": "v9", "published_at": None, "draft": True, "body": ""}
        self.assertNotIn("## x", render([draft] + RELEASES))


if __name__ == "__main__":
    unittest.main()
