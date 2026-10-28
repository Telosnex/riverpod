// Behavioral probes, not performance benchmarks. See the research document.
// Dynamic calls probe API absence/shared shape; explicit types/defaults test
// assignability and argument normalization rather than stylistic concision.
// ignore_for_file: avoid_dynamic_calls, avoid_redundant_argument_values, omit_local_variable_types

import 'package:riverpod/legacy.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' as codegen;
import 'package:test/test.dart';

import 'integration/provider_tradeoffs.dart';

void main() {
  test('bare defaults retain; generated defaults dispose', () async {
    final container = ProviderContainer.test();
    final bare = Provider<int>((ref) => 1);
    final bareAuto = Provider.autoDispose<int>((ref) => 1);
    final providers = [
      bare,
      bareAuto,
      generatedDefaultProvider,
      generatedRetainedProvider,
      generatedPinnedProvider,
    ];
    final subscriptions = [
      for (final provider in providers) container.listen(provider, (_, _) {}),
    ];
    for (final sub in subscriptions) {
      sub.close();
    }
    await container.pump();
    expect(providers.map(container.exists), [true, false, false, true, true]);
    expect(generatedPinnedProvider.isAutoDispose, isTrue);
    expect(
      NotifierProvider<ManualCounter, int>(ManualCounter.new).isAutoDispose,
      isFalse,
    );
    expect(generatedCounterProvider.isAutoDispose, isTrue);
  });

  test('pausing a strong listener is not the same as removing it', () async {
    final container = ProviderContainer.test();
    final bare = Provider.autoDispose<int>((ref) => 1);
    final a = container.listen(bare, (_, _) {});
    final b = container.listen(generatedDefaultProvider, (_, _) {});
    a.pause();
    b.pause();
    await container.pump();
    expect(container.exists(bare), isTrue);
    expect(container.exists(generatedDefaultProvider), isTrue);
    a.close();
    b.close();
    await container.pump();
    expect(container.exists(bare), isFalse);
    expect(container.exists(generatedDefaultProvider), isFalse);
  });

  for (final generated in [false, true]) {
    test(
      '${generated ? 'generated' : 'manual'} notifier survives rebuild and live invalidation',
      () async {
        final container = ProviderContainer.test(
          overrides: [seedProvider.overrideWithValue(1)],
        );
        final ProviderBase<int> provider =
            generated ? generatedCounterProvider : manualCounterProvider;
        final notifierProvider =
            generated
                ? generatedCounterProvider.notifier
                : manualCounterProvider.notifier;
        final sub = container.listen(provider, (_, _) {});
        final dynamic before = container.read(notifierProvider);
        before.increment();
        expect(container.read(provider), 2);
        container.updateOverrides([seedProvider.overrideWithValue(10)]);
        expect(container.read(provider), 10);
        expect(container.read(notifierProvider), same(before));
        expect(before.builds, 2);
        container.invalidate(provider);
        expect(container.read(provider), 10);
        expect(container.read(notifierProvider), same(before));
        expect(before.builds, 3);
        sub.close();
        await container.pump();
        expect(container.exists(provider), isFalse);
        final newSub = container.listen(provider, (_, _) {});
        expect(container.read(notifierProvider), isNot(same(before)));
        newSub.close();
      },
    );
  }

  test(
    'StateProvider replaces its controller when a watched input changes',
    () {
      final legacy = StateProvider<int>((ref) => ref.watch(seedProvider));
      final container = ProviderContainer.test(
        overrides: [seedProvider.overrideWithValue(1)],
      );
      final before = container.read(legacy.notifier);
      before.state = 9;
      container.updateOverrides([seedProvider.overrideWithValue(2)]);
      expect(container.read(legacy), 2);
      expect(container.read(legacy.notifier), isNot(same(before)));
    },
  );

  test('modern notifier variants both suppress equal nonidentical state', () {
    final container = ProviderContainer.test();
    var manualEvents = 0;
    var generatedEvents = 0;
    container.listen(manualEqualProvider, (_, _) => manualEvents++);
    container.listen(generatedEqualProvider, (_, _) => generatedEvents++);
    final original = container.read(manualEqualProvider);
    final replacement = EqualValue(1);
    expect(identical(original, replacement), isFalse);
    container.read(manualEqualProvider.notifier).replace(replacement);
    container.read(generatedEqualProvider.notifier).replace(EqualValue(1));
    expect([manualEvents, generatedEvents], [0, 0]);
    container.read(manualEqualProvider.notifier).replace(EqualValue(2));
    container.read(generatedEqualProvider.notifier).replace(EqualValue(2));
    expect([manualEvents, generatedEvents], [1, 1]);
  });

  test(
    'StateController identity filtering precedes provider equality filtering',
    () {
      final provider = StateProvider<EqualValue>((ref) => EqualValue(1));
      final container = ProviderContainer.test();
      var providerEvents = 0;
      var controllerEvents = 0;
      container.listen(provider, (_, _) => providerEvents++);
      final controller = container.read(provider.notifier);
      final remove = controller.addListener(
        (_) => controllerEvents++,
        fireImmediately: false,
      );
      addTearDown(remove);
      controller.state = EqualValue(1);
      expect(controllerEvents, 1);
      expect(providerEvents, 0);
    },
  );

  test('named/default family arguments and record family keys share state', () {
    final generated = generatedFamilyProvider(1);
    expect(generated, generatedFamilyProvider(1, locale: 'en'));
    expect(identical(generated, generatedFamilyProvider(1)), isFalse);
    final manual = Provider.autoDispose.family<int, (int, {String locale})>(
      (ref, args) => args.$1 + args.locale.length,
    );
    expect(manual((1, locale: 'en')), manual((1, locale: 'en')));
    final otherFamily = Provider.autoDispose
        .family<int, (int, {String locale})>((ref, args) => 0);
    expect(manual((1, locale: 'en')), isNot(otherFamily((1, locale: 'en'))));
    final container = ProviderContainer.test();
    final a = container.listen(generatedFamilyCounterProvider(1), (_, _) {});
    final b = container.listen(
      generatedFamilyCounterProvider(1, offset: 2),
      (_, _) {},
    );
    expect(
      container.read(generatedFamilyCounterProvider(1).notifier),
      same(
        container.read(generatedFamilyCounterProvider(1, offset: 2).notifier),
      ),
    );
    expect([a.read(), b.read()], [3, 3]);
    expect(container.read(manualFamilyCounterProvider((1, offset: 2))), 3);
  });

  test('generated keys do not add deep equality for collections', () {
    expect(
      generatedListFamilyProvider([1]),
      isNot(generatedListFamilyProvider([1])),
    );
    final ids = [1];
    expect(generatedListFamilyProvider(ids), generatedListFamilyProvider(ids));
  });

  test('generic type arguments are part of generated family identity', () {
    expect(generatedGenericProvider<int>(), generatedGenericProvider<int>());
    expect(
      generatedGenericProvider<int>(),
      isNot(generatedGenericProvider<num>()),
    );
    final container = ProviderContainer.test();
    expect(container.read(generatedGenericProvider<int>()), int);
    expect(container.read(generatedGenericProvider<num>()), num);
  });

  test('generated types are siblings, not public manual concrete types', () {
    final container = ProviderContainer.test();
    final Object provider = generatedDefaultProvider;
    final Object notifier = container.read(generatedCounterProvider.notifier);
    expect(provider, isA<ProviderListenable<int>>());
    expect(provider, isNot(isA<Provider<int>>()));
    expect(notifier, isA<AnyNotifier<int, int>>());
    expect(notifier, isNot(isA<Notifier<int>>()));
  });

  test('Raw preserves Future instead of exposing AsyncValue', () async {
    final container = ProviderContainer.test();
    final sub = container.listen(generatedFutureProvider, (_, _) {});
    expect(sub.read(), isA<AsyncLoading<int>>());
    expect(await container.read(generatedFutureProvider.future), 42);
    final Future<int> raw = container.read(generatedRawFutureProvider);
    expect(await raw, 42);
    expect(sub.read(), const AsyncData(42));
  });

  test(
    'generated and manual consumers participate in the same scope graph',
    () {
      final manualConsumer = Provider<int>(
        (ref) => ref.watch(generatedScopedProvider) * 3,
        dependencies: [generatedScopedProvider],
      );
      final root = ProviderContainer.test();
      expect(root.read(generatedScopedConsumerProvider), 2);
      expect(root.read(manualConsumer), 3);
      final child = ProviderContainer.test(
        parent: root,
        overrides: [generatedScopedProvider.overrideWithValue(10)],
      );
      expect(child.read(generatedScopedConsumerProvider), 20);
      expect(child.read(manualConsumer), 30);
      expect(root.read(generatedScopedConsumerProvider), 2);
    },
  );

  test('overrideWithBuild works with manual and generated notifiers', () {
    final container = ProviderContainer.test(
      overrides: [
        manualCounterProvider.overrideWithBuild((ref, notifier) => 7),
        generatedCounterProvider.overrideWithBuild((ref, notifier) => 7),
      ],
    );
    container.listen(manualCounterProvider, (_, _) {});
    container.listen(generatedCounterProvider, (_, _) {});
    container.read(manualCounterProvider.notifier).increment();
    container.read(generatedCounterProvider.notifier).increment();
    expect(container.read(manualCounterProvider), 8);
    expect(container.read(generatedCounterProvider), 8);
  });

  test(
    'generated sync notifier has value-only override absent on manual class',
    () {
      final container = ProviderContainer.test(
        overrides: [generatedCounterProvider.overrideWithValue(7)],
      );
      expect(container.read(generatedCounterProvider), 7);
      expect(
        () => container.read(generatedCounterProvider.notifier),
        throwsA(isA<TypeError>()),
      );
      final dynamic manual = manualCounterProvider;
      expect(() => manual.overrideWithValue(7), throwsNoSuchMethodError);
    },
  );

  test(
    'generated metadata supplies name and source hash; bare naming is optional',
    () {
      final bare = Provider<int>((ref) => 1);
      final named = Provider<int>((ref) => 1, name: 'explicitName');
      expect(bare.name, isNull);
      expect(named.name, 'explicitName');
      expect(bare.debugGetCreateSourceHash(), isNull);
      expect(generatedDefaultProvider.name, 'generatedDefaultProvider');
      expect(generatedDefaultProvider.debugGetCreateSourceHash(), isNotEmpty);
    },
  );

  test('bare Provider exposes objects but does not observe their fields', () {
    final provider = Provider<MutableService>((ref) => MutableService());
    final container = ProviderContainer.test();
    var events = 0;
    container.listen(provider, (_, _) => events++);
    container.read(provider).count++;
    expect(container.read(provider).count, 1);
    expect(events, 0);
  });

  test('reassemble invalidates changed source hashes, not bare providers', () {
    final container = ProviderContainer.test();
    var value = 1;
    final hashed = ReloadProbeProvider(() => value);
    final bare = Provider<int>((ref) => value);
    container.listen(hashed, (_, _) {});
    container.listen(bare, (_, _) {});
    expect(container.read(hashed), 1);
    expect(container.read(bare), 1);
    value = 2;
    container.debugReassemble();
    expect(container.read(hashed), 1);
    hashed.sourceHash = 'edited declaration';
    container.debugReassemble();
    expect(container.read(hashed), 2);
    expect(container.read(bare), 1);
    container.invalidate(bare);
    expect(container.read(bare), 2);
  });
}

class MutableService {
  int count = 0;
}

// Deliberately mirrors generated internals to vary the hash in-process.
// This tests Riverpod reassembly, NOT Dart VM/Flutter hot reload itself.
final class ReloadProbeProvider
    extends codegen.$FunctionalProvider<int, int, int>
    with codegen.$Provider<int> {
  ReloadProbeProvider(this.compute)
    : super(
        name: 'reloadProbe',
        from: null,
        argument: null,
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
        retry: null,
      );

  final int Function() compute;
  String sourceHash = 'original declaration';

  @override
  String debugGetCreateSourceHash() => sourceHash;

  @override
  int create(Ref ref) => compute();

  @override
  codegen.$ProviderElement<int> $createElement(
    codegen.$ProviderPointer pointer,
  ) => codegen.$ProviderElement<int>(pointer);
}
