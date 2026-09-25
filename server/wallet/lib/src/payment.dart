enum PaymentStatus { pending, succeeded, failed }

class DepositRequest {
  /// A UUID v4, used as the provider's reference.
  final String paymentId;
  final int amount;

  /// 256 followed by 9 digits.
  final String msisdn;
  final String currency;

  const DepositRequest({
    required this.paymentId,
    required this.amount,
    required this.msisdn,
    this.currency = 'UGX',
  });
}

/// The provider's id for the request.
class ProviderAck {
  final String providerRef;

  const ProviderAck(this.providerRef);
}

class ProviderStatus {
  final String providerRef;
  final PaymentStatus status;
  final String? reason;

  /// The amount the provider reports, when it reports one.
  final int? amount;

  const ProviderStatus({
    required this.providerRef,
    required this.status,
    this.reason,
    this.amount,
  });

  @override
  String toString() => 'ProviderStatus($providerRef, ${status.name}, $reason)';
}

class CallbackEvent {
  final String providerRef;
  final PaymentStatus status;
  final int? amount;

  const CallbackEvent({
    required this.providerRef,
    required this.status,
    this.amount,
  });
}

/// The provider definitely refused the request (HTTP 4xx or an explicit
/// failure answer). The payment can be marked failed.
class ProviderRejectedException implements Exception {
  final String message;

  const ProviderRejectedException(this.message);

  @override
  String toString() => 'ProviderRejectedException: $message';
}

/// The provider could not be reached or answered 5xx. The outcome is unknown,
/// so the payment stays pending.
class ProviderUnavailableException implements Exception {
  final String message;

  const ProviderUnavailableException(this.message);

  @override
  String toString() => 'ProviderUnavailableException: $message';
}

abstract interface class PaymentProvider {
  /// fake, mtn, airtel
  String get name;

  /// Throws ProviderRejectedException or ProviderUnavailableException.
  Future<ProviderAck> requestDeposit(DepositRequest request);

  /// Throws ProviderUnavailableException when the answer is unknown.
  Future<ProviderStatus> checkStatus(String providerRef);

  /// Parses and checks a callback. Returns null for a body it cannot trust or
  /// read.
  CallbackEvent? parseCallback(Map<String, String> headers, String body);
}

/// Bad amount, bad msisdn or unknown provider (bad_request), an unreadable
/// callback (bad_callback) or an unknown payment id (not_found).
class PaymentException implements Exception {
  final String code;
  final String message;

  const PaymentException(this.code, this.message);

  @override
  String toString() => 'PaymentException($code): $message';
}

class Payment {
  final String id;
  final String userId;
  final String provider;
  final String? providerRef;
  final int amount;
  final String msisdn;
  final PaymentStatus status;
  final DateTime createdAt;
  final DateTime? settledAt;

  const Payment({
    required this.id,
    required this.userId,
    required this.provider,
    this.providerRef,
    required this.amount,
    required this.msisdn,
    required this.status,
    required this.createdAt,
    this.settledAt,
  });

  Payment copyWith({
    String? providerRef,
    PaymentStatus? status,
    DateTime? settledAt,
  }) => Payment(
    id: id,
    userId: userId,
    provider: provider,
    providerRef: providerRef ?? this.providerRef,
    amount: amount,
    msisdn: msisdn,
    status: status ?? this.status,
    createdAt: createdAt,
    settledAt: settledAt ?? this.settledAt,
  );

  @override
  String toString() => 'Payment($id, $provider, $amount, ${status.name})';
}

abstract interface class PaymentStore {
  Future<Payment> create(Payment payment);
  Future<Payment?> byId(String id);
  Future<Payment?> byProviderRef(String provider, String providerRef);

  /// StateError for an unknown id.
  Future<Payment> setProviderRef(String id, String providerRef);

  /// Moves pending to succeeded or failed. Returns null if the payment was not
  /// pending (compare and set), which is how a duplicate is detected.
  Future<Payment?> settle(String id, PaymentStatus status);
}

class InMemoryPaymentStore implements PaymentStore {
  final DateTime Function() _clock;
  final _payments = <String, Payment>{};

  InMemoryPaymentStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  @override
  Future<Payment> create(Payment payment) async {
    if (_payments.containsKey(payment.id)) {
      throw StateError('Payment ${payment.id} exists');
    }
    return _payments[payment.id] = payment;
  }

  @override
  Future<Payment?> byId(String id) async => _payments[id];

  @override
  Future<Payment?> byProviderRef(String provider, String providerRef) async {
    for (final p in _payments.values) {
      if (p.provider == provider && p.providerRef == providerRef) return p;
    }
    return null;
  }

  @override
  Future<Payment> setProviderRef(String id, String providerRef) async {
    final payment = _payments[id];
    if (payment == null) throw StateError('Unknown payment $id');
    return _payments[id] = payment.copyWith(providerRef: providerRef);
  }

  @override
  Future<Payment?> settle(String id, PaymentStatus status) async {
    if (status == PaymentStatus.pending) {
      throw ArgumentError.value(status, 'status', 'must be final');
    }
    final payment = _payments[id];
    if (payment == null || payment.status != PaymentStatus.pending) return null;
    return _payments[id] = payment.copyWith(
      status: status,
      settledAt: _clock().toUtc(),
    );
  }
}
