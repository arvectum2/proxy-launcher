"""Managed profile source is signed, bounded and not connected to payments."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
CODE=(ROOT/'mobile/ios/SharedCore/ManagedProfileContract.swift').read_text(encoding='utf-8')
DOC=(ROOT/'docs/APL_IOS_MANAGED_MARKETPLACE_ARCH_2026-10-31.md').read_text(encoding='utf-8')
class ManagedContractTests(unittest.TestCase):
    def test_signature_and_source_pinning_before_accept(self):
        for required in ['import CryptoKit','isValidSignature','trustedKey:','keyID:',
                         'maxPayload = 128 * 1024','maxProfiles = 32','validSource',
                         'issuerMismatch', 'credentialRef']:
            self.assertIn(required,CODE)
        for forbidden in ['URLSession','SecItemAdd','StoreKit']:
            self.assertNotIn(forbidden,CODE)
    def test_no_production_claims_or_silent_downgrade(self):
        for expected in ['Set(root.keys) == Set(', 'Set($0.keys) == Set(',
                         'Set(manifest.profiles.map', 'requiresApproval']:
            self.assertIn(expected,CODE)
        self.assertIn('НЕ запуск продаж',DOC)
        self.assertIn('не реализованы',DOC)
if __name__ == '__main__': unittest.main()
