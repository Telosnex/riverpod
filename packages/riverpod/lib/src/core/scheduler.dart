part of '../framework.dart';

@internal
class Task {
  Task(this._task);

  final void Function() _task;
  var _completed = false;

  bool get completed => _completed;

  void call() {
    if (_completed) return;
    _completed = true;
    _task();
  }
}

/// A listener used to determine when providers should rebuild.
/// This is used to synchronize provider rebuilds when widget rebuilds.
@internal
abstract interface class Vsync {
  void Function()? scheduleRefresh(Task task);

  void Function()? scheduleDispose(Task task);
}

@internal
typedef VsyncScheduler = void Function()? Function(Vsync vsync, Task task);

final class _DefaultVsync implements Vsync {
  const _DefaultVsync();

  @override
  void Function()? scheduleRefresh(Task task) {
    final timer = Timer(Duration.zero, task.call);

    return timer.cancel;
  }

  @override
  void Function()? scheduleDispose(Task task) {
    final timer = Timer(Duration.zero, task.call);

    return timer.cancel;
  }
}

const _defaultVsync = _DefaultVsync();

/// The object that handles when providers are refreshed and disposed.
///
/// Providers are typically refreshed at the end of the frame where they
/// notified that they wanted to rebuild.
///
/// Providers are disposed if they spent at least one full frame without any listener.
@internal
class ProviderScheduler {
  var _disposed = false;

  final flutterVsyncs = <Vsync>{};

  final _stateToDispose = <ProviderElement>[];
  final stateToRefresh = <ProviderElement>[];

  Completer<void>? _pendingTaskCompleter;
  Task? _pendingTask;

  /// A future that completes when the next task is done.
  Future<void>? get pendingFuture => _pendingTaskCompleter?.future;

  void Function()? _cancelTask;
  var _taskUsesVsync = false;
  var _pendingTaskNeedsRefresh = false;

  /// Whether [_task] is currently executing synchronously.
  ///
  /// While true, [_pendingTask] may legitimately be non-null and completed
  /// (work scheduled by an ongoing flush/dispose is drained by [_task]'s own
  /// loops). Observed from anywhere else, a completed pending task means a
  /// previous [_task] aborted mid-flight; [_scheduleTask] recovers from that
  /// instead of silently dropping all future work.
  var _executingTask = false;

  /// Schedules a provider to be refreshed.
  ///
  /// The refresh will happen at the end of the next event-loop,
  /// and only if the provider is active.
  void scheduleProviderRefresh(ProviderElement element) {
    assert(
      element.container.scheduler == this,
      'Tried to refresh ${element.origin}, but it does not belong to this scheduler',
    );
    stateToRefresh.add(element);

    _scheduleTask(taskNeedsRefresh: true);
  }

  void _scheduleTask({required bool taskNeedsRefresh}) {
    // Don't schedule a task if there is already one pending or if the scheduler
    // is disposed.
    // It is possible that during disposal of a ProviderContainer, if a provider
    // uses ref.keepAlive(), the keepAlive closure will try to schedule a task.
    // In this case, we don't want to schedule a task as the container is already
    // disposed.
    if (_disposed) return;

    final pendingTask = _pendingTask;
    if (pendingTask != null) {
      if (pendingTask.completed) {
        // A completed task still registered as pending is normal while
        // _task() is running (its index-based loops pick up entries added
        // during the flush/dispose passes). Outside of that, it means a
        // previous _task() aborted mid-flight (it should no longer be
        // possible now that _task() is exception-safe, but the failure mode
        // is catastrophic: every subsequent refresh/dispose would be
        // silently dropped, freezing all provider updates until process
        // restart). Recover by discarding the stale task and scheduling a
        // fresh one.
        if (_executingTask) return;

        if (!(_pendingTaskCompleter?.isCompleted ?? true)) {
          _pendingTaskCompleter!.complete();
        }
        _pendingTask = null;
        _pendingTaskCompleter = null;
        _cancelTask?.call();
        _cancelTask = null;
        _taskUsesVsync = false;
        _pendingTaskNeedsRefresh = false;
        // Fall through to schedule a new task.
      } else if (taskNeedsRefresh && !_pendingTaskNeedsRefresh) {
        _pendingTaskNeedsRefresh = true;
        if (!_taskUsesVsync) {
          _cancelTask?.call();
          _cancelTask = _scheduleTaskWithVsyncs(
            pendingTask,
            _scheduleRefreshTask,
          );
          _taskUsesVsync = true;
        }

        return;
      } else {
        return;
      }
    }

    _pendingTaskCompleter = Completer<void>();
    final task = Task(_task);
    _pendingTask = task;
    _pendingTaskNeedsRefresh = taskNeedsRefresh;
    _taskUsesVsync = taskNeedsRefresh;
    _cancelTask = _scheduleTaskWithVsyncs(
      task,
      taskNeedsRefresh ? _scheduleRefreshTask : _scheduleDisposeTask,
    );
  }

