import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import patch_platforms  # noqa: E402
from patch_platforms import patch_gradle_build  # noqa: E402

KTS = '''android {
    namespace = "com.nodeloc.nodeloc_app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

flutter {
    source = "../.."
}
'''


class AndroidGradleTest(unittest.TestCase):
    def test_kts_compile_sdk_and_desugaring(self):
        out = patch_gradle_build(KTS, kts=True)
        self.assertIn('compileSdk = 37', out)
        self.assertIn('isCoreLibraryDesugaringEnabled = true', out)
        self.assertIn('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:', out)

    def test_idempotent(self):
        once = patch_gradle_build(KTS, kts=True)
        self.assertEqual(once, patch_gradle_build(once, kts=True))

    def test_missing_compile_options_fails(self):
        with self.assertRaises(ValueError):
            patch_gradle_build('android {\n    compileSdk = 36\n}\n', kts=True)

    def test_other_platforms_without_android_dir_are_skipped(self):
        cwd = os.getcwd()
        with tempfile.TemporaryDirectory() as d:
            os.chdir(d)
            try:
                patch_platforms.patch_android_gradle()
            finally:
                os.chdir(cwd)


if __name__ == '__main__':
    unittest.main()
