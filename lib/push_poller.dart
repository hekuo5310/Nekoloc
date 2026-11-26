import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api/discourse_api.dart';
import 'models.dart';
import 'push_watch.dart';
import 'system_notifier.dart';

/// 消息提醒的轮询核心，前台（AppState 定时器）与后台（workmanager）共用。
///
/// 水位线与基线保存在 SharedPreferences 里，两条路径读写同一份状态，
/// 所以前台和后台不会对同一条通知重复提醒。

const String _kWatermark = 'push_watermark';
const String _kBaseline = 'push_baseline';
const String _kReplies = 'push_replies';
const String _kLikes = 'push_likes';
const String _kMessages = 'push_messages';
const String _kSystem = 'push_system';

/// 当前保存的提醒类别设置。
PushSettings pushSettingsFromPrefs(SharedPreferences prefs) => PushSettings(
      replies: prefs.getBool(_kReplies) ?? true,
      likes: prefs.getBool(_kLikes) ?? true,
      messages: prefs.getBool(_kMessages) ?? true,
      system: prefs.getBool(_kSystem) ?? true,
    );

Future<void> savePushSettings(SharedPreferences prefs, PushSettings s) async {
  await prefs.setBool(_kReplies, s.replies);
  await prefs.setBool(_kLikes, s.likes);
  await prefs.setBool(_kMessages, s.messages);
  await prefs.setBool(_kSystem, s.system);
}

PushWatchState _readState(SharedPreferences prefs) => PushWatchState(
      watermark: prefs.getInt(_kWatermark) ?? 0,
      baselineDone: prefs.getBool(_kBaseline) ?? false,
    );

/// 清空基线与水位线（退出登录，或换账号时调用）。
Future<void> resetPushState(SharedPreferences prefs) async {
  await prefs.remove(_kWatermark);
  await prefs.remove(_kBaseline);
}

/// 拉取一次未读通知，返回需要提醒的条目，并推进水位线。
///
/// 失败时抛出异常，状态保持不变，下一次轮询会重新处理同一批通知。
Future<List<NotificationItem>> runPushPoll(
  SharedPreferences prefs,
  DiscourseApi api,
) async {
  final items = await api.notifications();
  final plan = planPushAlerts(items, _readState(prefs), pushSettingsFromPrefs(prefs));
  await prefs.setInt(_kWatermark, plan.next.watermark);
  await prefs.setBool(_kBaseline, plan.next.baselineDone);
  return plan.toAlert;
}

/// 后台 API 客户端：与 AppState 使用同一份本机保存的会话 token，
/// 保证后台拉取的登录状态与前台一致。
Future<DiscourseApi> backgroundApi(SharedPreferences prefs) async => DiscourseApi(
      base: 'https://www.nodeloc.com',
      token: prefs.getString('auth_token'),
    );

/// workmanager 的后台入口。必须是顶层函数，并带 vm:entry-point 标注。
@pragma('vm:entry-point')
void pushBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final prefs = await SharedPreferences.getInstance();
      final api = await backgroundApi(prefs);
      // 未登录时直接结束，不改动任何状态。
      if (!api.isLoggedIn) return true;
      final alerts = await runPushPoll(prefs, api);
      for (final n in alerts) {
        await SystemNotifier.show(n.id, pushAlertText(n));
      }
    } catch (_) {
      // 后台失败等待下一次调度。
    }
    return true;
  });
}

const String _kPeriodicTask = 'nodeloc-push-poll';

/// 在 Android 上注册 15 分钟一次的后台拉取；其他平台没有后台任务，只做前台轮询。
Future<void> initBackgroundPush() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(pushBackgroundDispatcher);
}

Future<void> scheduleBackgroundPush(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        _kPeriodicTask,
        'push-poll',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_kPeriodicTask);
    }
  } catch (_) {
    // 调度失败不影响前台轮询。
  }
}
