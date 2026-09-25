import 'dart:io';

import 'ids.dart';
import 'ledger.dart';
import 'payment.dart';

/// Deposits: starts them with a provider, and credits the wallet once the
/// provider confirms.
///
/// Crediting is safe to repeat. The wallet is credited by the ledger
/// transaction `deposit:<paymentId>`, posted before the payment is settled and
/// posted again whenever a succeeded payment is seen, so a crash between the
/// two writes is repaired by the next callback or refresh. The store's compare
/// and set settle and the ledger's idempotency key keep it to one credit.
class PaymentsService {
  static const minAmount = 500;
  static const maxAmount = 5000000;
  static final _msisdn = RegExp(r'^256\d{9}$');

  final Map<String, PaymentProvider> providers;
  final PaymentStore store;
  final Ledger ledger;
  final DateTime Function() _clock;
  final void Function(String message) _log;

  PaymentsService({
    required this.providers,
    required this.store,
    required this.ledger,
    DateTime Function()? clock,
    void Function(String message)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? ((m) => stderr.writeln('payments: $m'));

  /// Throws PaymentException(bad_request) for an unknown provider, an amount
  /// outside 500 to 5,000,000 UGX or an msisdn that is not 256 plus 9 digits.
  /// Returns the payment, pending unless the provider refused it outright.
  Future<Payment> startDeposit({
    required String userId,
    required String provider,
    required int amount,
    required String msisdn,
  }) async {
    final p = providers[provider];
    if (p == null) {
      throw PaymentException('bad_request', 'Unknown provider $provider');
    }
    if (amount < minAmount || amount > maxAmount) {
      throw const PaymentException(
        'bad_request',
        'Amount must be between 500 and 5,000,000 UGX',
      );
    }
    if (!_msisdn.hasMatch(msisdn)) {
      throw const PaymentException(
        'bad_request',
        'Phone number must be 256 followed by 9 digits',
      );
    }

    var payment = await store.create(
      Payment(
        id: newUuidV4(),
        userId: userId,
        provider: provider,
        amount: amount,
        msisdn: msisdn,
        status: PaymentStatus.pending,
        createdAt: _clock().toUtc(),
      ),
    );
    try {
      final ack = await p.requestDeposit(
        DepositRequest(paymentId: payment.id, amount: amount, msisdn: msisdn),
      );
      payment = await store.setProviderRef(payment.id, ack.providerRef);
    } on ProviderRejectedException catch (e) {
      _log('deposit ${payment.id} refused: ${e.message}');
      payment =
          await store.settle(payment.id, PaymentStatus.failed) ??
          (await store.byId(payment.id))!;
    } catch (e) {
      // Unknown outcome: leave it pending for refresh.
      _log('deposit ${payment.id} request failed, left pending: $e');
    }
    return payment;
  }

  /// Idempotent. A callback received twice credits once. The callback only
  /// names the payment; its status comes from the provider's checkStatus.
  /// Throws PaymentException(bad_request) for an unknown provider and
  /// PaymentException(bad_callback) for a body the provider cannot read.
  /// Returns null for an unknown payment.
  Future<Payment?> handleCallback(
    String provider,
    Map<String, String> headers,
    String body,
  ) async {
    final p = providers[provider];
    if (p == null) {
      throw PaymentException('bad_request', 'Unknown provider $provider');
    }
    final event = p.parseCallback(headers, body);
    if (event == null) {
      throw const PaymentException('bad_callback', 'Unreadable callback');
    }
    final payment =
        await store.byId(event.providerRef) ??
        await store.byProviderRef(provider, event.providerRef);
    if (payment == null || payment.provider != provider) {
      _log('callback for unknown payment $provider/${event.providerRef}');
      return null;
    }
    return _sync(payment, p);
  }

  /// Asks the provider about a pending payment and settles it the same way
  /// as a callback. Throws PaymentException(not_found) for an unknown id.
  Future<Payment> refresh(String paymentId) async {
    final payment = await store.byId(paymentId);
    if (payment == null) {
      throw PaymentException('not_found', 'Unknown payment $paymentId');
    }
    final p = providers[payment.provider];
    if (p == null) {
      _log('payment $paymentId has unknown provider ${payment.provider}');
      return payment;
    }
    return _sync(payment, p);
  }

  Future<Payment> _sync(Payment payment, PaymentProvider provider) async {
    if (payment.status == PaymentStatus.succeeded) {
      await _credit(payment);
      return payment;
    }
    if (payment.status == PaymentStatus.failed) return payment;

    final ProviderStatus status;
    try {
      status = await provider.checkStatus(payment.providerRef ?? payment.id);
    } catch (e) {
      _log('status check for ${payment.id} failed: $e');
      return payment;
    }

    switch (status.status) {
      case PaymentStatus.pending:
        return payment;
      case PaymentStatus.failed:
        return await store.settle(payment.id, PaymentStatus.failed) ??
            (await store.byId(payment.id))!;
      case PaymentStatus.succeeded:
        if (status.amount != null && status.amount != payment.amount) {
          _log(
            'REVIEW: payment ${payment.id} confirmed for ${status.amount}, '
            'expected ${payment.amount}. Not credited.',
          );
          return payment;
        }
        await _credit(payment);
        final settled =
            await store.settle(payment.id, PaymentStatus.succeeded) ??
            (await store.byId(payment.id))!;
        if (settled.status != PaymentStatus.succeeded) {
          _log(
            'REVIEW: payment ${payment.id} credited but stored as '
            '${settled.status.name}',
          );
        }
        return settled;
    }
  }

  Future<void> _credit(Payment payment) => ledger.post(
    LedgerTransaction(
      idempotencyKey: 'deposit:${payment.id}',
      kind: 'deposit',
      transfers: [
        Transfer(
          from: AccountId.providerClearing(payment.provider),
          to: AccountId.wallet(payment.userId),
          amount: payment.amount,
        ),
      ],
      metadata: {
        'paymentId': payment.id,
        'provider': payment.provider,
        'providerRef': payment.providerRef,
      },
    ),
  );
}
