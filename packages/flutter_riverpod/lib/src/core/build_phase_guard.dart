part of '../core.dart';

/// Tracks which riverpod-owned element's `build` is currently executing.
///
/// Flutter builds dirty elements in depth order and only allows an element to
/// be marked dirty during the build phase if it is a descendant of the
/// element currently building (a dirty descendant is guaranteed to be reached
/// later in the same pass). Anything else is rejected in debug and, in
/// release, silently dropped by `BuildScope._flushDirtyElements` with its
/// `dirty` flag left set, after which [Element.markNeedsBuild] early-returns
/// forever: the element is wedged for the life of the app.
///
/// Riverpod fires notifications from inside builds in two places, the
/// scope's build (running the scheduler task) and a consumer's `ref.watch`
/// (flushing a dirty provider). Both record themselves here so
/// [canMarkNeedsBuildNow] can tell safe targets from wedge candidates.
@internal
abstract final class RiverpodBuildTarget {
  static Element? current;

  static T run<T>(Element target, T Function() body) {
    final previous = current;
    current = target;
    try {
      return body();
    } finally {
      current = previous;
    }
  }
}

/// Whether marking [element] dirty right now will actually result in a
/// rebuild, per the rules described on [RiverpodBuildTarget].
///
/// Outside the build/layout/paint phase this is always true. Inside it, only
/// descendants of the currently building riverpod element are known-safe.
/// When no riverpod element is building (the notification came from somewhere
/// else in the widget lifecycle, e.g. `ProviderScope.didUpdateWidget` or a
/// TickerMode resume), the answer is [whenUnknown]: consumers keep upstream's
/// mark-now behaviour there, the scope (an ancestor of everything) defers.
/// Callers getting `false` must defer with [deferMarkNeedsBuild].
@internal
bool canMarkNeedsBuildNow(Element element, {required bool whenUnknown}) {
  if (SchedulerBinding.instance.schedulerPhase !=
      SchedulerPhase.persistentCallbacks) {
    return true;
  }
  // Already dirty: markNeedsBuild is a no-op either way.
  if (element.dirty) return true;

  final target = RiverpodBuildTarget.current;
  if (target == null) return whenUnknown;
  if (identical(target, element)) return true;
  if (element.depth <= target.depth) return false;

  var isDescendant = false;
  element.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      isDescendant = true;
      return false;
    }
    // Walked above the target's depth without meeting it.
    return ancestor.depth > target.depth;
  });
  return isDescendant;
}

/// Runs [mark] once the current frame is done, when marking dirty is legal
/// again and schedules a new frame.
@internal
void deferMarkNeedsBuild(VoidCallback mark) {
  SchedulerBinding.instance.addPostFrameCallback((_) => mark());
}
