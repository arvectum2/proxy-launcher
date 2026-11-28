from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher/storage'
STORE=(BASE/'SecureProfileStore.kt').read_text()
class OrdinaryWriteContract(unittest.TestCase):
    def test_all_ordinary_mutators_use_shared_guard(self):
        for name in ('saveProfile','appendImportedProfiles','setAutoProfileSelection','setLastAutoProfileId','setActiveProfile','deleteProfile','setPrimaryProfileId','setRestorePolicy','markRecentlyFailedProfile','clearRecentlyFailedProfile','setLastFailoverAtMs','markVpnProcessRestartPending','consumeVpnProcessRestartPending','clearVpnProcessRestartPending','setSiteExclusions','setAppExclusions'):
            body=STORE.split('fun '+name+'(',1)[1].split('\n    }',1)[0]
            self.assertIn('ordinaryWrite {',body,name)
    def test_managed_and_ordinary_share_monitor(self):
        for name in ('inspectManagedCrash','prepareManagedRecoveryReview','acknowledgeManagedRecovery','prepareManagedRefresh','applyManagedRefresh','rollbackManagedRefresh','prepareManagedOwnership','confirmManagedOwnership'):
            body=STORE.split('fun '+name+'(',1)[1].split('\n    }',1)[0]
            self.assertIn('synchronized(ManagedOrdinaryWriteGuard.monitor)',body,name)
    def test_constructor_migration_and_read_only_decryption(self):
        self.assertIn('ordinaryWriteIfAvailable {',STORE.split('    init {',1)[1].split('\n    }',1)[0])
        self.assertIn('ordinaryWriteIfAvailable {',STORE.split('private fun ensureLegacyProfileIndexed()',1)[1].split('\n    }',1)[0])
        self.assertNotIn('.apply()',STORE)
        self.assertIn('key: SecretKey = existingCredentialKey()',STORE)
        self.assertEqual(2,STORE.count('Managed profile requires review'))
if __name__=='__main__': unittest.main()
