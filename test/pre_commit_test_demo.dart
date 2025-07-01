import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pre-commit Hook Demo', () {
    test('this test will intentionally fail to demo the pre-commit hook', () {
      // This test is designed to fail to show how pre-commit hooks work
      expect(1 + 1, equals(3), reason: 'This is an intentional failure for demo purposes');
    });
  });
} 