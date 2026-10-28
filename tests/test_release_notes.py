import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from release_notes import main, pr_titles, section  # noqa: E402

CHANGELOG = """# Changelog

Intro.

## 1.1.0 - 2026-10-28

- First fix
- Second "quoted" fix

## 1.0.0 - 2026-10-28

- Initial release
"""


class SectionTest(unittest.TestCase):
    def test_found(self):
        self.assertEqual(section(CHANGELOG, "1.1.0"), ["First fix", 'Second "quoted" fix'])

    def test_last_section(self):
        self.assertEqual(section(CHANGELOG, "1.0.0"), ["Initial release"])

    def test_not_found(self):
        self.assertIsNone(section(CHANGELOG, "2.0.0"))

    def test_version_is_not_a_prefix_match(self):
        self.assertIsNone(section(CHANGELOG, "1.1"))


class PrTitlesTest(unittest.TestCase):
    def test_keeps_squash_titles(self):
        subjects = ["chore: bump helm (#12)", "fix: a wip commit", "feat: thing (#13)"]
        self.assertEqual(pr_titles(subjects), ["chore: bump helm (#12)", "feat: thing (#13)"])

    def test_falls_back_to_all_subjects(self):
        self.assertEqual(pr_titles(["fix: a", "fix: b"]), ["fix: a", "fix: b"])

    def test_empty(self):
        self.assertEqual(pr_titles([]), [])


class MainTest(unittest.TestCase):
    def run_main(self, version, prev, changelog=CHANGELOG, subjects=()):
        with tempfile.TemporaryDirectory() as d:
            main(version, prev, d, changelog, list(subjects))
            with open(os.path.join(d, "notes.md")) as f:
                notes = f.read()
            with open(os.path.join(d, "changes.yaml")) as f:
                changes = f.read()
        return notes, changes

    def test_changelog_wins_over_pr_titles(self):
        notes, _ = self.run_main("1.1.0", "v1.0.0", subjects=["chore: x (#9)"])
        self.assertIn("- First fix", notes)
        self.assertNotIn("chore: x", notes)

    def test_compare_link(self):
        notes, _ = self.run_main("1.1.0", "v1.0.0")
        self.assertEqual(
            notes.splitlines()[-1],
            "Full changelog: https://github.com/sdaberdaku/spark-connect-chart/compare/v1.0.0...v1.1.0",
        )

    def test_first_release_has_no_compare_link(self):
        notes, _ = self.run_main("1.0.0", "")
        self.assertNotIn("compare", notes)

    def test_pr_titles_used_without_section(self):
        notes, changes = self.run_main("1.2.0", "v1.1.0", subjects=["chore: x (#9)"])
        self.assertIn("- chore: x (#9)", notes)
        self.assertEqual(changes, '- "chore: x (#9)"\n')

    def test_changes_yaml_round_trips(self):
        _, changes = self.run_main("1.1.0", "v1.0.0")
        parsed = [json.loads(line[2:]) for line in changes.splitlines()]
        self.assertEqual(parsed, ["First fix", 'Second "quoted" fix'])

    def test_changes_yaml_keeps_non_ascii_literal(self):
        _, changes = self.run_main("1.3.0", "v1.2.0", changelog="## 1.3.0 - 2026-10-29\n\n- Ship \U0001F680 now\n")
        self.assertIn("\U0001F680", changes)
        self.assertNotIn("\\ud83d", changes)

    def test_no_notes_source_still_writes_files(self):
        notes, changes = self.run_main("1.2.0", "v1.1.0")
        self.assertEqual(changes, "")
        self.assertIn("compare", notes)


if __name__ == "__main__":
    unittest.main()
