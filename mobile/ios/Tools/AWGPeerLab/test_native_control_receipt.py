import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from native_control_receipt import REQUIRED, validate_native_control

class NativeControlReceiptTests(unittest.TestCase):
    def test_complete(self):
        validate_native_control(dict.fromkeys(REQUIRED,True)|{"nativeFailure":False})
    def test_missing_or_contradictory_receipt(self):
        good=dict.fromkeys(REQUIRED,True)|{"nativeFailure":False}
        for key in good:
            for value in (None, 1, 0, "true"):
                with self.assertRaises(RuntimeError):validate_native_control(good|{key:value})
        for key in REQUIRED:
            with self.assertRaises(RuntimeError):validate_native_control(good|{key:False})
        with self.assertRaises(RuntimeError):validate_native_control(good|{"nativeFailure":True})
