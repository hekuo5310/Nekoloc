import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 系统级通知（通知栏 / 通知中心）。
///
/// 平台不支持或权限被拒绝时全部静默降级：提醒仍会以应用内横幅的形式出现，
/// 不会因为通知失败而影响轮询或界面。
class SystemNotifier {
  SystemNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void>? _init;

  static Future<void> init() => _init ??= _doInit();

  static Future<void> _doInit() async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );
      await _plugin.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
        linux: LinuxInitializationSettings(defaultActionName: '打开'),
      ));
      // Android 13+ 需要运行时授权；其他平台此调用为空操作。
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 展示一条提醒。相同 [id] 会替换旧的提醒，避免重复。
  static Future<void> show(int id, String text) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: 'Nekoloc',
        body: text,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'nodeloc_messages',
            '消息提醒',
            channelDescription: '回复、点赞、私信等新通知',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (_) {
      // 单条通知失败不影响其他提醒。
    }
  }
}
