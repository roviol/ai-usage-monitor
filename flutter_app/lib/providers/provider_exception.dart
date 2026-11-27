/// Exceptions carrying structured provider errors, mirroring the C++
/// `ProviderException`.
library;

import '../domain/model.dart';

/// Thrown by provider adapters with a structured error for the scheduler.
class ProviderException implements Exception {
  ProviderException(this.error);

  final ProviderError error;

  @override
  String toString() => error.message;
}