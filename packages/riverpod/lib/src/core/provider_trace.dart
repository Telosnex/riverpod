part of '../framework.dart';

/// Debug-only, opt-in, per-provider trace hook.
///
/// Both [hook] and [filter] must be set for anything to be emitted; [filter]
/// scopes emission to the specific providers under investigation so this can
/// be enabled in a large app without tracing every provider. Events that are
/// not tied to a single provider (vsync scheduling, task execution) are only
/// emitted when at least one *matching* provider is pending in the scheduler.
///
/// Null by default. No cost beyond a null check when disabled.
@internal
final class ProviderTrace {
  ProviderTrace._();

  /// Receives `(event, fields)`. Field values are primitives/strings only.
  static void Function(String event, Map<String, Object?> fields)? hook;

  /// Returns true for providers that should be traced. Receives the
  /// provider's `origin` (the thing the user declared, so `name`/`toString`
  /// are meaningful).
  static bool Function(ProviderOrFamily origin)? filter;

  static bool get enabled => hook != null && filter != null;

  static bool matches(ProviderElement<Object?, Object?> element) {
    final f = filter;
    return hook != null && f != null && f(element.origin);
  }

  /// True if any provider currently awaiting refresh matches [filter].
  static bool anyPendingMatches(ProviderScheduler scheduler) {
    if (!enabled) return false;
    for (final element in scheduler.stateToRefresh) {
      if (matches(element)) return true;
    }
    return false;
  }

  static void emit(
    String event,
    ProviderElement<Object?, Object?>? element,
    Map<String, Object?> fields,
  ) {
    final h = hook;
    if (h == null) return;
    h(event, {
      if (element != null) 'provider': element.origin.toString(),
      ...fields,
    });
  }
}