  void Function()? _scheduleTaskWithVsyncs(
    Task task,
    VsyncScheduler scheduleTask,
  ) {
    if (flutterVsyncs.isEmpty) {
      return scheduleTask(_defaultVsync, task);
    }

    final cancels = <void Function()?>[];
    for (final flutterVsync in flutterVsyncs) {
      cancels.add(scheduleTask(flutterVsync, task));
    }

    return () {
      for (final cancel in cancels) {
        cancel?.call();
      }
    };
  }

  static void Function()? _scheduleRefreshTask(Vsync vsync, Task task) {
    return vsync.scheduleRefresh(task);
  }

  static void Function()? _scheduleDisposeTask(Vsync vsync, Task task) {
    return vsync.scheduleDispose(task);
  }

  void _task() {
    final cancelTask = _cancelTask;
    _cancelTask = null;
    _taskUsesVsync = false;
    _pendingTaskNeedsRefresh = false;
    cancelTask?.call();
    final pendingTask = _pendingTask;
    final pendingTaskCompleter = _pendingTaskCompleter;
    if (pendingTask == null || pendingTaskCompleter == null) return;
    pendingTaskCompleter.complete();

    _executingTask = true;
    try {
      final refreshedCount = _performRefresh(0);
      _performDispose();
      // `ref.onDispose` callbacks may invalidate other providers, appending
      // to [stateToRefresh] *after* the refresh pass above. Flush those too:
      // the clear() below would otherwise silently drop them, leaving those
      // providers dirty-but-unflushed until something happens to read them.
      if (stateToRefresh.length > refreshedCount) {
        _performRefresh(refreshedCount);
      }
    } finally {
      // Reset the scheduler state unconditionally.
      //
      // Before this was exception-safe, a single error escaping a provider
      // rebuild (e.g. a throwing `updateShouldNotify`/`==` during
      // _performRebuild, or an internal bookkeeping error) left the completed
      // task registered in [_pendingTask] forever. [_scheduleTask] then
      // early-returned on every subsequent call, permanently wedging *all*
      // scheduled refreshes and disposals for this container: derived
      // providers stopped rebuilding and autoDispose providers stopped being
      // disposed (a leak), app-wide, until process restart.
      stateToRefresh.clear();
      _stateToDispose.clear();
      _pendingTask = null;
      _pendingTaskCompleter = null;
      _executingTask = false;
    }
  }

  void debugNotifyDidBuild(ProviderElement element) {
    if (kDebugMode) {
      final set = _builtWithinFrame;
      if (set != null && !set.add(element)) {
        throw StateError(
          'Tried to rebuild ${element.origin} multiple times in the same frame',
        );
      }
    }
  }

  Set<ProviderElement>? _builtWithinFrame;

