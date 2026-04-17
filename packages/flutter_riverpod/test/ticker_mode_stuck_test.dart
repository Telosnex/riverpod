import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/legacy.dart';

// Reproduces "stuck column count" bug.
//
// Symptom: after navigating Home -> Chat -> Home, a ConsumerWidget on Home
// stops receiving provider updates (won't rebuild on provider change).

void main() {
  testWidgets(
    'H1: widget receives provider update that happened while paused',
    (tester) async {
      final counterProvider = StateProvider<int>((ref) => 0);
      final tickerOn = ValueNotifier<bool>(true);

      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: tickerOn,
              builder: (context, on, _) => TickerMode(
                enabled: on,
                child: Consumer(
                  builder: (ctx, ref, _) {
                    buildCount++;
                    final val = ref.watch(counterProvider);
                    return Text('v:$val', textDirection: TextDirection.ltr);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('v:0'), findsOneWidget);
      final initialBuilds = buildCount;

      // 1. Turn off TickerMode (simulate navigating away).
      tickerOn.value = false;
      await tester.pump();

      // 2. Update provider while "paused".
      final container = ProviderScope.containerOf(
        tester.element(find.text('v:0')),
      );
      container.read(counterProvider.notifier).state = 42;
      await tester.pump();

      // Still shows old value because paused.
      expect(find.text('v:0'), findsOneWidget);

      // 3. Turn TickerMode back on (simulate navigating back).
      tickerOn.value = true;
      await tester.pump();
      await tester.pump(); // extra pump for post-frame defers

      // Should now show updated value.
      expect(
        find.text('v:42'),
        findsOneWidget,
        reason:
            'After resume, widget should rebuild with value that changed during pause',
      );

      print('Initial builds: $initialBuilds, final: $buildCount');
    },
  );

  testWidgets(
    'H2: multiple providers, one updates during pause',
    (tester) async {
      final provA = StateProvider<int>((ref) => 0);
      final provB = StateProvider<int>((ref) => 0);
      final tickerOn = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: tickerOn,
              builder: (context, on, _) => TickerMode(
                enabled: on,
                child: Consumer(
                  builder: (ctx, ref, _) {
                    final a = ref.watch(provA);
                    final b = ref.watch(provB);
                    return Text(
                      'a=$a,b=$b',
                      textDirection: TextDirection.ltr,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('a=0,b=0'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.text('a=0,b=0')),
      );

      tickerOn.value = false;
      await tester.pump();

      container.read(provA.notifier).state = 1;
      container.read(provB.notifier).state = 2;
      await tester.pump();
      expect(find.text('a=0,b=0'), findsOneWidget); // paused

      tickerOn.value = true;
      await tester.pump();
      await tester.pump();

      expect(find.text('a=1,b=2'), findsOneWidget);
    },
  );

  testWidgets(
    'H3: derived (keepAlive) provider updates during pause',
    (tester) async {
      // Mimic maxColumnCountProvider: keepAlive provider that watches another.
      final source = StateProvider<int>((ref) => 100);
      final derived = Provider<int>((ref) {
        final s = ref.watch(source);
        return s ~/ 10;
      });

      final tickerOn = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: tickerOn,
              builder: (context, on, _) => TickerMode(
                enabled: on,
                child: Consumer(
                  builder: (ctx, ref, _) {
                    final val = ref.watch(derived);
                    return Text('d:$val', textDirection: TextDirection.ltr);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('d:10'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.text('d:10')),
      );

      // Pause, update source, resume.
      tickerOn.value = false;
      await tester.pump();

      container.read(source.notifier).state = 500;
      await tester.pump();
      expect(find.text('d:10'), findsOneWidget);

      tickerOn.value = true;
      await tester.pump();
      await tester.pump();

      expect(find.text('d:50'), findsOneWidget);
    },
  );

  testWidgets(
    'H5: Navigator push/pop simulates real nav with TickerMode changes',
    (tester) async {
      final prov = StateProvider<int>((ref) => 0);
      final navKey = GlobalKey<NavigatorState>();

      Widget homeBody() => Consumer(
        builder: (ctx, ref, _) {
          final v = ref.watch(prov);
          return Text('home:$v', textDirection: TextDirection.ltr);
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(body: homeBody()),
          ),
        ),
      );

      expect(find.text('home:0'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('home:0')),
      );

      // Push a new route (Home becomes inactive via TickerMode).
      unawaited(navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('chat')),
        ),
      ));
      await tester.pumpAndSettle();

      // Update provider while Home is "in background".
      container.read(prov.notifier).state = 99;
      await tester.pump();

      // Pop back to Home.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(
        find.text('home:99'),
        findsOneWidget,
        reason: 'Home should show updated value after pop',
      );
    },
  );

  testWidgets(
    'H6: provider updates DURING navigation animation',
    (tester) async {
      final prov = StateProvider<int>((ref) => 0);
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) {
                  final v = ref.watch(prov);
                  return Text('home:$v', textDirection: TextDirection.ltr);
                },
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('home:0')),
      );

      unawaited(navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('chat')),
        ),
      ));
      // Pump partial frames of the transition animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Update provider mid-animation.
      container.read(prov.notifier).state = 1;
      await tester.pump(const Duration(milliseconds: 50));
      container.read(prov.notifier).state = 2;
      await tester.pumpAndSettle();

      // Pop back.
      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      container.read(prov.notifier).state = 3;
      await tester.pumpAndSettle();

      expect(find.text('home:3'), findsOneWidget);
    },
  );

  testWidgets(
    'H7: widget watches multiple, one updates during transition, pop back',
    (tester) async {
      final a = StateProvider<int>((ref) => 0);
      final b = StateProvider<int>((ref) => 0);
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) {
                  final av = ref.watch(a);
                  final bv = ref.watch(b);
                  return Text(
                    'a=$av,b=$bv',
                    textDirection: TextDirection.ltr,
                  );
                },
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('a=0,b=0')),
      );

      // Push, update a during animation, pop, update b.
      unawaited(navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('chat')),
        ),
      ));
      await tester.pump();
      container.read(a.notifier).state = 5;
      await tester.pumpAndSettle();

      navKey.currentState!.pop();
      await tester.pump();
      container.read(b.notifier).state = 7;
      await tester.pumpAndSettle();

      expect(find.text('a=5,b=7'), findsOneWidget);
    },
  );

  testWidgets(
    'H8: GlobalKey reparenting between different TickerMode ancestors',
    (tester) async {
      final prov = StateProvider<int>((ref) => 0);
      final consumerKey = GlobalKey();
      final parentOn = ValueNotifier<bool>(true);

      Widget consumer() => Consumer(
        key: consumerKey,
        builder: (ctx, ref, _) {
          final v = ref.watch(prov);
          return Text('v:$v', textDirection: TextDirection.ltr);
        },
      );

      // Two separate TickerMode subtrees. Reparent the consumer between them.
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: parentOn,
              builder: (context, onLeft, _) => Row(
                children: [
                  TickerMode(
                    enabled: onLeft,
                    child: onLeft ? consumer() : const SizedBox(),
                  ),
                  TickerMode(
                    enabled: !onLeft,
                    child: !onLeft ? consumer() : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('v:0'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('v:0')),
      );

      // Reparent to right side (different TickerMode ancestor, both enabled).
      parentOn.value = false;
      await tester.pump();

      // Update provider.
      container.read(prov.notifier).state = 1;
      await tester.pump();

      expect(
        find.text('v:1'),
        findsOneWidget,
        reason: 'After reparent, widget should still receive updates',
      );
    },
  );

  testWidgets(
    'H9: reparent from enabled TickerMode to disabled, then update provider',
    (tester) async {
      final prov = StateProvider<int>((ref) => 0);
      final consumerKey = GlobalKey();
      final atTop = ValueNotifier<bool>(true);

      Widget consumer() => Consumer(
        key: consumerKey,
        builder: (ctx, ref, _) {
          final v = ref.watch(prov);
          return Text('v:$v', textDirection: TextDirection.ltr);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: atTop,
              builder: (context, top, _) => Column(
                children: [
                  TickerMode(
                    enabled: true,
                    child: top ? consumer() : const SizedBox(),
                  ),
                  TickerMode(
                    enabled: false,
                    child: !top ? consumer() : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('v:0'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('v:0')),
      );

      // Reparent to disabled TickerMode.
      atTop.value = false;
      await tester.pump();

      // Update provider while in disabled TickerMode.
      container.read(prov.notifier).state = 1;
      await tester.pump();

      // Widget is now under disabled TickerMode - should not update yet.
      // (But if our code is buggy and didn't properly pause after reparent,
      // it might update anyway. That's not the stuck-bug.)

      // Reparent BACK to enabled TickerMode.
      atTop.value = true;
      await tester.pump();
      await tester.pump();

      expect(
        find.text('v:1'),
        findsOneWidget,
        reason:
            'After reparenting back to enabled TickerMode, widget should show updated value',
      );
    },
  );

  testWidgets(
    'H10: subscription stays paused after reparenting from disabled to enabled TickerMode',
    (tester) async {
      // This tests the bug: _ensureTickerModeSubscribed updates _isActive
      // without syncing subscription pause/resume state.
      final prov = StateProvider<int>((ref) => 0);
      final consumerKey = GlobalKey();
      final atTop = ValueNotifier<bool>(false); // start under disabled ticker

      Widget consumer() => Consumer(
        key: consumerKey,
        builder: (ctx, ref, _) {
          final v = ref.watch(prov);
          return Text('v:$v', textDirection: TextDirection.ltr);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: atTop,
              builder: (context, top, _) => Column(
                children: [
                  TickerMode(
                    enabled: true,
                    child: top ? consumer() : const SizedBox(),
                  ),
                  TickerMode(
                    enabled: false,
                    child: !top ? consumer() : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Widget initialized under disabled TickerMode.
      // _isActive should be false at this point. Subs paused on creation.
      expect(find.text('v:0'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('v:0')),
      );

      // Update provider while paused (expected not to update).
      container.read(prov.notifier).state = 42;
      await tester.pump();
      expect(find.text('v:0'), findsOneWidget);

      // Reparent to enabled TickerMode. Without sub.resume(), stays stuck.
      atTop.value = true;
      await tester.pump();
      await tester.pump();

      expect(
        find.text('v:42'),
        findsOneWidget,
        reason:
            'After reparent to enabled TickerMode, widget should resume and show missed update',
      );

      // Now update again. If sub is still paused, widget won't update.
      container.read(prov.notifier).state = 100;
      await tester.pump();
      expect(
        find.text('v:100'),
        findsOneWidget,
        reason:
            'After reparent, sub should be resumed and receive NEW updates',
      );
    },
  );

  testWidgets(
    'H4: repeated pause/resume cycles with updates each time',
    (tester) async {
      final prov = StateProvider<int>((ref) => 0);
      final tickerOn = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            child: ValueListenableBuilder<bool>(
              valueListenable: tickerOn,
              builder: (context, on, _) => TickerMode(
                enabled: on,
                child: Consumer(
                  builder: (ctx, ref, _) {
                    final v = ref.watch(prov);
                    return Text('v:$v', textDirection: TextDirection.ltr);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('v:0')),
      );

      for (var i = 1; i <= 5; i++) {
        tickerOn.value = false;
        await tester.pump();

        container.read(prov.notifier).state = i;
        await tester.pump();

        tickerOn.value = true;
        await tester.pump();
        await tester.pump();

        expect(
          find.text('v:$i'),
          findsOneWidget,
          reason: 'cycle $i: should show updated value',
        );
      }
    },
  );
}
