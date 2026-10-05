from datetime import datetime, timezone
import unittest

from play_metadata import metadata

SHA = 'c9db062e6b3b5204bf445bd864491199d3d05a86'
NOW = datetime(2026, 10, 5, tzinfo=timezone.utc).timestamp()


class PlayMetadataTest(unittest.TestCase):
    def test_main_commit_is_open_testing_with_last_six_digits(self):
        result = metadata('refs/heads/main', SHA, now=NOW)
        self.assertEqual(result['track'], 'beta')
        self.assertEqual(result['version_name'], 'd05a86')
        self.assertEqual(result['release_name'], 'd05a86')
        self.assertTrue(result['version_code'].isdigit())
        self.assertGreater(int(result['version_code']), 11)

    def test_tag_is_production(self):
        result = metadata('refs/tags/v1.3.7', SHA, now=NOW)
        self.assertEqual(result['track'], 'production')
        self.assertEqual(result['version_name'], '1.3.7')
        self.assertEqual(result['release_name'], 'v1.3.7')

    def test_ci_created_tag_is_production_when_called_from_main(self):
        result = metadata('refs/heads/main', SHA, 'v1.3.7', now=NOW)
        self.assertEqual(result['track'], 'production')
        self.assertEqual(result['version_name'], '1.3.7')

    def test_next_serial_run_gets_higher_code_across_tracks(self):
        beta = metadata('refs/heads/main', SHA, now=NOW)
        production = metadata('refs/tags/v1.3.7', SHA, now=NOW + 1)
        self.assertGreater(int(production['version_code']), int(beta['version_code']))

    def test_untrusted_ref_invalid_sha_and_invalid_tag_fail(self):
        for ref, sha, tag in [('refs/heads/dev', SHA, ''), ('refs/tags/other', SHA, ''),
                              ('refs/heads/main', 'd05a86', ''), ('refs/heads/main', SHA, 'v1.3.7\ntrack=beta')]:
            with self.subTest(ref=ref,sha=sha,tag=tag), self.assertRaises(ValueError):
                metadata(ref, sha, tag, now=NOW)

    def test_invalid_clock_fails_before_build(self):
        with self.assertRaises(ValueError):
            metadata('refs/heads/main', SHA, now=0)


if __name__ == '__main__':
    unittest.main()
