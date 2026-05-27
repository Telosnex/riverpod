import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Consumer establishes a TickerMode dependency to resync paused subscriptions',
    (tester) async {
      final provider = Provider<int>((ref) => 0);
      final tickerEnabled = ValueNotifier<bool>(true);
      var builds = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: tickerEnabled,
              child: Consumer(
                builder: (context, ref, child) {
                  ref.watch(provider);
                  builds++;
                  return Text('builds:$builds');
                },
              ),
              builder: (context, enabled, child) {
                return TickerMode(enabled: enabled, child: child!);
              },
            ),
          ),
        ),
      );

      expect(find.text('builds:1'), findsOneWidget);

      tickerEnabled.value = false;
      await tester.pump();

      expect(
        find.text('builds:2'),
        findsOneWidget,
        reason:
            'When TickerMode changes, Consumer must rebuild so provider '
            'subscriptions are paused in sync with the visible tree.',
      );

      tickerEnabled.value = true;
      await tester.pump();

      expect(
        find.text('builds:3'),
        findsOneWidget,
        reason:
            'When TickerMode changes back, Consumer must rebuild so paused '
            'provider subscriptions are resumed.',
      );
    },
  );
}
