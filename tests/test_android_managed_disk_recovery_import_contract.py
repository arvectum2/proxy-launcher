"""Persistent-state proof and explicit recovery acknowledgement; device acceptance separate."""
from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
DISK=(BASE/'storage/ManagedPreferenceDiskVerifier.kt').read_text()
EVIDENCE=(BASE/'storage/ManagedRecoveryEvidence.kt').read_text()
REVIEW=(BASE/'storage/ManagedRecoveryReview.kt').read_text()
GATE=(BASE/'storage/ManagedCrashGate.kt').read_text()
TX=(BASE/'storage/ManagedCrashTransaction.kt').read_text()
STORE=(BASE/'storage/SecureProfileStore.kt').read_text()

class ManagedDiskRecoveryContract(unittest.TestCase):
    def test_disk_read_not_cache(self):
        for item in ('Files.notExists(backup,LinkOption.NOFOLLOW_LINKS)','channel.force(true)',
                     'syncDirectory(parent)','before.fileKey() == after.fileKey()',
                     'before.lastModifiedTime() == after.lastModifiedTime()','MAX_BYTES=16_777_216',
                     'Charsets.UTF_8.newDecoder()','External entity forbidden','entries.containsKey(key)'):
            self.assertIn(item,DISK)
        self.assertNotIn('getSharedPreferences',DISK)
        self.assertIn('managedDisk::matches',STORE)
        self.assertIn('managedBackend.read() == disk',STORE)
    def test_authenticated_recovery_evidence_before_commit(self):
        for item in ('AES/GCM/NoPadding','cipher.updateAAD(AAD)','SEALED_SIZE=93','MessageDigest.isEqual(before,digest)',
                     'MessageDigest.isEqual(after,digest)','values.toSortedMap()'):
            self.assertIn(item,EVIDENCE)
        self.assertLess(TX.index('ManagedRecoveryEvidence.create(expected,target).seal(evidenceKey())'),
                        TX.index('lease.beginMutation(evidence)'))
        self.assertLess(TX.index('lease.beginMutation(evidence)'),TX.index('ManagedPreferenceTransaction(backend).execute'))
        self.assertIn('managedEvidenceKey(false)',STORE)
    def test_recovery_is_explicit_and_stale_guarded(self):
        for item in ('if(consumed) return false','consumed=true','elapsed()-started in 0 until TTL_MS',
                     'gate.acknowledgePending(marker)','classify(readDurable())==state',
                     'state!=ManagedRecoveryEvidence.State.UNKNOWN'):
            self.assertIn(item,REVIEW)
        self.assertIn('MessageDigest.isEqual(expectedPayload,actual)',GATE)
        self.assertIn('removeMarker(actual)',GATE)
        self.assertIn('ByteBuffer.wrap(original)',GATE)
        for path in ('MainActivity.kt','tunnel/ProxyVpnService.kt'):
            text=(BASE/path).read_text()
            for name in ('prepareManagedRecoveryReview(','acknowledgeManagedRecovery(','applyManagedRefresh('):
                self.assertNotIn(name,text)
if __name__=='__main__': unittest.main()
