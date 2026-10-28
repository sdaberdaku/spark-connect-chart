import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from discover import discover, serialize  # noqa: E402

ROWS = [{"spark": "4.0.4"}, {"spark": "4.1.3"}, {"spark": "4.2.0"}]


class DiscoverTest(unittest.TestCase):
    def test_new_minor_line(self):
        rows, app, chart, added = discover(ROWS, ["4.2.0", "4.3.0", "4.3.1"], "4.2.0", "1.0.0")
        self.assertEqual(rows[-1], {"spark": "4.3.1"})
        self.assertEqual((len(rows), app, chart, added), (4, "4.3.1", "1.1.0", ["spark 4.3"]))

    def test_new_major_line(self):
        rows, app, chart, added = discover(ROWS, ["5.0.0"], "4.2.0", "1.4.2")
        self.assertEqual((rows[-1], app, chart, added), ({"spark": "5.0.0"}, "5.0.0", "2.0.0", ["spark 5.0"]))

    def test_two_new_lines_bump_once(self):
        rows, app, chart, added = discover(ROWS, ["4.3.0", "5.0.0"], "4.2.0", "1.4.2")
        self.assertEqual([r["spark"] for r in rows[-2:]], ["4.3.0", "5.0.0"])
        self.assertEqual((app, chart, added), ("5.0.0", "2.0.0", ["spark 4.3", "spark 5.0"]))

    def test_patch_of_known_line_ignored(self):
        self.assertEqual(discover(ROWS, ["4.2.1"], "4.2.0", "1.0.0"), (ROWS, "4.2.0", "1.0.0", []))

    def test_old_or_odd_tags_ignored(self):
        tags = ["3.5.9", "4.3.0-python3", "latest", "4.3.0-scala2.13-java17-ubuntu"]
        self.assertEqual(discover(ROWS, tags, "4.2.0", "1.0.0"), (ROWS, "4.2.0", "1.0.0", []))

    def test_new_line_older_than_default(self):
        rows = [{"spark": "4.0.4"}, {"spark": "4.2.0"}]
        out, app, chart, added = discover(rows, ["4.1.3"], "4.2.0", "1.0.0")
        self.assertEqual(([r["spark"] for r in out], app, chart, added), (["4.0.4", "4.1.3", "4.2.0"], "4.2.0", "1.0.0", ["spark 4.1"]))

    def test_does_not_mutate_input(self):
        discover(ROWS, ["4.3.0"], "4.2.0", "1.0.0")
        self.assertEqual(len(ROWS), 3)

    def test_serialize(self):
        self.assertEqual(
            serialize(ROWS),
            '[\n  {"spark": "4.0.4"},\n  {"spark": "4.1.3"},\n  {"spark": "4.2.0"}\n]\n',
        )

    def test_serialize_matches_current_file(self):
        path = os.path.join(os.path.dirname(__file__), "..", "spark-versions.json")
        with open(path) as f:
            text = f.read()
        import json
        self.assertEqual(serialize(json.loads(text)), text)


if __name__ == "__main__":
    unittest.main()
