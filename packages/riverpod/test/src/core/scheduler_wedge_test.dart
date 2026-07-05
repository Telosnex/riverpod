// Regression tests for the scheduler permanently wedging when an exception
// escapes a scheduled provider refresh.
//
// Before the fix, `ProviderScheduler._task()` was not exception-safe: if
// `element.flush()` threw (e.g. a user type whose `==` throws, invoked by the
// default `updateShouldNotify` during `_performRebuild`), the completed task
// stayed registered in `_pendingTask` forever. Every subsequent
// `_scheduleTask` call then early-returned on `pendingTask.completed`,
// silently dropping ALL future refreshes and disposals for the container:
// derived providers stopped rebuilding app-wide until process restart.
//
// This matches a production failure mode: an app that stays alive for a long
// time (e.g. iOS overnight in background) hits one internal/user error during
// a scheduled refresh, and from then on every provider that updates through
// the scheduler (ref.watch chains, invalidate, autoDispose) is frozen, while
// directly-listened state still moves. In release mode there is no red
// screen, so the wedge is invisible except as "stuck UI".

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/src/internals.dart' show InternalProviderContainer;
import 'package:test/test.dart';

/// A value whose `==` throws, making the default `updateShouldNotify` throw
/// during a scheduled rebuild (`_performRebuild` calls it outside of
/// `buildState`'s try/catch, so the exception escapes `flush()`).
@immutable
class ThrowingEquality {
  const ThrowingEquality();

  @override
  bool operator ==(Object other) =>
      throw StateError('ThrowingEquality.== boom');

  @override
  int get hashCode => 0;
}

class Counter extends Notifier<int> {
  @override
  int build() => 0;
}

void main() {
  group('scheduler wedge', () {
    test(
      'an exception escaping flush() during a scheduled refresh does not '
      'prevent other scheduled providers from refreshing (same task)',
      () async {
        final onErrorReports = <Object>[];
        final zoneErrors = <Object>[];

        await runZonedGuarded(() async {
          final container = ProviderContainer(
            onError: (err, stack) => onErrorReports.add(err),
          );
          addTearDown(container.dispose);

          final bad = Provider((ref) => const ThrowingEquality());

          var goodBuildCount = 0;
          final good = Provider((ref) => ++goodBuildCount);

          final goodValues = <int>[];
          container.listen(bad, (_, _) {});
          container.listen(good, (_, next) => goodValues.add(next));
          expect(goodBuildCount, 1);

          // Schedule both in the same task. `bad` rebuilds first and throws
          // from updateShouldNotify; `good` must still be flushed.
          container.invalidate(bad);
          container.invalidate(good);
          await container.pump();
          await Future<void>.delayed(Duration.zero);

          expect(goodBuildCount, 2);
          expect(goodValues, [2]);
        }, (error, stack) => zoneErrors.add(error))!;

        // Wait for the zone's async work (scheduler timers) to settle.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          onErrorReports.map((e) => e.toString()),
          contains(contains('ThrowingEquality')),
          reason: 'the escaping exception must be reported, not swallowed',
        );
        expect(zoneErrors, isEmpty);
      },
    );

    test(
      'an exception escaping flush() during a scheduled refresh does not '
      'wedge subsequent tasks',
      () async {
        final onErrorReports = <Object>[];
        final zoneErrors = <Object>[];

        await runZonedGuarded(() async {
          final container = ProviderContainer(
            onError: (err, stack) => onErrorReports.add(err),
          );
          addTearDown(container.dispose);

          final bad = Provider((ref) => const ThrowingEquality());

          var goodBuildCount = 0;
          final good = Provider((ref) => ++goodBuildCount);

          container.listen(bad, (_, _) {});
          final goodValues = <int>[];
          container.listen(good, (_, next) => goodValues.add(next));

          // Round 1: only `bad` refreshes, and throws.
          container.invalidate(bad);
          await container.pump();
          await Future<void>.delayed(Duration.zero);

          // Round 2: a completely healthy provider must still refresh.
          // Pre-fix, the stale completed task caused _scheduleTask to
          // early-return forever, so `good` would never rebuild again.
          container.invalidate(good);
          await container.pump();
          await Future<void>.delayed(Duration.zero);

          expect(goodBuildCount, 2, reason: 'scheduler must not wedge');
          expect(goodValues, [2]);

          // And the scheduler's own bookkeeping is clean again.
          final health = container.scheduler.health;
          expect(health.hasPendingTask, false);
          expect(health.pendingRefreshCount, 0);
          expect(health.pendingDisposeCount, 0);
        }, (error, stack) => zoneErrors.add(error))!;

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(onErrorReports, isNotEmpty);
        expect(zoneErrors, isEmpty);
      },
    );

    test(
      'refreshes appended to stateToRefresh during the dispose pass are not '
      'silently dropped',
      () async {
        final container = ProviderContainer.test();

        var dependentBuildCount = 0;

        final trigger = NotifierProvider<Counter, int>(Counter.new);
        final dependent = Provider((ref) {
          ref.watch(trigger);

          return ++dependentBuildCount;
        });

        final disposable = Provider.autoDispose((ref) {
          ref.onDispose(() {
            // A refresh scheduled during _performDispose used to be appended
            // to stateToRefresh *after* _performRefresh had already run, then
            // dropped by the trailing clear() -- leaving `dependent` dirty
            // but never flushed.
            container.invalidate(dependent);
          });

          return 0;
        });

        container.listen(dependent, (_, _) {});
        expect(dependentBuildCount, 1);

        // Create then release the autoDispose provider, scheduling a dispose.
        final sub = container.listen(disposable, (_, _) {});
        sub.close();

        await container.pump();
        await Future<void>.delayed(Duration.zero);
        await container.pump();
        await Future<void>.delayed(Duration.zero);

        expect(
          dependentBuildCount,
          2,
          reason: 'refresh scheduled during the dispose pass must flush',
        );
      },
    );
  });
}
