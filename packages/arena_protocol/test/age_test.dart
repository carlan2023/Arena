import 'package:arena_protocol/arena_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('old enough on the birthday, not the day before', () {
    final birth = DateTime.utc(2001, 10, 23);
    expect(isOldEnough(birth, DateTime.utc(2026, 10, 22), 25), isFalse);
    expect(isOldEnough(birth, DateTime.utc(2026, 10, 23), 25), isTrue);
    expect(isOldEnough(birth, DateTime.utc(2026, 10, 24, 23), 25), isTrue);
  });

  test('29 February is 1 March in a year that is not a leap year', () {
    final birth = DateTime.utc(2000, 2, 29);
    expect(isOldEnough(birth, DateTime.utc(2025, 2, 28), 25), isFalse);
    expect(isOldEnough(birth, DateTime.utc(2025, 3, 1), 25), isTrue);
  });

  test('parseDateOfBirth rejects a date that is not real', () {
    expect(parseDateOfBirth('1990-01-01'), DateTime.utc(1990, 1, 1));
    expect(parseDateOfBirth('1990-02-31'), isNull);
    expect(parseDateOfBirth('1990-13-01'), isNull);
    expect(parseDateOfBirth('90-01-01'), isNull);
    expect(formatDateOfBirth(DateTime.utc(1990, 4, 1, 15)), '1990-04-01');
  });

  test('limits round trip, and a user date of birth is optional', () {
    final pendingAt = DateTime.utc(2026, 10, 23, 12);
    final limits = LimitsView(
      daily: 1000,
      weekly: 7000,
      monthly: 30000,
      pending: PendingLimitsView(at: pendingAt, daily: 2000),
      excludedUntil: DateTime.utc(2026, 10, 30),
      permanent: false,
    );
    expect(LimitsView.fromJson(limits.toJson()).toJson(), limits.toJson());
    expect(limits.toJson().containsKey('pending'), isTrue);
    final open = const LimitsView(
      daily: 1,
      weekly: 2,
      monthly: 3,
      permanent: false,
    );
    expect(open.toJson().containsKey('pending'), isFalse);
    expect(open.toJson().containsKey('excludedUntil'), isFalse);

    const withDob = UserView(
      id: 'u',
      phone: '+256772000001',
      displayName: 'Amina',
      dateOfBirth: '1990-01-01',
    );
    expect(UserView.fromJson(withDob.toJson()).dateOfBirth, '1990-01-01');
    const without = UserView(id: 'u', phone: '', displayName: 'G');
    expect(without.toJson().containsKey('dateOfBirth'), isFalse);
    expect(
      UserView.fromJson({
        'id': 'u',
        'phone': '',
        'displayName': 'G',
      }).dateOfBirth,
      isNull,
    );
  });
}
