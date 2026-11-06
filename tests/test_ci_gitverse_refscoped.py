"""Hermetic contract for GitVerse mirror event scoping and bounded retries."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/mirror-to-gitverse.yml'


class GitVerseMirrorScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text()
        cls.snippet = cls.workflow.split('# BEGIN REFSCOPED_PUSH\n', 1)[1].split(
            '# END REFSCOPED_PUSH', 1)[0]

    def run_snippet(self, *, event='push', ref='refs/heads/feature/test',
                    deleted='false', failures=0):
        with tempfile.TemporaryDirectory(prefix='gitverse-mirror-mock-') as d:
            root = Path(d)
            bindir = root / 'bin'
            bindir.mkdir()
            log = root / 'commands.log'
            (bindir / 'git').write_text('''#!/bin/sh
printf 'git %s\\n' "$*" >> "$MOCK_GIT_LOG"
n=0
[ ! -f "$MOCK_COUNT" ] || n=$(cat "$MOCK_COUNT")
n=$((n+1))
echo "$n" > "$MOCK_COUNT"
[ "$n" -gt "$MOCK_GIT_FAILURES" ]
''')
            (bindir / 'sleep').write_text('''#!/bin/sh
printf 'sleep %s\\n' "$*" >> "$MOCK_GIT_LOG"
''')
            for f in bindir.iterdir():
                f.chmod(0o700)
            env = os.environ.copy()
            env.update({'GITHUB_EVENT_NAME': event, 'GITHUB_REF': ref,
                        'GITVERSE_PUSH_DELETED': deleted,
                        'MOCK_GIT_LOG': str(log), 'MOCK_COUNT': str(root/'count'),
                        'MOCK_GIT_FAILURES': str(failures),
                        'PATH': str(bindir) + os.pathsep + env.get('PATH', '')})
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', self.snippet],
                                    env=env, cwd=root, capture_output=True,
                                    text=True, timeout=15)
            return result.returncode, log.read_text().splitlines() if log.exists() else [], result.stdout

    def test_push_only_current_nested_branch_not_full_mirror(self):
        rc, lines, _ = self.run_snippet(ref='refs/heads/fix/a/b')
        self.assertEqual(rc, 0)
        self.assertEqual(lines, ['git push --force gitverse refs/heads/fix/a/b:refs/heads/fix/a/b'])
        self.assertNotIn('--prune', '\n'.join(lines))

    def test_push_only_changed_tag(self):
        rc, lines, _ = self.run_snippet(ref='refs/tags/v0.2.42')
        self.assertEqual(rc, 0)
        self.assertEqual(lines, ['git push --force gitverse refs/tags/v0.2.42:refs/tags/v0.2.42'])

    def test_deleted_branch_or_tag_removes_only_target_ref(self):
        for ref in ('refs/heads/feat/old', 'refs/tags/old-release'):
            with self.subTest(ref=ref):
                rc, lines, _ = self.run_snippet(ref=ref, deleted='true')
                self.assertEqual(rc, 0)
                self.assertEqual(lines, ['git push --force gitverse :' + ref])

    def test_manual_and_scheduled_full_prune_but_no_pull_refs(self):
        for event in ('schedule', 'workflow_dispatch'):
            with self.subTest(event=event):
                rc, lines, _ = self.run_snippet(event=event, ref='refs/heads/main')
                self.assertEqual(rc, 0)
                self.assertEqual(lines, [
                    'git push --force --prune gitverse refs/heads/*:refs/heads/* refs/tags/*:refs/tags/*'
                ])
                self.assertNotIn('refs/pull/', lines[0])

    def test_only_three_attempts_on_persistent_transport_failure(self):
        rc, lines, message = self.run_snippet(failures=9)
        self.assertEqual(rc, 1)
        self.assertEqual(len([x for x in lines if x.startswith('git ')]), 3)
        self.assertEqual([x for x in lines if x.startswith('sleep ')], ['sleep 15', 'sleep 30'])
        self.assertIn('failed after three attempts', message)

    def test_transient_transport_failure_recovers_without_secret_echo(self):
        rc, lines, message = self.run_snippet(failures=2)
        self.assertEqual(rc, 0)
        self.assertEqual(len([x for x in lines if x.startswith('git ')]), 3)
        self.assertNotIn('GITVERSE_TOKEN', message)

    def test_yaml_and_shell_structure_and_trigger_contract(self):
        proc = subprocess.run(['bash', '-n'], input=self.snippet,
                              text=True, capture_output=True, timeout=10)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for key in ('workflow_dispatch:', 'schedule:', 'cron:', 'concurrency:',
                    'cancel-in-progress: false', 'GITVERSE_PUSH_DELETED: ${{ github.event.deleted }}'):
            self.assertIn(key, self.workflow)
        self.assertNotIn('refs/pull/*:', self.snippet)
        self.assertIn('git push --force', self.snippet)


if __name__ == '__main__':
    unittest.main()
