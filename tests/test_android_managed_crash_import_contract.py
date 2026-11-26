"""Crash gate source contract; Android durable storage and VPN integration remain separate."""
from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
GATE=(BASE/'storage/ManagedCrashGate.kt').read_text()
TX=(BASE/'storage/ManagedCrashTransaction.kt').read_text()

class ManagedCrashContract(unittest.TestCase):
    def test_stable_lock_and_fail_closed_marker(self):
        for token in ('heldPaths.add(lockPath)','channel.tryLock()','LinkOption.NOFOLLOW_LINKS',
                      'Files.notExists(markerPath','StandardOpenOption.CREATE_NEW','file.force(true)',
                      'syncDirectory(directory)','markerDurable = true','!markerDurable','verifyDurableOutcome'):
            self.assertIn(token,GATE)
        self.assertNotIn('Files.delete(lockPath)',GATE)
    def test_marker_before_commit_and_persistent_verification(self):
        self.assertLess(TX.index('lease.beginMutation()'),TX.index('ManagedPreferenceTransaction(backend).execute'))
        self.assertIn('!durable(expected)',TX)
        self.assertIn('lease.resolve { permitted() && durable(verified) }',TX)
        self.assertIn('RECOVERY_REQUIRED -> return@use Outcome.RECOVERY_REQUIRED',TX)
    def test_not_enabled_in_runtime(self):
        for path in ('MainActivity.kt','storage/SecureProfileStore.kt','tunnel/ProxyVpnService.kt'):
            self.assertNotIn('ManagedCrashTransaction(', (BASE/path).read_text())
            self.assertNotIn('ManagedCrashGate(', (BASE/path).read_text())
if __name__=='__main__': unittest.main()
