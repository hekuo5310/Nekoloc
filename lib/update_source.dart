import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Use the installer of record; Play builds also have a fallback when Android
/// cannot report an installer (for example after a device restore).
class UpdateSource {
  static const channel = MethodChannel('net.zerexa.nekoloc/update_source');
  static const _playBuild = bool.fromEnvironment('PLAY_DISTRIBUTION');
  static const playPackage = 'net.zerexa.nekoloc';

  static Future<bool> usesPlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final installer = await channel.invokeMethod<String>('installerPackage');
      if (installer != null && installer.isNotEmpty) {
        return installer == 'com.android.vending';
      }
    } on PlatformException {
      // Fall back to the distribution marker rather than a GitHub APK.
    } on MissingPluginException {
      // Older platform integrations may not expose the installer yet.
    }
    return _playBuild;
  }

  /// The store determines availability for the user's production/testing track.
  static Future<bool> openPlay() async {
    try {
      if (await channel.invokeMethod<bool>('openPlayStore') == true) return true;
    } on PlatformException {
      // Keep the HTTPS listing available if the store app cannot be opened.
    } on MissingPluginException {
      // Fallback for platform integrations without the native handler.
    }
    return launchUrl(
      Uri.https('play.google.com', '/store/apps/details', {'id': playPackage}),
      mode: LaunchMode.externalApplication,
    );
  }
}
