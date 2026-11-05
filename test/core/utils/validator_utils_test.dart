import 'package:app_quanly_giaiui/core/utils/validator_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ValidatorUtils.validateAppointment', () {
    final now = DateTime(2026, 10, 18, 10);

    test('rejects an appointment in the past', () {
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 9, 59),
          now: now,
        ),
        isNotNull,
      );
    });

    test('accepts the current time and future appointments', () {
      expect(ValidatorUtils.validateAppointment(now, now: now), isNull);
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 10, 1),
          now: now,
        ),
        isNull,
      );
    });

    test('allows appointments only from 08:00 through 17:00', () {
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 8),
          now: DateTime(2026, 10, 18, 7),
        ),
        isNull,
      );
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 17),
          now: DateTime(2026, 10, 18, 7),
        ),
        isNull,
      );
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 7, 59),
          now: DateTime(2026, 10, 18, 7),
        ),
        isNotNull,
      );
      expect(
        ValidatorUtils.validateAppointment(
          DateTime(2026, 10, 18, 17, 1),
          now: DateTime(2026, 10, 18, 7),
        ),
        isNotNull,
      );
    });
  });

  group('ValidatorUtils.validatePhone', () {
    test('accepts common Vietnamese mobile formats', () {
      expect(ValidatorUtils.validatePhone('0901234567'), isNull);
      expect(ValidatorUtils.validatePhone('+84 901 234 567'), isNull);
      expect(ValidatorUtils.validatePhone('84-901-234-567'), isNull);
    });

    test('rejects empty and malformed phone numbers', () {
      expect(ValidatorUtils.validatePhone('  '), isNotNull);
      expect(ValidatorUtils.validatePhone('09012345678'), isNotNull);
      expect(ValidatorUtils.validatePhone('0201234567'), isNotNull);
    });
  });
}
