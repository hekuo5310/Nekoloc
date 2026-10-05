import contextlib
import os
from pathlib import Path
import tempfile
import unittest

import patch_platforms


class AndroidUpdateBridgeTest(unittest.TestCase):
    def test_installs_bridge_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            gradle = root / 'android/app/build.gradle.kts'
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            activity = root / 'android/app/src/main/kotlin/com/nodeloc/nodeloc_app/MainActivity.kt'
            for file in (gradle, manifest, activity):
                file.parent.mkdir(parents=True, exist_ok=True)
            gradle.write_text('namespace = "com.nodeloc.nodeloc_app"\napplicationId = "com.nodeloc.nodeloc_app"\n')
            manifest.write_text('<activity android:name=".MainActivity"/>')
            activity.write_text('package com.nodeloc.nodeloc_app\nclass MainActivity : FlutterActivity()')
            previous = os.getcwd()
            try:
                os.chdir(root)
                with contextlib.redirect_stdout(None):
                    patch_platforms.patch_android_package()
                    first = activity.read_text()
                    patch_platforms.patch_android_package()
                self.assertEqual(activity.read_text(), first)
                self.assertIn('package com.nodeloc.nodeloc_app', first)
                self.assertNotIn('__ANDROID_NAMESPACE__', first)
                self.assertIn('getInstallSourceInfo(packageName)', first)
                self.assertIn('net.zerexa.nekoloc', gradle.read_text())
                self.assertIn('com.nodeloc.nodeloc_app.MainActivity', manifest.read_text())
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
