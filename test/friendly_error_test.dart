import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/api/discourse_api.dart';
import 'package:nodeloc_app/api/friendly_error.dart';

DioException _dio(DioExceptionType type, {String? message}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      message: message,
    );

void main() {
  test('站点业务文案原样展示', () {
    expect(friendlyError(ApiException('标题太短')), '标题太短');
  });

  test('状态码不进入界面', () {
    final e = ApiException('请求失败，请稍后重试', 500);
    expect(friendlyError(e), isNot(contains('500')));
  });

  test('Dio 英文原文不进入界面', () {
    final e = _dio(DioExceptionType.connectionError, message: 'SocketException: Failed host lookup');
    final text = friendlyError(e);
    expect(text, '网络不可用，请检查网络连接');
    expect(text, isNot(contains('Socket')));
  });

  test('超时归为连接超时', () {
    expect(friendlyError(_dio(DioExceptionType.receiveTimeout)), '连接超时，请稍后重试');
    expect(friendlyError(_dio(DioExceptionType.sendTimeout)), '连接超时，请稍后重试');
  });

  test('未知异常使用调用方给出的兜底文案', () {
    expect(friendlyError(StateError('boom')), '操作失败，请稍后重试');
    expect(friendlyError(StateError('boom'), fallback: '登录失败'), '登录失败');
  });
}
