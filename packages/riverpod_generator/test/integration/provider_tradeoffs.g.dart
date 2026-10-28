// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_tradeoffs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(generatedDefault)
final generatedDefaultProvider = GeneratedDefaultProvider._();

final class GeneratedDefaultProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedDefaultProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedDefaultProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedDefaultHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return generatedDefault(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedDefaultHash() => r'6dfbe5c57ff8731b247ada5a26d3e4914ebc5b38';

@ProviderFor(generatedRetained)
final generatedRetainedProvider = GeneratedRetainedProvider._();

final class GeneratedRetainedProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedRetainedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedRetainedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedRetainedHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return generatedRetained(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedRetainedHash() => r'9383c2077df08ff5a7d0a624aaf2aa539fc6b67e';

@ProviderFor(generatedPinned)
final generatedPinnedProvider = GeneratedPinnedProvider._();

final class GeneratedPinnedProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedPinnedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedPinnedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedPinnedHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return generatedPinned(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedPinnedHash() => r'4de51d60f50f4b3ff671aec13607878627a77f26';

@ProviderFor(GeneratedCounter)
final generatedCounterProvider = GeneratedCounterProvider._();

final class GeneratedCounterProvider
    extends $NotifierProvider<GeneratedCounter, int> {
  GeneratedCounterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedCounterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedCounterHash();

  @$internal
  @override
  GeneratedCounter create() => GeneratedCounter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedCounterHash() => r'c793d672054f13a9aad18b9d6ed58dc948bc1058';

abstract class _$GeneratedCounter extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(generatedFamily)
final generatedFamilyProvider = GeneratedFamilyFamily._();

final class GeneratedFamilyProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedFamilyProvider._({
    required GeneratedFamilyFamily super.from,
    required (int, {String locale}) super.argument,
  }) : super(
         retry: null,
         name: r'generatedFamilyProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$generatedFamilyHash();

  @override
  String toString() {
    return r'generatedFamilyProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as (int, {String locale});
    return generatedFamily(ref, argument.$1, locale: argument.locale);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneratedFamilyProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$generatedFamilyHash() => r'51f577406d5bcdc1908cb1ecbfe9fc93f5ae3321';

final class GeneratedFamilyFamily extends $Family
    with $FunctionalFamilyOverride<int, (int, {String locale})> {
  GeneratedFamilyFamily._()
    : super(
        retry: null,
        name: r'generatedFamilyProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GeneratedFamilyProvider call(int id, {String locale = 'en'}) =>
      GeneratedFamilyProvider._(argument: (id, locale: locale), from: this);

  @override
  String toString() => r'generatedFamilyProvider';
}

@ProviderFor(generatedListFamily)
final generatedListFamilyProvider = GeneratedListFamilyFamily._();

final class GeneratedListFamilyProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedListFamilyProvider._({
    required GeneratedListFamilyFamily super.from,
    required List<int> super.argument,
  }) : super(
         retry: null,
         name: r'generatedListFamilyProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$generatedListFamilyHash();

  @override
  String toString() {
    return r'generatedListFamilyProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as List<int>;
    return generatedListFamily(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneratedListFamilyProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$generatedListFamilyHash() =>
    r'7c41aeb395ecf8ff5d69bc3a740631c7cc1c6693';

final class GeneratedListFamilyFamily extends $Family
    with $FunctionalFamilyOverride<int, List<int>> {
  GeneratedListFamilyFamily._()
    : super(
        retry: null,
        name: r'generatedListFamilyProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GeneratedListFamilyProvider call(List<int> ids) =>
      GeneratedListFamilyProvider._(argument: ids, from: this);

  @override
  String toString() => r'generatedListFamilyProvider';
}

@ProviderFor(generatedGeneric)
final generatedGenericProvider = GeneratedGenericFamily._();

final class GeneratedGenericProvider<T>
    extends $FunctionalProvider<Type, Type, Type>
    with $Provider<Type> {
  GeneratedGenericProvider._({required GeneratedGenericFamily super.from})
    : super(
        argument: null,
        retry: null,
        name: r'generatedGenericProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedGenericHash();

  @override
  String toString() {
    return r'generatedGenericProvider'
        '<${T}>'
        '()';
  }

  @$internal
  @override
  $ProviderElement<Type> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Type create(Ref ref) {
    return generatedGeneric<T>(ref);
  }

  $R _captureGenerics<$R>($R Function<T>() cb) {
    return cb<T>();
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Type value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Type>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneratedGenericProvider &&
        other.runtimeType == runtimeType &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, argument);
  }
}

String _$generatedGenericHash() => r'dc5361bb5c6cb397797f917d535244625a296475';

final class GeneratedGenericFamily extends $Family {
  GeneratedGenericFamily._()
    : super(
        retry: null,
        name: r'generatedGenericProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GeneratedGenericProvider<T> call<T>() =>
      GeneratedGenericProvider<T>._(from: this);

  @override
  String toString() => r'generatedGenericProvider';

  /// {@macro riverpod.override_with}
  Override overrideWith(Type Function<T>(Ref ref) create) => $FamilyOverride(
    from: this,
    createElement: (pointer) {
      final provider = pointer.origin as GeneratedGenericProvider;
      return provider._captureGenerics(<T>() {
        provider as GeneratedGenericProvider<T>;
        return provider.$view(create: create<T>).$createElement(pointer);
      });
    },
  );
}

@ProviderFor(GeneratedFamilyCounter)
final generatedFamilyCounterProvider = GeneratedFamilyCounterFamily._();

final class GeneratedFamilyCounterProvider
    extends $NotifierProvider<GeneratedFamilyCounter, int> {
  GeneratedFamilyCounterProvider._({
    required GeneratedFamilyCounterFamily super.from,
    required (int, {int offset}) super.argument,
  }) : super(
         retry: null,
         name: r'generatedFamilyCounterProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$generatedFamilyCounterHash();

  @override
  String toString() {
    return r'generatedFamilyCounterProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  GeneratedFamilyCounter create() => GeneratedFamilyCounter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneratedFamilyCounterProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$generatedFamilyCounterHash() =>
    r'6d301f8e2c4cb84d69ab44d16e56343e663ed737';

final class GeneratedFamilyCounterFamily extends $Family
    with
        $ClassFamilyOverride<
          GeneratedFamilyCounter,
          int,
          int,
          int,
          (int, {int offset})
        > {
  GeneratedFamilyCounterFamily._()
    : super(
        retry: null,
        name: r'generatedFamilyCounterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GeneratedFamilyCounterProvider call(int id, {int offset = 2}) =>
      GeneratedFamilyCounterProvider._(
        argument: (id, offset: offset),
        from: this,
      );

  @override
  String toString() => r'generatedFamilyCounterProvider';
}

abstract class _$GeneratedFamilyCounter extends $Notifier<int> {
  late final _$args = ref.$arg as (int, {int offset});
  int get id => _$args.$1;
  int get offset => _$args.offset;

  int build(int id, {int offset = 2});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, offset: _$args.offset),
    );
  }
}

@ProviderFor(generatedFuture)
final generatedFutureProvider = GeneratedFutureProvider._();

final class GeneratedFutureProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  GeneratedFutureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedFutureProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedFutureHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return generatedFuture(ref);
  }
}

String _$generatedFutureHash() => r'f1106a74a2bd10544a4d9cd97453a11348056051';

@ProviderFor(generatedRawFuture)
final generatedRawFutureProvider = GeneratedRawFutureProvider._();

final class GeneratedRawFutureProvider
    extends
        $FunctionalProvider<
          Raw<Future<int>>,
          Raw<Future<int>>,
          Raw<Future<int>>
        >
    with $Provider<Raw<Future<int>>> {
  GeneratedRawFutureProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedRawFutureProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedRawFutureHash();

  @$internal
  @override
  $ProviderElement<Raw<Future<int>>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Raw<Future<int>> create(Ref ref) {
    return generatedRawFuture(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Raw<Future<int>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Raw<Future<int>>>(value),
    );
  }
}

String _$generatedRawFutureHash() =>
    r'f88edbbf3af18b6255ef4a08db0eeb211b2518dc';

@ProviderFor(generatedScoped)
final generatedScopedProvider = GeneratedScopedProvider._();

final class GeneratedScopedProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedScopedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedScopedProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[],
        $allTransitiveDependencies: <ProviderOrFamily>[],
      );

  @override
  String debugGetCreateSourceHash() => _$generatedScopedHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return generatedScoped(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedScopedHash() => r'7f70b4e9cdd00e044469421440ff7b9495f8d131';

@ProviderFor(generatedScopedConsumer)
final generatedScopedConsumerProvider = GeneratedScopedConsumerProvider._();

final class GeneratedScopedConsumerProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  GeneratedScopedConsumerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedScopedConsumerProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[generatedScopedProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          GeneratedScopedConsumerProvider.$allTransitiveDependencies0,
        ],
      );

  static final $allTransitiveDependencies0 = generatedScopedProvider;

  @override
  String debugGetCreateSourceHash() => _$generatedScopedConsumerHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return generatedScopedConsumer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$generatedScopedConsumerHash() =>
    r'058b5188a07e4f5ade0f5940f3c7b9ac00a2dbf7';

@ProviderFor(GeneratedEqual)
final generatedEqualProvider = GeneratedEqualProvider._();

final class GeneratedEqualProvider
    extends $NotifierProvider<GeneratedEqual, EqualValue> {
  GeneratedEqualProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generatedEqualProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generatedEqualHash();

  @$internal
  @override
  GeneratedEqual create() => GeneratedEqual();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EqualValue value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EqualValue>(value),
    );
  }
}

String _$generatedEqualHash() => r'dff2384060baf87d44110b4ea434c2f8f4778abe';

abstract class _$GeneratedEqual extends $Notifier<EqualValue> {
  EqualValue build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EqualValue, EqualValue>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EqualValue, EqualValue>,
              EqualValue,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
