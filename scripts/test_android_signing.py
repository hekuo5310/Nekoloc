import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from android_signing import patch_gradle, verify_bundle

TEMPLATE = '''plugins { id("com.android.application") }
android {
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'''


class GradleSigningTest(unittest.TestCase):
    def test_switches_release_to_upload_and_keeps_secrets_out_of_source(self):
        result = patch_gradle(TEMPLATE)
        self.assertIn('signingConfig = signingConfigs.getByName("upload")', result)
        self.assertLess(result.index('signingConfigs {'), result.index('buildTypes {'))
        for name in ['ANDROID_KEYSTORE_PATH', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']:
            self.assertIn(f'System.getenv("{name}")', result)
        self.assertNotIn('getByName("debug")', result)

    def test_rejects_changed_flutter_template(self):
        for text in [TEMPLATE.replace('"debug"', '"release"'), TEMPLATE + TEMPLATE,
                     TEMPLATE.replace('buildTypes', 'otherTypes')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                patch_gradle(text)

    def test_rejects_second_patch(self):
        with self.assertRaises(ValueError):
            patch_gradle(patch_gradle(TEMPLATE))


@unittest.skipUnless(shutil.which('keytool') and shutil.which('jarsigner'), 'JDK required')
class BundleSignatureTest(unittest.TestCase):
    def test_real_signature_unsigned_tampered_and_wrong_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            keystore = root / 'test.jks'
            env = {**os.environ, 'ANDROID_KEYSTORE_PATH': str(keystore),
                   'ANDROID_KEYSTORE_PASSWORD': 'test-only-password',
                   'ANDROID_KEY_ALIAS': 'upload', 'ANDROID_KEY_PASSWORD': 'test-only-password'}
            for alias in ['upload', 'other']:
                subprocess.run(['keytool', '-genkeypair', '-keystore', str(keystore),
                                '-storetype', 'JKS', '-alias', alias, '-keyalg', 'RSA', '-keysize', '2048',
                                '-validity', '30', '-dname', 'CN=CI test', '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
                                '-keypass:env', 'ANDROID_KEY_PASSWORD'], env=env, check=True, capture_output=True)
            bundle = root / 'test.aab'
            with zipfile.ZipFile(bundle, 'w') as archive:
                archive.writestr('base/manifest/AndroidManifest.xml', 'test fixture')
            with patch.dict(os.environ, env):
                with self.assertRaisesRegex(ValueError, 'unsigned'):
                    verify_bundle(bundle)
                subprocess.run(['jarsigner', '-keystore', str(keystore), '-storepass:env',
                                'ANDROID_KEYSTORE_PASSWORD', '-keypass:env', 'ANDROID_KEY_PASSWORD',
                                str(bundle), 'upload'], env=env, check=True, capture_output=True)
                verify_bundle(bundle)
                with patch.dict(os.environ, {'ANDROID_KEY_ALIAS': 'other'}):
                    with self.assertRaisesRegex(ValueError, 'configured upload key'):
                        verify_bundle(bundle)
                corrupted = root / 'corrupted.aab'
                with zipfile.ZipFile(bundle) as source, zipfile.ZipFile(corrupted, 'w') as target:
                    for name in source.namelist():
                        target.writestr(name, 'tampered' if name.endswith('.xml') else source.read(name))
                with self.assertRaisesRegex(ValueError, 'verification failed'):
                    verify_bundle(corrupted)


if __name__ == '__main__':
    unittest.main()
