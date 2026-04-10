#!/usr/bin/env python3
import unittest
from extract_steps import clean_regex

class TestStepExtractor(unittest.TestCase):
    def test_basic_cleaning(self):
        self.assertEqual(clean_regex("^the elevator is idle$"), "the elevator is idle")
        
    def test_named_capture_cleaning(self):
        # Case from user example
        self.assertEqual(
            clean_regex('^the Elevator Vault stores "Floor (?<floor>.+)"$'),
            "the Elevator Vault stores <floor>"
        )
        
    def test_multiple_named_captures(self):
        self.assertEqual(
            clean_regex('^the "(?<attr>.+)" should become "(?<val>.+)"$'),
            "the <attr> should become <val>"
        )
        
    def test_unquoted_named_capture(self):
        self.assertEqual(
            clean_regex('^a request for floor (?<target>.+) is received$'),
            "a request for floor <target> is received"
        )
        
    def test_keep_alternatives(self):
        # Alternatives should be kept as is
        self.assertEqual(
            clean_regex('^the system (starts|reboots)$'),
            "the system (starts|reboots)"
        )

    def test_complex_quoted_string(self):
        # Ensure we don't over-clean if there's no capture group
        self.assertEqual(
            clean_regex('^the "door" is "closed"$'),
            'the "door" is "closed"'
        )

    def test_mixed_quoted_and_unquoted(self):
        self.assertEqual(
            clean_regex('^the "(?<attr>.+)" is active on floor (?<floor>.+)$'),
            "the <attr> is active on floor <floor>"
        )

if __name__ == "__main__":
    unittest.main()
