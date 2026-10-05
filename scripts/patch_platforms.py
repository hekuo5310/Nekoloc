#!/usr/bin/env python3
"""
Nekoloc 平台补丁脚本（在 CI 中 `flutter create .` 生成平台目录后运行）：
- Android: applicationId、INTERNET 权限、应用名称、图标
- iOS:     显示名称、Bundle ID、图标
- macOS:   网络权限（沙盒）、产品名称、图标
- Windows: 应用名称
- Linux:   窗口标题
包名配置必须成功；其余步骤独立容错。
"""
import json
import os
import re
import sys

# Windows 控制台默认 cp1252，强制 UTF-8 防止中文输出崩溃
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

APP_LABEL = 'Nekoloc'
PROJECT_NAME = 'nodeloc_app'
ANDROID_PACKAGE = 'net.zerexa.nekoloc'
BUNDLE_ID = 'com.nodeloc.app'


def read(p):
    try:
        with open(p, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return None


def write(p, content):
    with open(p, 'w', encoding='utf-8') as f:
        f.write(content)


def step(name):
    def deco(fn):
        def wrapper(*a, **kw):
            try:
                fn(*a, **kw)
                print(f'[OK] {name}')
            except Exception as e:
                print(f'[SKIP] {name}: {e}')
        return wrapper
    return deco


# ---------------------------------------------------------------- Android

def patch_android_package():
    # applicationId is the public app identity. Keep the generated Kotlin
    # namespace and point the launcher at its fully qualified class.
    if not os.path.isdir('android'):
        return
    for p in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
        m = read(p)
        if m is None:
            continue
        namespace = re.search(r'\bnamespace\s*(?:=\s*)?[\"\']([^\"\']+)[\"\']', m)
        if namespace is None:
            raise ValueError('Android namespace 未找到，无法配置启动 Activity')
        m, count = re.subn(
            r'\bapplicationId\s*(?:=\s*)?([\"\'])[^\"\']+\1',
            lambda match: f'applicationId = "{ANDROID_PACKAGE}"'
                if p.endswith('.kts') else f'applicationId "{ANDROID_PACKAGE}"', m,
        )
        if count != 1:
            raise ValueError('Android applicationId 配置缺失或不唯一')
        manifest_path = 'android/app/src/main/AndroidManifest.xml'
        manifest = read(manifest_path)
        if manifest is None:
            raise FileNotFoundError(manifest_path)
        activity = namespace.group(1) + '.MainActivity'
        manifest = manifest.replace('android:name=".MainActivity"',
                                    f'android:name="{activity}"')
        if f'android:name="{activity}"' not in manifest:
            raise ValueError('Android MainActivity 配置与生成的 namespace 不一致')
        # Generated platform directories are disposable; keep the native bridge
        # in a tracked template and fail the build if it cannot be installed.
        kotlin_path = 'android/app/src/main/kotlin/' + namespace.group(1).replace('.', '/') + '/MainActivity.kt'
        if read(kotlin_path) is None:
            raise FileNotFoundError(kotlin_path)
        template_path = os.path.join(os.path.dirname(__file__), 'android', 'MainActivity.kt')
        template = read(template_path)
        if template is None or '__ANDROID_NAMESPACE__' not in template:
            raise ValueError('Android 更新来源桥接模板缺失')
        write(kotlin_path, template.replace('__ANDROID_NAMESPACE__', namespace.group(1)))
        write(p, m)
        write(manifest_path, manifest)
        print(f'[OK] Android applicationId = {ANDROID_PACKAGE}')
        return
    raise FileNotFoundError('android/app/build.gradle(.kts)')


@step('Android Manifest（INTERNET 权限 + 应用名）')
def patch_android():
    p = 'android/app/src/main/AndroidManifest.xml'
    m = read(p)
    if m is None:
        raise FileNotFoundError(p)
    if 'android.permission.INTERNET' not in m:
        m = m.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <uses-permission android:name="android.permission.INTERNET"/>',
            1,
        )
    m = m.replace(f'android:label="{PROJECT_NAME}"', f'android:label="{APP_LABEL}"')
    write(p, m)


@step('Android compileSdk 提升到 36（flutter_plugin_android_lifecycle 等插件要求）')
def patch_android_gradle():
    import re as _re
    for p in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
        m = read(p)
        if m is None:
            continue
        orig = m
        # Kotlin DSL: compileSdk = <n|flutter.compileSdkVersion>
        m = _re.sub(r'compileSdk\s*=\s*(?:flutter\.compileSdkVersion|\d+)',
                    'compileSdk = 36', m)
        # Groovy DSL: compileSdkVersion <n|flutter.compileSdkVersion>
        m = _re.sub(r'compileSdkVersion\s+(?:flutter\.compileSdkVersion|\d+)',
                    'compileSdkVersion 36', m)
        if m != orig:
            write(p, m)
            return
    raise FileNotFoundError('android/app/build.gradle(.kts)')


# ---------------------------------------------------------------- iOS

