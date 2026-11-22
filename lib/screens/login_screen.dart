import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/discourse_api.dart';
import '../app_state.dart';
import 'password_reset_screen.dart';
import 'signup_screen.dart';
import '../theme.dart';
import '../api/friendly_error.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _totpCtrl = TextEditingController();
  bool _obscure = true;
  bool _showTotp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _pwdCtrl.dispose();
    _totpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _loginCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (login.isEmpty || pwd.isEmpty) {
      setState(() => _error = '请输入用户名 / 邮箱和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      await app.login(login, pwd, _showTotp ? _totpCtrl.text : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('欢迎回来，${app.user?.username ?? ''}')),
        );
      }
    } on SecondFactorRequiredException catch (e) {
      setState(() {
        _busy = false;
        _showTotp = true;
        _error = '${e.message}\n已为你展开动态口令（2FA）输入框';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  /// 浏览器授权登录：支持第三方 OAuth（LinuxDo Connect 等）、邮箱登录链接等全部方式
  Future<void> _browserLogin() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.loginViaBrowser(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('欢迎回来，${app.user?.username ?? ''}')),
        );
      }
    } catch (e) {
      final cancelled = e.toString() == '已取消授权';
      if (!cancelled && mounted) {
        setState(() => _error = '浏览器登录失败：${friendlyError(e, fallback: '请稍后重试')}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final siteTitle = app.siteInfo?.title ?? 'NodeLoc';
    final siteDesc =
        app.siteInfo?.description ?? '自由、平等、友好、开放、有趣的互联网交流社区';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset('assets/icon/app_icon.png',
                            width: 76, height: 76),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nekoloc',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: scheme.primary)),
                          const SizedBox(height: 2),
                          Text(siteTitle,
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            siteDesc,
                            style: TextStyle(
                                fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _loginCtrl,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: '用户名或邮箱',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pwdCtrl,
                    obscureText: _obscure,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      hintText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _showTotp
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: TextField(
                              controller: _totpCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '动态口令（2FA 验证码）',
                                prefixIcon: Icon(Icons.password_outlined),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showTotp = !_showTotp),
                      icon: const Icon(Icons.vpn_key_outlined, size: 16),
                      label: Text(
                        _showTotp ? '收起 2FA' : '使用动态口令（2FA）',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style:
                            TextStyle(fontSize: 13, color: scheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white))
                        : const Text('登录'),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SignupScreen())),
                        child: const Text('注册新账号'),
                      ),
                      const Text('·'),
                      TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PasswordResetScreen())),
                        child: const Text('忘记密码'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _browserLogin,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: scheme.primary.withOpacity(0.5)),
                      foregroundColor: scheme.primary,
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 19),
                    label: const Text('浏览器授权登录'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '浏览器授权登录支持第三方账号（LinuxDo Connect 等）、邮箱登录链接、\n'
                    '2FA 等站点提供的全部登录方式，授权后自动返回本应用',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant.withOpacity(0.85),
                        height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: NL.orangeDark.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Nekoloc 为社区第三方开源客户端，与 NodeLoc 官方无关',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
