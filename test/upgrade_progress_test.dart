import 'package:flutter_test/flutter_test.dart';
import 'package:nodeloc_app/account_models.dart';

void main() {
  test('升级进度按已满足项计算比例，全部满足才算完成', () {
    final p = UpgradeProgress.fromJson({
      'current_level': 2,
      'total_conditions': 4,
      'met_count': 3,
      'conditions': [
        {'label': '阅读', 'group': 'activity', 'comparison': 'min', 'value': 9, 'target': 10, 'met': false},
        {'label': '举报', 'group': 'standing', 'comparison': 'max', 'value': 0, 'target': 0, 'met': 1},
      ],
    });
    expect(p.fraction, closeTo(0.75, 1e-9));
    expect(p.allMet, isFalse);
    expect(p.conditions.first.met, isFalse);
    expect(p.conditions[1].comparison, 'max');
    expect(p.conditions[1].met, isTrue);
  });

  test('没有要求时比例为 0，且不算完成', () {
    final p = UpgradeProgress.fromJson({'total_conditions': 0, 'met_count': 0});
    expect(p.fraction, 0);
    expect(p.allMet, isFalse);
  });
}
