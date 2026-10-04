#!/usr/bin/env python3
"""Configure Flutter's generated Kotlin Gradle project without storing passwords."""
import argparse
import base64
import os
from pathlib import Path
import re
import subprocess
import zipfile

KEY_ENV = ('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')


def required_env():
    missing = [name for name in KEY_ENV if not os.environ.get(name)]
    if missing:
        raise ValueError('Missing secrets: ' + ', '.join(missing))
    path = Path(os.environ.get('ANDROID_KEYSTORE_PATH', ''))
    if not path.is_file():
        raise ValueError('Upload keystore is missing')
    return path


def patch_gradle(text):
    marker = '// Nekoloc upload signing'
    if marker in text:
        raise ValueError('Signing already configured; regenerate the Android project')
    if len(re.findall(r'\bbuildTypes\s*\{', text)) != 1:
        raise ValueError('Expected one buildTypes block in generated Kotlin Gradle')
    pattern = r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'
    if len(re.findall(pattern, text)) != 1:
        raise ValueError('Expected one default debug release signing configuration')
    block = '''    // Nekoloc upload signing
    signingConfigs {
        create("upload") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") ?: error("Missing upload keystore"))
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: error("Missing store password")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: error("Missing key alias")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: error("Missing key password")
        }
    }

'''
    text = re.sub(pattern, 'signingConfig = signingConfigs.getByName("upload")', text)
    return re.sub(r'(?m)^\s*buildTypes\s*\{', lambda m: '\n' + block + '    buildTypes {', text, count=1)


def keytool(*args):
    result = subprocess.run(['keytool', *args], capture_output=True, text=True)
    if result.returncode:
        # Do not print external errors that might contain credential arguments.
        raise ValueError('Keystore validation failed; check the store password and alias')
    return result.stdout


def certificate(text):
    matches = re.findall(r'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', text, re.S)
    if not matches:
        raise ValueError('Signing certificate was not found')
    return [base64.b64decode(re.sub(r'\s+', '', value), validate=True) for value in matches]


def verify_bundle(bundle):
    path = required_env()
    with zipfile.ZipFile(bundle) as archive:
        if not any(name.startswith('META-INF/') and name.endswith('.SF') for name in archive.namelist()):
            raise ValueError('AAB is unsigned')
    result = subprocess.run(['jarsigner', '-verify', str(bundle)], capture_output=True, text=True,
                            env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode or 'jar verified.' not in result.stdout:
        raise ValueError('AAB signature verification failed')
    expected = certificate(keytool('-exportcert', '-rfc', '-keystore', str(path),
                                  '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
                                  '-alias', os.environ['ANDROID_KEY_ALIAS']))[0]
    actual = certificate(keytool('-printcert', '-jarfile', str(bundle), '-rfc'))
    if expected not in actual:
        raise ValueError('AAB was not signed by the configured upload key')
    print('AAB upload signature verified')


def configure():
    path = required_env()
    keytool('-list', '-keystore', str(path), '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
            '-alias', os.environ['ANDROID_KEY_ALIAS'])
    gradle = Path('android/app/build.gradle.kts')
    patched = patch_gradle(gradle.read_text())
    gradle.write_text(patched)
    print('Upload signing configured (credentials remain in environment variables)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    try:
        verify_bundle(args.verify) if args.verify else configure()
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from None
