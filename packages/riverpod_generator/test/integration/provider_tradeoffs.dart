// Research fixture for docs/research/handwritten-vs-generated-riverpod.md.
// Command methods intentionally mirror the APIs being compared.
// ignore_for_file: use_setters_to_change_properties

import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider_tradeoffs.g.dart';

final seedProvider = Provider<int>((ref) => 1, name: 'researchSeed');

@riverpod
int generatedDefault(Ref ref) => 1;

@Riverpod(keepAlive: true)
int generatedRetained(Ref ref) => 1;

@riverpod
int generatedPinned(Ref ref) {
  ref.keepAlive();
  return 1;
}

class ManualCounter extends Notifier<int> {
  @visibleForTesting
  int builds = 0;

  @override
  int build() {
    builds++;
    return ref.watch(seedProvider);
  }

  void increment() => state++;
}

final manualCounterProvider = NotifierProvider<ManualCounter, int>(
  ManualCounter.new,
  isAutoDispose: true,
  name: 'manualCounter',
);

@riverpod
class GeneratedCounter extends _$GeneratedCounter {
  @visibleForTesting
  int builds = 0;

  @override
  int build() {
    builds++;
    return ref.watch(seedProvider);
  }

  void increment() => state++;
}

@riverpod
int generatedFamily(Ref ref, int id, {String locale = 'en'}) =>
    id + locale.length;

@riverpod
int generatedListFamily(Ref ref, List<int> ids) => ids.length;

@riverpod
Type generatedGeneric<T>(Ref ref) => T;

@riverpod
class GeneratedFamilyCounter extends _$GeneratedFamilyCounter {
  @override
  int build(int id, {int offset = 2}) => id + offset;

  void reset() => state = id + offset;
}

class ManualFamilyCounter extends Notifier<int> {
  ManualFamilyCounter(this.args);
  final (int, {int offset}) args;

  @override
  int build() => args.$1 + args.offset;

  void reset() => state = args.$1 + args.offset;
}

final manualFamilyCounterProvider = NotifierProvider.autoDispose
    .family<ManualFamilyCounter, int, (int, {int offset})>(
      ManualFamilyCounter.new,
    );

@riverpod
Future<int> generatedFuture(Ref ref) async => 42;

@riverpod
Raw<Future<int>> generatedRawFuture(Ref ref) async => 42;

@Riverpod(keepAlive: true, dependencies: [])
int generatedScoped(Ref ref) => 1;

@Riverpod(keepAlive: true, dependencies: [generatedScoped])
int generatedScopedConsumer(Ref ref) => ref.watch(generatedScopedProvider) * 2;

// Value equality distinct from identity, to test notification filtering.
@immutable
class EqualValue {
  // Deliberately non-const: these probes require distinct object identities.
  // ignore: prefer_const_constructors_in_immutables
  EqualValue(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is EqualValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
class GeneratedEqual extends _$GeneratedEqual {
  @override
  EqualValue build() => EqualValue(1);

  void replace(EqualValue next) => state = next;
}

class ManualEqual extends Notifier<EqualValue> {
  @override
  EqualValue build() => EqualValue(1);

  void replace(EqualValue next) => state = next;
}

final manualEqualProvider =
    NotifierProvider.autoDispose<ManualEqual, EqualValue>(ManualEqual.new);
