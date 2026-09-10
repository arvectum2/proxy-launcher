import ast
import pathlib
import re
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RETIRED_REPOSITORY_SLUGS = (
    "arutyunoveth" + "/proxy-launcher",
    "arvectum" + "/proxy-launcher",
    "arvectum1" + "/proxy-launcher",
)
CANONICAL_REPOSITORY_SLUG = "arvectum2/proxy-launcher"
HISTORICAL_REFERENCE_PREFIXES = (
    "docs/evidence/",
    "release/baselines/",
)


def _tracked_files() -> list[str]:
    return subprocess.check_output(
        ["git", "ls-files"],
        cwd=ROOT,
        text=True,
    ).splitlines()


class RepositoryHygieneTests(unittest.TestCase):
    def test_regression_names_do_not_encode_refactor_slice_numbers(self):
        violations = {}
        for path in sorted((ROOT / "tests").glob("test_*.py")):
            tree = ast.parse(path.read_text(encoding="utf-8-sig"))
            names = [
                node.name
                for node in ast.walk(tree)
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                and node.name.startswith("test_")
                and re.search(r"slice\d+", node.name)
            ]
            if names:
                violations[path.relative_to(ROOT).as_posix()] = names
        if violations:
            self.fail(repr(violations))

    def test_current_tree_uses_canonical_repository_identity(self):
        violations = {}
        for relative in _tracked_files():
            if relative == ".mailmap" or relative.startswith(HISTORICAL_REFERENCE_PREFIXES):
                continue
            path = ROOT / relative
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            matched = [slug for slug in RETIRED_REPOSITORY_SLUGS if slug in text]
            if matched:
                violations[relative] = matched
        if violations:
            self.fail(repr(violations))

    def test_historical_identity_mapping_is_preserved_without_history_rewrite(self):
        mailmap = (ROOT / ".mailmap").read_text(encoding="utf-8")
        self.assertIn("arutyunoveth", mailmap)
        self.assertIn("Arvectum <arvectum@gmail.com>", mailmap)

    def test_canonical_repository_identity_is_present_in_current_governance(self):
        task = (ROOT / "docs" / "APL_IP_003_CANONICAL_SOURCE_REFACTOR.md").read_text(
            encoding="utf-8"
        )
        self.assertIn(CANONICAL_REPOSITORY_SLUG, task)


if __name__ == "__main__":
    unittest.main()
