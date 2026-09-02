// Guards the scoping contract of ProviderTrace: enabling the hook in a large
// app must emit nothing for providers outside the filter.
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/src/internals.dart' show ProviderTrace;
import 'package:test/test.dart';

class Counter extends Notifier<int> {
  @override
  int build() => 0;
  void inc() => state++;
}

void main() {
  tearDown(() {
    ProviderTrace.hook = null;
    ProviderTrace.filter = null;
  });

  test('emits nothing when only hook is set (filter required)', () async {
    final events = <String>[];
    ProviderTrace.hook = (event, _) => events.add(event);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final counter = NotifierProvider<Counter, int>(Counter.new);
    final derived = Provider<int>((ref) => ref.watch(counter) * 2);
    container.listen(derived, (_, _) {});
    container.read(counter.notifier).inc();
    await container.pump();
    expect(events, isEmpty);
  });

  test('emits only for providers matching the filter', () async {
    final events = <(String, String?)>[];
    final counter = NotifierProvider<Counter, int>(
      Counter.new,
      name: 'counter',
    );
    final traced = Provider<int>(
      (ref) => ref.watch(counter) * 2,
      name: 'traced',
    );
    final untraced = Provider<int>(
      (ref) => ref.watch(counter) + 1,
      name: 'untraced',
    );
    ProviderTrace.hook =
        (event, fields) => events.add((event, fields['provider'] as String?));
    ProviderTrace.filter = (origin) => origin.name == 'traced';

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(traced, (_, _) {});
    container.listen(untraced, (_, _) {});
    events.clear();

    container.read(counter.notifier).inc();
    await container.pump();

    expect(
      events.map((e) => e.$1),
      containsAll(['markDirty', 'scheduleRefresh', 'flush']),
    );
    final named = events.where((e) => e.$2 != null).map((e) => e.$2!);
    expect(named, everyElement('traced'));
    expect(named, isNot(contains('untraced')));
    expect(named, isNot(contains('counter')));
  });

  test('flush reports whether the scheduler task drove it', () async {
    final events = <Map<String, Object?>>[];
    final counter = NotifierProvider<Counter, int>(
      Counter.new,
      name: 'counter',
    );
    final traced = Provider<int>(
      (ref) => ref.watch(counter) * 2,
      name: 'traced',
    );
    ProviderTrace.hook = (event, fields) {
      if (event == 'flush') events.add(fields);
    };
    ProviderTrace.filter = (origin) => origin.name == 'traced';

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(traced, (_, _) {});

    // Synchronous read while dirty: consumer-driven flush.
    container.read(counter.notifier).inc();
    container.read(traced);
    expect(events.single['fromTask'], isFalse);
    events.clear();

    // Let the scheduler do it: task-driven flush.
    container.read(counter.notifier).inc();
    await container.pump();
    expect(events.single['fromTask'], isTrue);
  });
}
