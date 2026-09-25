import 'dart:convert';

import 'payment.dart';
import 'provider_http.dart';

/// Records requests and confirms them when told to. Used for tests and when
/// PAYMENTS_PROVIDER=fake.
class FakePaymentProvider implements PaymentProvider {
  @override
  final String name;

  /// Every deposit request received, in order.
  final requests = <DepositRequest>[];

  /// When set, the next requestDeposit throws this and clears it.
  Exception? failNextRequest;

  /// When set, checkStatus throws this until it is cleared.
  Exception? failStatusChecks;

  final _statuses = <String, ProviderStatus>{};

  FakePaymentProvider({this.name = 'fake'});

  @override
  Future<ProviderAck> requestDeposit(DepositRequest request) async {
    final failure = failNextRequest;
    if (failure != null) {
      failNextRequest = null;
      throw failure;
    }
    requests.add(request);
    _statuses[request.paymentId] = ProviderStatus(
      providerRef: request.paymentId,
      status: PaymentStatus.pending,
      amount: request.amount,
    );
    return ProviderAck(request.paymentId);
  }

  @override
  Future<ProviderStatus> checkStatus(String providerRef) async {
    final failure = failStatusChecks;
    if (failure != null) throw failure;
    final status = _statuses[providerRef];
    if (status == null) {
      throw ProviderUnavailableException('fake: unknown ref $providerRef');
    }
    return status;
  }

  /// Sets what checkStatus returns. [amount] defaults to the requested amount.
  void complete(
    String providerRef, {
    PaymentStatus status = PaymentStatus.succeeded,
    int? amount,
  }) {
    final current = _statuses[providerRef];
    if (current == null) throw StateError('fake: unknown ref $providerRef');
    _statuses[providerRef] = ProviderStatus(
      providerRef: providerRef,
      status: status,
      amount: amount ?? current.amount,
      reason: status == PaymentStatus.failed ? 'declined' : null,
    );
  }

  /// A callback body matching the current status of [providerRef].
  String callbackBody(String providerRef) {
    final status = _statuses[providerRef];
    if (status == null) throw StateError('fake: unknown ref $providerRef');
    return jsonEncode({
      'ref': providerRef,
      'status': status.status.name,
      'amount': status.amount,
    });
  }

  @override
  CallbackEvent? parseCallback(Map<String, String> headers, String body) {
    final json = jsonObject(body);
    final ref = json?['ref'];
    final status = json?['status'];
    if (ref is! String || ref.isEmpty || status is! String) return null;
    final parsed = PaymentStatus.values.asNameMap()[status];
    if (parsed == null) return null;
    return CallbackEvent(
      providerRef: ref,
      status: parsed,
      amount: parseAmount(json!['amount']),
    );
  }
}