@step('iOS Info.plist / 工程（显示名 + Bundle ID）')
def patch_ios():
    p = 'ios/Runner/Info.plist'
    m = read(p)
    if m is not None:
        m = re.sub(
            r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
            r'\g<1>' + APP_LABEL + r'\g<2>',
            m,
        )
        m = re.sub(
            r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)',
            r'\g<1>' + APP_LABEL + r'\g<2>',
            m,
        )
        write(p, m)

    proj = 'ios/Runner.xcodeproj/project.pbxproj'
    m = read(proj)
    if m is not None:
        m = m.replace('com.nodeloc.' + PROJECT_NAME.replace('_', ''), BUNDLE_ID)
        m = m.replace('com.nodeloc.' + PROJECT_NAME, BUNDLE_ID)
        write(proj, m)


# ---------------------------------------------------------------- macOS

@step('macOS 沙盒网络权限 + 文件选择权限')
def patch_macos_entitlements():
    keys = (
        '\t<key>com.apple.security.network.server</key>\n'
        '\t<true/>\n'
        '\t<key>com.apple.security.network.client</key>\n'
        '\t<true/>\n'
        '\t<key>com.apple.security.files.user-selected.read-only</key>\n'
        '\t<true/>\n'
    )
    for name in ['DebugProfile.entitlements', 'Release.entitlements']:
        p = f'macos/Runner/{name}'
        m = read(p)
        if m is None:
            raise FileNotFoundError(p)
        if 'com.apple.security.network.client' not in m:
            m = m.replace('</dict>', keys + '</dict>')
        if 'com.apple.security.files.user-selected.read-only' not in m:
            m = m.replace(
                '</dict>',
                '\t<key>com.apple.security.files.user-selected.read-only</key>\n'
                '\t<true/>\n</dict>',
            )
        write(p, m)


@step('macOS 产品名称 / Bundle ID')
def patch_macos_config():
    p = 'macos/Runner/Configs/AppInfo.xcconfig'
    m = read(p)
    if m is None:
        raise FileNotFoundError(p)
    m = re.sub(r'(?m)^PRODUCT_NAME\s*=.*$', f'PRODUCT_NAME = {APP_LABEL}', m)
    m = re.sub(
        r'(?m)^PRODUCT_BUNDLE_IDENTIFIER\s*=.*$',
        f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}',
        m,
    )
    m = re.sub(
        r'(?m)^PRODUCT_COPYRIGHT\s*=.*$',
        'PRODUCT_COPYRIGHT = Copyright (c) 2026 Nekoloc Contributors.',
        m,
    )
    write(p, m)


# ---------------------------------------------------------------- Windows / Linux

@step('Windows 应用名称')
def patch_windows():
    for p in [
        'windows/runner/main.cpp',
        'windows/runner/CMakeLists.txt',
        'windows/runner/Runner.rc',
    ]:
        m = read(p)
        if m is None:
            continue
        m = m.replace(PROJECT_NAME, APP_LABEL)
        write(p, m)


@step('Linux 窗口标题')
def patch_linux():
    p = 'linux/runner/my_application.cc'
    m = read(p)
    if m is None:
        raise FileNotFoundError(p)
    m = m.replace(f'"{PROJECT_NAME}"', f'"{APP_LABEL}"')
    write(p, m)


# ---------------------------------------------------------------- 图标

@step('应用图标（Android mipmap / iOS & macOS AppIcon）')
def make_icons():
    try:
        from PIL import Image
    except Exception:
        print('  PIL 不可用，跳过图标生成')
        return
    src_p = 'assets/icon/app_icon.png'
    if not os.path.exists(src_p):
        raise FileNotFoundError(src_p)
    src = Image.open(src_p).convert('RGBA')

    if os.path.isdir('android/app/src/main/res'):
        sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
        for bucket, px in sizes.items():
            d = f'android/app/src/main/res/mipmap-{bucket}'
            os.makedirs(d, exist_ok=True)
            src.resize((px, px), Image.LANCZOS).save(f'{d}/ic_launcher.png')

    for platform, folder in [('ios', 'ios/Runner/Assets.xcassets/AppIcon.appiconset'),
                             ('macos', 'macos/Runner/Assets.xcassets/AppIcon.appiconset')]:
        if not os.path.isdir(folder):
            continue
        src.resize((1024, 1024), Image.LANCZOS).save(f'{folder}/icon-1024.png')
        write(f'{folder}/contents.json', json.dumps({
            'images': [
                {
                    'filename': 'icon-1024.png',
                    'idiom': 'universal',
                    'platform': platform,
                    'size': '1024x1024',
                }
            ],
            'info': {'author': 'xcode', 'version': 1},
        }, indent=2))


if __name__ == '__main__':
    only = sys.argv[1] if len(sys.argv) > 1 else None
    jobs = {
        'android-package': patch_android_package,
        'android': patch_android,
        'android-gradle': patch_android_gradle,
        'ios': patch_ios,
        'macos': patch_macos_entitlements,
        'macos-config': patch_macos_config,
        'windows': patch_windows,
        'linux': patch_linux,
        'icons': make_icons,
    }
    if only and only in jobs:
        jobs[only]()
    else:
        for fn in jobs.values():
            fn()
    print('平台补丁完成。')
