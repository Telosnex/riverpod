// Regression test for the _TickerModeHub multiplexer.
//
// The hub registers ONE listener on the shared TickerMode notifier and
// dispatches to all consumer elements itself. Upstream riverpod registers one
// listener per element, and ChangeNotifier.notifyListeners isolates each
// listener's exceptions. Pre-fix, the hub's dispatch loop had no such
// isolation: if resuming one element's subscriptions threw (a synchronous
// provider flush during resume can throw, e.g. via a user `==` in
// updateShouldNotify), every element after it in the loop was skipped --
// leaving those consumers' subscriptions permanently paused while fully
// visible. Their widgets then showed stale provider values indefinitely.
//
// Note: pre-fix failure was probabilistic (identity-HashSet iteration order
// decides whether the throwing element precedes the healthy ones), which is
// why this test uses many healthy consumers around a single bad one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A value whose `==` throws, so the default `updateShouldNotify` throws
/// when the provider rebuilds during a subscription resume.
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

  void increment() => state++;
}

void main() {
  testWidgets(
    'a consumer whose resume throws does not leave sibling consumers paused',
    (tester) async {
      const goodConsumerCount = 8;

      final good = NotifierProvider<Counter, int>(Counter.new);
      final bad = Provider((ref) => const ThrowingEquality());

      final tickerEnabled = ValueNotifier(true);
      addTearDown(tickerEnabled.dispose);

      // Built ONCE and reused as an identical widget instance, so that
      // flipping TickerMode does not rebuild the consumers. Their state can
      // then only change through the pause/resume + missed-event machinery,
      // which is what this test exercises.
      final consumers = Column(
        children: [
          for (var i = 0; i < goodConsumerCount; i++)
            Consumer(
              builder: (context, ref, _) => Text(
                'good$i:${ref.watch(good)}',
                textDirection: TextDirection.ltr,
              ),
            ),
          Consumer(
            builder: (context, ref, _) {
              ref.watch(bad);

              return const SizedBox();
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: ValueListenableBuilder(
            valueListenable: tickerEnabled,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: consumers,
          ),
        ),
      );
      for (var i = 0; i < goodConsumerCount; i++) {
        expect(find.text('good$i:0'), findsOneWidget);
      }

      final container = tester.container();

      // Hide the subtree: all consumer subscriptions get paused.
      tickerEnabled.value = false;
      await tester.pump();

      // While hidden:
      // - `good` updates; the paused subscriptions record a missed event.
      // - `bad` is invalidated; its element is inactive, so the scheduled
      //   refresh skips it, leaving it dirty. It will rebuild -- and throw
      //   from updateShouldNotify -- synchronously during resume.
      container.read(good.notifier).increment();
      container.invalidate(bad);
      await tester.pump();
      // The consumers were not rebuilt while hidden (paused = no
      // markNeedsBuild from provider updates).
      for (var i = 0; i < goodConsumerCount; i++) {
        expect(find.text('good$i:0'), findsOneWidget);
      }

      // Show the subtree again. The hub resumes every consumer; the bad
      // consumer's resume flushes its dirty provider, which throws. All good
      // consumers must still resume and replay their missed event.
      final errors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        tickerEnabled.value = true;
        await tester.pump();
      } finally {
        FlutterError.onError = oldOnError;
      }

      expect(
        errors.map((e) => e.exception.toString()),
        contains(contains('ThrowingEquality')),
        reason: 'the resume failure must be reported, not swallowed',
      );

      for (var i = 0; i < goodConsumerCount; i++) {
        expect(
          find.text('good$i:1'),
          findsOneWidget,
          reason:
              'consumer $i must have resumed and received the update that '
              'was emitted while it was hidden',
        );
      }
    },
  );
}
