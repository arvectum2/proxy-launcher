"""VPN participant integration contract; on-device lifecycle acceptance remains separate."""
from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher'
VPN=(BASE/'tunnel/ProxyVpnService.kt').read_text()
STORE=(BASE/'storage/SecureProfileStore.kt').read_text()
LEASE=(BASE/'storage/ManagedVpnProcessLease.kt').read_text()
LOCATION=(BASE/'storage/ManagedProfileGateLocation.kt').read_text()
class ManagedVpnParticipantContract(unittest.TestCase):
    def test_same_gate_before_preferences(self):
        self.assertIn('managedProfileGate(appContext)',STORE)
        self.assertIn('noBackupFilesDir.toPath().resolve("managed-profile-gate")',LOCATION)
        self.assertLess(VPN.index('ManagedVpnProcessLease.enter(managedProfileGate(this))'),VPN.index('store = SecureProfileStore(this)'))
        self.assertIn('if (profileGateStatus == ManagedCrashGate.Status.ACQUIRED)',VPN)
    def test_retained_process_and_denied_start(self):
        self.assertIn('internal object ManagedVpnProcessLease',LEASE)
        self.assertIn('it.isHeld()',LEASE)
        self.assertNotIn('.close()',LEASE)
        self.assertNotIn('ManagedVpnProcessLease',VPN.split('override fun onDestroy()')[1].split('private fun')[0])
        start=VPN.split('override fun onStartCommand')[1].split('override fun onRevoke')[0]
        self.assertLess(start.index('profileGateStatus !='),start.index('store.clearVpnProcessRestartPending()'))
        self.assertIn('startForegroundCompat',start)
        self.assertIn('return START_NOT_STICKY',start)
        self.assertIn('terminateVpnProcess()',start)
if __name__=='__main__': unittest.main()