  /// Flushes entries of [stateToRefresh], starting at index [from].
  ///
  /// Returns the number of entries processed, so that callers can resume
  /// from that index if new entries were appended in the meantime.
  int _performRefresh(int from) {
    if (kDebugMode) _builtWithinFrame = {};

    /// No need to traverse entries from top to bottom, because refreshing a
    /// child will automatically refresh its parent when it will try to read it
    for (var i = from; i < stateToRefresh.length; i++) {
      final element = stateToRefresh[i];
      if (!element.isActive) continue;
      try {
        element.flush();
      } catch (err, stack) {
        // Guarded so that one provider failing to rebuild cannot prevent
        // the other scheduled providers from rebuilding, nor wedge the
        // scheduler itself (see _task).
        element.container.defaultOnError(err, stack);
      }
    }

    if (kDebugMode) _builtWithinFrame = null;
    return stateToRefresh.length;
  }

  void debugScheduleFrame(void Function() onEvent) {
    if (!kDebugMode || _disposed) return;

    Future.microtask(() {
      if (_disposed) return;
      onEvent();
    });
  }

  /// Schedules a provider to be disposed.
  ///
  /// The provider will be disposed at the end of the next event-loop,
  void scheduleProviderDispose(ProviderElement element) {
    assert(
      element.container.scheduler == this,
      'Tried to dispose ${element.origin}, but it does not belong to this scheduler',
    );
    assert(
      !element.isActive,
      'Tried to dispose ${element.origin} , but still has listeners',
    );

    _stateToDispose.add(element);
    _scheduleTask(taskNeedsRefresh: false);
  }

  void _performDispose() {
    /// No need to traverse entries from children to parents as a parent cannot
    /// have no listener until its children are disposed first.
    /// Worse case scenario, a parent will be added twice to the list (parent child parent)
    /// but when the parent is traversed first, it will still have listeners,
    /// and the second time it is traversed, it won't anymore.
    for (var i = 0; i < _stateToDispose.length; i++) {
      final element = _stateToDispose[i];
      final links = element.ref?._keepAliveLinks;

      if ((links != null && links.isNotEmpty) ||
          element.container._disposed ||
          element.hasNonWeakListeners) {
        continue;
      }

      try {
        if (element.weakDependents.isEmpty) {
          element.container._disposeProvider(element.origin);
        } else {
          // Don't delete the pointer if there are some "weak" listeners active.
          element.clearState();
        }
      } catch (err, stack) {
        // Guarded so that one provider failing to dispose cannot prevent
        // the other scheduled providers from being disposed, nor wedge the
        // scheduler itself (see _task).
        element.container.defaultOnError(err, stack);
      }
    }
  }

  /// Diagnostic snapshot of the scheduler's internal state.
  ///
  /// Intended for app-level watchdogs that want to detect a wedged
  /// scheduler in release builds: because [_task] runs synchronously,
  /// observing `hasPendingTask && pendingTaskCompleted && !executingTask`
  /// from the event loop means scheduled work is no longer being processed.
  ({
    bool hasPendingTask,
    bool pendingTaskCompleted,
    bool executingTask,
    int pendingRefreshCount,
    int pendingDisposeCount,
    int vsyncCount,
    bool disposed,
  })
  get health => (
    hasPendingTask: _pendingTask != null,
    pendingTaskCompleted: _pendingTask?.completed ?? false,
    executingTask: _executingTask,
    pendingRefreshCount: stateToRefresh.length,
    pendingDisposeCount: _stateToDispose.length,
    vsyncCount: flutterVsyncs.length,
    disposed: _disposed,
  );

  /// Disposes the scheduler.
  void dispose() {
    _disposed = true;
    _pendingTaskCompleter?.complete();
    _pendingTaskCompleter = null;
    _pendingTask = null;
    _cancelTask?.call();
    _cancelTask = null;
    _taskUsesVsync = false;
    _pendingTaskNeedsRefresh = false;
  }
}
