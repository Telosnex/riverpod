import 'dart:async';

import 'package:meta/meta.dart';

import '../internals.dart';

/// Rethrows as a [ProviderException] with the given stack trace.
@internal
Never throwProviderException(Object error, StackTrace stackTrace) {
  throw ProviderException(error, stackTrace);
}

@internal
extension ProviderExceptionX on ProviderException {
  Never unwrap(StackTrace stackTrace) =>
      rethrowWithStackTrace(exception, stackTrace);
}

/// The error and stack trace that [rethrowWithStackTrace] threw last.
Object? _rethrownError;
StackTrace? _rethrownStackTrace;

/// Rethrows [error] with [stackTrace], like [Error.throwWithStackTrace].
///
/// The pair is remembered so that [caughtStackTrace] can restore it.
@internal
Never rethrowWithStackTrace(Object error, StackTrace stackTrace) {
  _rethrownError = error;
  _rethrownStackTrace = stackTrace;
  Error.throwWithStackTrace(error, stackTrace);
}

/// The stack trace to store for [error], given the [caught] stack trace from
/// its catch clause.
///
/// dart2js gives a new [StackTrace] object each time a trace is caught after
/// [Error.throwWithStackTrace], even when it is the same trace. That breaks
/// the identity of stack traces compared by [AsyncValue] and [MutationError].
/// When [error] is the one that [rethrowWithStackTrace] threw last and [caught]
/// has the same contents, this returns the trace that was thrown. Otherwise it
/// returns [caught].
@internal
StackTrace caughtStackTrace(Object error, StackTrace caught) {
  final thrown = _rethrownStackTrace;
  if (thrown == null || !identical(error, _rethrownError)) return caught;
  if (!identical(caught, thrown) && caught.toString() != thrown.toString()) {
    return caught;
  }

  _rethrownError = null;
  _rethrownStackTrace = null;
  return thrown;
}

/// An exception thrown when trying to read a provider that is in error state.
///
/// This exception can be thrown when either:
/// - You're using a synchronous provider ([Notifier]/[Provider]) and
///   the provider threw an exception during its initialization.
/// - You're using an asynchronous provider ([FutureProvider]/[StreamProvider]),
///   the state is an [AsyncError], and you called [AsyncValue.requireValue].
/// - Using an asynchronous provider, you awaited [FutureProvider.future],
///   and the provider was in error state.
///
///
/// Catching this exception can be useful to differentiate between
/// a provider in error state from a provider that depends on another provider
/// in error state.
///
/// In particular, Riverpod will:
/// - Disable automatic retry if a [ProviderException] is thrown by a provider.
///   This avoids retrying a provider that isn't the source of the problem.
/// - Not report the error to [Zone] if it is a [ProviderException].
///   This avoids reporting the same error twice.
@publicInMisc
final class ProviderException implements Exception {
  /// Creates a [ProviderException].
  @internal
  ProviderException(this.exception, this.stackTrace);

  /// The exception that was thrown by the provider.
  final Object exception;

  /// The stack trace of the exception.
  final StackTrace stackTrace;

  @override
  String toString() {
    if (exception case final ProviderException exception) {
      return '''
$exception

And rethrown at:
$stackTrace''';
    }

    return '''
ProviderException: Tried to use a provider that is in error state.

A provider threw the following exception:
$exception

The stack trace of the exception:
$stackTrace''';
  }
}
