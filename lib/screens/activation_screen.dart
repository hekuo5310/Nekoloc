import 'package:flutter/material.dart';

/// 账号待激活：提示查收邮件，并说明激活后即可登录。激活链接由站点邮件发送。
class ActivationScreen extends StatelessWidget {
  final String email;
  final String? message;

  const ActivationScreen({super.key, required this.email, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('请查收邮件')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 56),
            const SizedBox(height: 16),
            Text('激活邮件已发送到 $email',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(message ?? '请打开邮件，点击其中的激活链接，然后回到这里登录。'),
            const SizedBox(height: 8),
            const Text('没有收到？请检查垃圾邮件文件夹。', style: TextStyle(fontSize: 12)),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('返回登录'),
            ),
          ],
        ),
      ),
    );
  }
}
