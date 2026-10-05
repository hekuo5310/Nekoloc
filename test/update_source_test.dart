import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/update_checker.dart';
import 'package:nodeloc_app/update_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var calls = <String>[];
  String? installer;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installer = 'com.android.vending';
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateSource.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'installerPackage') return installer;
      if (call.method == 'openPlayStore') return true;
      throw MissingPluginException();
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateSource.channel, null);
  });

  test('Play installs skip GitHub release checks', () async {
    expect(await UpdateSource.usesPlay(), isTrue);
    expect(await UpdateChecker.fetchLatest(), isNull);
    expect(calls, ['installerPackage', 'installerPackage']);
  });

  test('APK installers continue to use GitHub', () async {
    installer = 'com.google.android.packageinstaller';
    expect(await UpdateSource.usesPlay(), isFalse);
    installer = null;
    expect(await UpdateSource.usesPlay(),
        const bool.fromEnvironment('PLAY_DISTRIBUTION'));
  });

  test('desktop does not invoke the Android installer API', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await UpdateSource.usesPlay(), isFalse);
    expect(calls, isEmpty);
  });

  test('download action for Play installs opens the store', () async {
    await UpdateChecker.openDownload(UpdateInfo(
      version: '99.0.0',
      releaseNotes: '',
      releaseUrl: 'https://github.com/hekuo5310/Nekoloc/releases',
      assetUrls: {},
    ));
    expect(calls, ['installerPackage', 'openPlayStore']);
  });

  test('missing installer integration falls back safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateSource.channel, null);
    expect(await UpdateSource.usesPlay(),
        const bool.fromEnvironment('PLAY_DISTRIBUTION'));
  });
}
