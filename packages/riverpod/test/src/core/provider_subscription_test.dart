import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/src/internals.dart' show NodeInternal;
import 'package:test/test.dart';

import '../matrix.dart';
import '../utils.dart';

void main() {
  group('_ProxySubscription', () {
    test('handles pause/resume', () {
      final container = ProviderContainer.test();
      final provider = FutureProvider((ref) => 0);

      final element = container.readProviderElement(provider);

      final sub = container.listen(provider.future, (previous, next) {});

      expect(element.isActive, true);

      sub.pause();

      expect(element.isActive, false);

      sub.resume();

      expect(element.isActive, true);
    });

    test('closing a paused subscription unpauses the element', () {
      final container = ProviderContainer.test();
      final provider = FutureProvider((ref) => 0);

      final element = container.readProviderElement(provider);

      final sub = container.listen(provider.future, (previous, next) {});

      expect(element.isActive, true);

      sub.pause();

      expect(element.isActive, false);

      sub.close();
      container.listen(provider.future, (previous, next) {});

      expect(element.isActive, true);
    });
  });

  group('ProviderSubscription.resume', () {
    test(
      'Resuming a paused subscription with no missed data event does not call listeners',
      () {
        final container = ProviderContainer.test();
        final provider = Provider((ref) => 0);
        final listener = Listener<int>();

        final sub = container.listen(provider, listener.call);

        sub.pause();

        sub.resume();

        verifyZeroInteractions(listener);
      },
    );

    test(
      'Resuming a paused subscription with missed data emits the last event',
      () async {
        final container = ProviderContainer.test();
        final provider = NotifierProvider<DeferredNotifier<int>, int>(
          () => DeferredNotifier((ref, _) => 0),
        );
        final listener = Listener<int>();

        final notifier = container.read(provider.notifier);

        final sub = container.listen(provider, listener.call);

        sub.pause();

        notifier.state = 1;
        notifier.state = 2;

        sub.resume();

        verifyOnly(listener, listener(1, 2));

        sub.resume();

        verifyNoMoreInteractions(listener);
      },
    );

    test(
      'Resuming a paused subscription with missed error emits the last error',
      () async {
        final container = ProviderContainer.test();
        late Error toThrow;
        final stack = StackTrace.current;
        final provider = Provider<int>((ref) {
          Error.throwWithStackTrace(toThrow, stack);
        });
        final listener = Listener<int>();
        final onError = ErrorListener();
        final err = Error();
        final err2 = Error();

        toThrow = err;

        final sub = container.listen(
          provider,
          listener.call,
          onError: onError.call,
        );

        sub.pause();

        toThrow = err2;
        try {
          container.refresh(provider);
        } catch (e) {
          // Will rethrow the error, but we don't care about it here
        }

        sub.resume();

        verifyOnly(onError, onError(err2, stack));

        sub.resume();

        verifyNoMoreInteractions(onError);
        verifyZeroInteractions(listener);
      },
    );

    test('needs to be called as many times as pause() was called', () {
      final container = ProviderContainer.test();
      final provider = Provider((ref) => 0);

      final sub = container.listen(provider, (p, b) {});

      sub.pause();
      sub.pause();
      sub.pause();

      sub.resume();
      expect(sub.isPaused, true);
      sub.resume();
      expect(sub.isPaused, true);
      sub.resume();
      expect(sub.isPaused, false);
    });

    // Regression test for the "stuck HomeDateTime" bug.
    //
    // Symptom in Telosnex: after navigating away from Home (which paused
    // every subscription via TickerMode=false) the home-screen clock froze
    // on its last-seen value forever, even after navigating back.
    //
    // Root cause lives in `ProviderScheduler._performRefresh`:
    //
    //   while (stateToRefresh.isNotEmpty) {
    //     final element = stateToRefresh.first;
    //     stateToRefresh.remove(element);
    //     if (element.isActive) element.flush(); // ← bug
    //   }
    //
    // `element.isActive` is defined as
    //   `(listenerCount - pausedActiveSubscriptionCount) > 0`
    // so a provider whose sole listener is *paused* is considered inactive.
    // Meanwhile `invalidateSelf()` has already eagerly fired `runOnDispose()`
    // (cancelling any internal timers / lifecycle listeners the provider
    // installed during its last build). The matching rebuild is then
    // silently skipped, leaving the provider in a zombie state
    // (`_mustRecomputeState=true`, all disposables torn down, nothing left
    // to reschedule the refresh). On resume the subscription has no missed
    // event to deliver, so the widget never rebuilds and stays stuck.
    //
    // `_performDispose` meanwhile gates on `hasNonWeakListeners` (which
    // *does* count paused subs) so dispose is also skipped — the element
    // is neither refreshed nor disposed. That asymmetry is the real flaw.
    //
    // The fix: gate `_performRefresh` on `hasNonWeakListeners` as well.
    // A paused subscription is still a subscription; it wants the provider
    // to rebuild so the new value can be stashed in `_missedCalled` and
    // delivered on resume.
    test(
      'invalidate() while only listener is paused still rebuilds the '
      'provider, and the new value is delivered on resume',
      () async {
        final container = ProviderContainer.test();
        var buildCount = 0;
        final provider = Provider<int>((ref) {
          // ignore: join_return_with_assignment
          buildCount++;
          return buildCount;
        });
        final listener = Listener<int>();

        final sub = container.listen(provider, listener.call);
        expect(buildCount, 1);
        verifyZeroInteractions(listener);

        sub.pause();

        // Exact same code path as an autoDispose provider's internal timer
        // calling `ref.invalidateSelf()` from inside itself.
        container.invalidate(provider);

        // Let the scheduler run its end-of-frame refresh pass.
        await container.pump();

        // With the bug, `_performRefresh` skips this element because
        // `isActive` is false (the sole listener is paused), so buildCount
        // stays at 1.
        expect(
          buildCount,
          2,
          reason: 'provider must rebuild even when every listener is paused, '
              'otherwise `invalidateSelf()` leaves it permanently dirty',
        );

        sub.resume();

        // The rebuild that happened during the pause should have been
        // recorded in `_missedCalled` and delivered here.
        verifyOnly(listener, listener(1, 2));
      },
    );

    // Companion test: same scenario but with an autoDispose provider that
    // models `currentDateTimeProvider` — it registers an `onDispose`
    // callback and invalidates itself. We assert that the onDispose fires
    // exactly once per build cycle, matching the non-paused behaviour.
    test(
      'autoDispose provider with paused listener: invalidate() still runs '
      'onDispose + rebuild exactly once',
      () async {
        final container = ProviderContainer.test();
        var buildCount = 0;
        var disposeCount = 0;
        final provider = Provider.autoDispose<int>((ref) {
          buildCount++;
          ref.onDispose(() => disposeCount++);
          return buildCount;
        });
        final listener = Listener<int>();

        final sub = container.listen(provider, listener.call);
        expect(buildCount, 1);
        expect(disposeCount, 0);

        sub.pause();

        container.invalidate(provider);
        await container.pump();

        // Before the fix: buildCount=1, disposeCount=1 — runOnDispose fired
        // but no rebuild followed, leaving the provider dirty forever.
        // After the fix: rebuild proceeds, so buildCount goes to 2 and a
        // fresh onDispose is registered against the new build.
        expect(buildCount, 2, reason: 'paused-but-listened provider must rebuild');
        expect(disposeCount, 1, reason: 'only the pre-rebuild dispose should fire');

        sub.resume();

        verifyOnly(listener, listener(1, 2));
      },
    );
  });
}
