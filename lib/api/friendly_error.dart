import 'package:dio/dio.dart';

import 'discourse_api.dart';

/// 把任意异常转换为可直接展示给用户的中文文案。
///
/// 规则（对齐参考项目 `DiscourseError.messageRes`）：
/// - 站点返回的业务文案（如“标题太短”）原样展示——它是唯一能告诉用户如何修改的信息；
/// - HTTP 状态码、Dio/Socket 的英文原文、堆栈永远不进入界面；
/// - 无法归类时给出通用提示，而不是 `$e`。
String friendlyError(Object error, {String fallback = '操作失败，请稍后重试'}) {
  if (error is ApiException) return error.message;
  if (error is SecondFactorRequiredException) return error.message;
  if (error is DioException) return _dioMessage(error);
  return fallback;
}

String _dioMessage(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，请稍后重试';
    case DioExceptionType.connectionError:
      return '网络不可用，请检查网络连接';
    case DioExceptionType.cancel:
      return '操作已取消';
    default:
      return '网络异常，请稍后重试';
  }
}
