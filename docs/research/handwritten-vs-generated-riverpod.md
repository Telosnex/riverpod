# Handwritten providers versus `@riverpod`: semantics, machinery, and engineering tradeoffs

## Scope and evidence

This is an implementation-led study of **this checkout**, not a timeless statement about every Riverpod release.

| Component | Examined version |
|---|---|
| Repository baseline | `a2ca05a590d26c9bdeb6f4a320ef6d08e7f77216` |
| `riverpod` / `flutter_riverpod` | `3.3.2` |
| `riverpod_generator` | `4.0.4` |
| `riverpod_annotation` | `4.0.3` |
| SDK used for the probes | Dart `3.13.1`, macOS ARM64 |

This is the **Telosnex fork**. Its scheduler, Flutter integration, tracing, and DevTools changes matter when interpreting local behavior. Matching package version numbers do not prove that an upstream release has identical internals.

Evidence used:

1. Runtime implementation, generator templates, analyzer/parser implementation, and actual generated output.
2. **18 new behavioral probes**, with generated fixtures produced by the real generator.
3. A focused run of **80 passing tests**, comprising those probes and 12 existing generator test files.
4. Static analysis of the new handwritten fixture and test file.

The new tests are [here][probes], the annotated/manual fixtures are [here][fixture], and the emitted implementation is [here][output]. No application/runtime implementation was changed.

**Limits:** no representative application performance benchmark, AOT size comparison, browser run, or end-to-end Flutter/VM hot-reload session was performed. The reassembly probe simulates a changed source hash; it does not simulate the Dart VM. Source-derived conclusions and engineering recommendations below should not be confused with measurements. Absolute “100%” certainty across future versions, platforms, and application designs would not be an honest claim.

### Reading paths

- **Make a decision:** [executive answer](#1-executive-answer), [use cases](#16-recommended-decisions-by-use-case), [migration checklist](#17-migration-checklist-preserve-behavior-before-changing-design).
- **Understand the engine:** [generated machinery](#3-what-generation-actually-emits), [lifetime](#4-lifetime-the-biggest-migration-hazard), [StateProvider](#5-stateprovider-versus-a-notifier-genuinely-different-abstractions).
- **Investigate the sharp edges:** [families](#6-families-ergonomic-advantage-with-real-identity-rules), [hot reload](#7-hot-reload-useful-but-precisely-bounded), [scoping](#8-scoping-and-dependencies-more-than-documentation), [overrides](#9-testing-and-overrides-largely-shared-not-byte-for-byte-identical).
- **Audit the conclusion:** [performance methodology](#13-performance-decompose-the-question-before-benchmarking), [reproduction and evidence](#19-reproduction-and-evidence-ledger).

---

## 1. Executive answer

**A handwritten `NotifierProvider` is not a lesser state-management engine than an annotated notifier.** Once provider kind, lifetime, dependencies, equality policy, and overrides are aligned, both run through the same notifier/provider-element machinery.

But “a bare `Provider`/`StateProvider` versus an annotated class” combines two independent decisions:

1. **Which semantics?** Read-only derivation/service, publicly writable state cell, or notifier with a command API?
2. **Which declaration mechanism?** Explicit Dart constructors or generated Dart from annotations?

Changing both at once makes it easy to attribute benefits to code generation that actually come from switching to `Notifier`.

The largest practical tradeoffs are:

| Dimension | Handwritten | Generated |
|---|---|---|
| Core caching/reactivity | Full Riverpod runtime | Same runtime for corresponding provider kinds |
| Default lifetime | Retained when unused | Auto-dispose |
| State mutation API | Whatever provider kind you choose | Class exposes notifier commands; function does not create a notifier |
| Family call syntax | One argument; records/value objects encode more | Positional, named, optional/default parameters; generated generic families |
| Hot-reload invalidation | No generated source hash | Declaration hash triggers provider invalidation after regeneration/reassembly |
| Concrete Dart types | Public `Provider`, `Notifier`, etc. | Generated sibling types over internal shared bases |
| Debug names | Explicit `name:` | Generated names and source metadata |
| Scoped dependency tooling | Runtime support; manually maintain metadata | Generated metadata plus annotation-aware linting, with interoperability limits |
| Build pipeline | No Riverpod generation step | Builder/analyzer dependencies, generated artifacts, watch/CI workflow |
| Constructors/reuse | Arbitrary valid factories and reusable notifier classes | Generated factory calls an unnamed zero-required-argument constructor; arguments enter through `build` |
| Legacy providers | Available explicitly | No direct generated `StateProvider`/`StateNotifierProvider`/`ChangeNotifierProvider` equivalent |
| Experimental JSON persistence | Explicit serialization/key wiring | Additional `@JsonPersist` convenience |

**Default recommendation:** choose the smallest correct provider kind first. Use handwritten modern providers confidently when avoiding code generation has real value. Use generation when its family ergonomics, reload behavior, and tooling repay its workflow cost—especially in a project already running builders. Neither style needs a purity rule.

---

## 2. Separate the three axes

### 2.1 State model

- **`Provider<T>`:** derive/cache/expose a value. It can expose a service with methods. It does not observe arbitrary mutations inside that service.
- **`FutureProvider<T>` / `StreamProvider<T>`:** expose asynchronous initialization/stream output as `AsyncValue<T>`.
- **`NotifierProvider<N, T>`:** own synchronous reactive state with a notifier-defined command API.
- **`AsyncNotifierProvider<N, T>` / `StreamNotifierProvider<N, T>`:** notifier command API plus asynchronous/stream initialization.
- **`StateProvider<T>`:** expose a `StateController<T>` with a public setter/update operation. In this checkout this is a **legacy** API, imported from `package:riverpod/legacy.dart` (or the corresponding Flutter legacy library).
- **`StateNotifierProvider` / `ChangeNotifierProvider`:** adapters for their respective existing state objects, also legacy APIs in Riverpod 3.

### 2.2 Declaration mechanism

You can write the modern provider constructors yourself, or use an annotation to generate the declaration and supporting types.

`@riverpod` is the default constant `Riverpod()` annotation. `@Riverpod(...)` is the configurable form. They are not different runtime systems.

### 2.3 Lifetime and scope

Auto-disposal, dynamic keep-alive, dependency invalidation, family keys, and container scoping are additional choices. They do not follow inevitably from “class” or “function.”

For example, these are the closest semantic pair:

```dart
final counterProvider = NotifierProvider.autoDispose<Counter, int>(Counter.new);

class Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}
```

```dart
// In a library importing riverpod_annotation and declaring its generated part:
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
```

They are **alternatives**, not declarations to put in one library together. Both yield a state provider watched as `int`, and a `.notifier` projection used to call `increment`.

A bare `Provider<int>((ref) => 0)` is not an equivalent alternative to either one: it has no counter mutation API. A generated function returning `int` is its corresponding generated form.

---

## 3. What generation actually emits

### 3.1 Mapping from declaration to behavior

Ignoring lifetime defaults for a moment:

| Annotated declaration | Corresponding handwritten semantics | Value watched by a consumer |
|---|---|---|
| Function returning `T` | `Provider<T>` | `T` |
| Function returning `Future<T>` or `FutureOr<T>` | `FutureProvider<T>` | `AsyncValue<T>` |
| Function returning `Stream<T>` | `StreamProvider<T>` | `AsyncValue<T>` |
| Class whose `build` returns `T` | `NotifierProvider<…, T>` | `T` |
| Class whose `build` returns `Future<T>` or `FutureOr<T>` | `AsyncNotifierProvider<…, T>` | `AsyncValue<T>` |
| Class whose `build` returns `Stream<T>` | `StreamNotifierProvider<…, T>` | `AsyncValue<T>` |

The generator selects from the **declared return type**, not merely the presence of the `async` keyword. A non-`async` function returning a `Future<T>` still receives asynchronous provider semantics. `FutureOr<T>` can produce data synchronously; it does not promise a visible loading frame.

`Raw<T>` is the opt-out metadata/type alias. For example:

- `Raw<Future<int>>` produces a synchronous provider whose value is a `Future<int>`.
- `Future<Raw<MyObject>>` still has outer future handling.
- `Raw<Stream<T>>` does not automatically subscribe and expose stream events as `AsyncValue<T>`.

The [return-type parser][provider-parser] and [provider template][provider-template] implement this. The probes verify raw versus unwrapped futures.

### 3.2 Shared implementation, not necessarily the same public class

The relevant inheritance paths are approximately:

```text
Manual function provider:
  Provider<T>
    -> $FunctionalProvider<T, T, T>
    -> shared provider/container infrastructure
  creates $ProviderElement<T>

Generated function provider:
  MyValueProvider
    -> $FunctionalProvider<T, T, T>
    -> shared provider/container infrastructure
  creates $ProviderElement<T>

Manual notifier:
  Counter -> Notifier<T> -> $Notifier<T> -> AnyNotifier<T, T>
  NotifierProvider<Counter, T> -> $NotifierProvider<Counter, T>

Generated notifier:
  Counter -> _$Counter -> $Notifier<T> -> AnyNotifier<T, T>
  CounterProvider -> $NotifierProvider<Counter, T>
```

Both notifier providers use `$NotifierProviderElement`. Their build adapters converge on `element.handleCreate(...)`; state notification, dependency tracking, scheduling, and disposal are shared.

Generated code supplies such things as:

- The provider/family variable and concrete types.
- The appropriate provider kind and auto-dispose flag.
- A create function or notifier factory.
- A generated notifier base and build adapter.
- Family argument storage/accessors, call signature, equality and hashing.
- Names, source hash, `@ProviderFor` correspondence, dependency metadata.
- Relevant override conveniences.

There is no annotation interpreter evaluating your provider on every read. This is ordinary compiled Dart source, not runtime reflection or a separate service container.

The original annotated function is still an ordinary Dart function. Calling it directly does not consult the generated provider's cache/identity or reproduce its async/lifecycle machinery; consume the generated provider through Riverpod instead. Similarly, directly constructing an annotated notifier does not attach it to a container or initialize its `ref`/state.

**Important terminology trap:** `LegacyProviderMixin` is used by handwritten **modern** providers too. Its name does not make `NotifierProvider` deprecated. In this implementation it supplies manual provider identity/equality and a null source hash. Do not conflate it with the APIs exported from `legacy.dart`.

### 3.3 Why the nominal type difference matters

In this checkout:

```text
generatedDefaultProvider is Provider<int>        -> false
generatedCounter is Notifier<int>                -> false
 generatedCounter is AnyNotifier<int, int>       -> true
```

These were tested. The generated and public manual classes are siblings over shared bases, not subclasses of one another.

Consequences:

- A helper accepting only `Provider<T>` unnecessarily excludes generated providers and other provider kinds.
- A mixin constrained with `on Notifier<T>` does not automatically work on generated notifiers.
- You cannot assume `NotifierProvider<GeneratedCounter, int>(GeneratedCounter.new)` meets the public generic bound.
- Migration can break helper APIs, runtime type checks, mocks, and inheritance despite leaving every `ref.watch` call unchanged.

Use a public interface matching the operation: for example, `ProviderListenable<T>` for consumption, `Refreshable<T>` where refreshability is required, or `AnyNotifier<StateT, ValueT>` for shared notifier mixins. Some of these interfaces are exported by `package:riverpod/misc.dart`. Do not reach for `$` internals in application code to force interoperability.

Nor should every API be widened indiscriminately: `ProviderListenable<T>` does not promise every kind of override, `.future`, or `.notifier` operation. Preserve those stronger types where needed.

---

## 4. Lifetime: the biggest migration hazard

### 4.1 Defaults are opposite

The manual constructors have `isAutoDispose = false`. The annotation has `keepAlive = false`, and generation emits `isAutoDispose: !keepAlive`.

| Intent | Handwritten | Generated |
|---|---|---|
| Dispose when no longer listened to | `.autoDispose` or `isAutoDispose: true` | `@riverpod` / `@Riverpod(keepAlive: false)` |
| Retain unused state in its container | Default constructor behavior | `@Riverpod(keepAlive: true)` |

This applies to both functional and notifier-based declarations and to their families.

A migration that changes nothing but spelling can therefore reset a search/filter/counter on navigation, refetch data, close connections, or retain a large family cache indefinitely in the reverse direction.

**Recommendation:** make lifetime explicit during migrations. Preserve it first; change caching policy separately with tests.

### 4.2 Provider declaration, provider element, and state are different objects

A top-level provider variable is a descriptor/identity. The container owns the live element and state. Two unrelated root containers can hold independent states for the same provider descriptor.

Destroying an auto-disposed state does not erase the top-level provider declaration. A later read can construct fresh state. Neither a global variable nor a generated class means “one application-global state object forever.” Nested containers can also share or redirect ownership according to scoping metadata and overrides; do not assume every child container independently instantiates everything.

### 4.3 Keep-alive is not permanence, eagerness, or persistence

For both declaration styles:

- A retained provider is still initialized lazily.
- `keepAlive: true` does not stop dependency-triggered recomputation.
- `ref.keepAlive()` creates a retention link for an auto-disposed build; it is not the annotation flag itself.
- Closing that link allows normal disposal eligibility again.
- Build cleanup/recomputation resets the build's keep-alive registrations.
- Container disposal still tears down the state.
- In-memory keep-alive is not disk persistence.
- A non-family provider can still need auto-disposal; a family is not automatically safe just because it is generated.

Retained family instances can accumulate per distinct key. Auto-disposal limits unused state retention; it is not a bounded LRU cache, TTL, or a guarantee that a still-listened-to working set is small.

### 4.4 Rebuild is not notifier destruction

For modern manual **and** generated notifiers:

1. The factory creates a notifier when the live class-provider element first needs it.
2. `build` computes state and establishes dependencies/cleanup for that build.
3. A watched dependency change reruns `build` on the **same notifier instance**.
4. A manual invalidation of an actively listened-to notifier also preserves that instance in the tested path.
5. Actual auto-disposal followed by new use creates a **new notifier instance**.

The probes verify identity, build count, and state reset across these transitions in both declaration styles.

This is why “move initialization from `build` to the constructor so it only happens once” is dangerous. `ref`/`state` are not ready in the constructor, and constructor-owned resources can become inconsistent with per-build cleanup. `ref.onDispose` also runs on build invalidation/cleanup; it is not exclusively a final destructor for the Dart notifier object.

A private notifier field may survive a rebuild while `state` is replaced with the new build result. This can be useful for counters/tokens, but is not a substitute for deliberately reactive state.

### 4.5 Reads, listeners, pauses, and weak listeners

`ref.read` does not establish the persistent reactive subscription that `watch` does. Code/tests that need an auto-disposed provider to survive an asynchronous gap must arrange an appropriate subscription or retention policy. Merely fetching `.notifier` is not a lifetime lease.

In this fork, distinguish:

- `isActive`: based on non-paused active listener accounting; relevant to scheduled refresh.
- `hasNonWeakListeners`: checked by the scheduler before actual disposal.

A **paused strong subscription is not the same as removing it**. The probes pause manual/generated auto-dispose providers, pump the scheduler, and confirm that they remain mounted until those subscriptions are closed. Weak listeners do not supply normal retention.

Flutter's visibility/TickerMode integration and the fork's scheduler fixes operate underneath both declaration styles. An annotation is not a cure for a paused consumer or a scheduling problem. Inspect subscriptions and lifetimes, rather than changing provider syntax to make a stale screen “work.”

Sources: [annotation][annotation], [notifier element][class-core], [element lifecycle][element], [scheduler][scheduler], [Ref][ref].

---

## 5. `StateProvider` versus a notifier: genuinely different abstractions

A minimal state cell is convenient:

```dart
final countProvider = StateProvider<int>((ref) => 0);
// Any consumer can do:
ref.read(countProvider.notifier).state++;
```

A notifier makes allowed transitions explicit:

```dart
ref.read(countProvider.notifier).increment();
```

**That encapsulation benefit does not require generation.** A handwritten `NotifierProvider` offers it too.

### 5.1 Mutation authority

`StateProvider` intentionally exposes a public setter. Every caller can bypass domain validation. This is acceptable for some simple state, but gets expensive when transitions acquire rules, logging, persistence coordination, permission checks, or asynchronous work.

A notifier lets callers express commands, not arbitrary state replacement. Its protected state is an API/tooling boundary, not a security sandbox; Dart's analyzer and your API discipline matter.

Conversely, creating a notifier class with a single unrestricted `setValue` method solely to reproduce a state cell adds ceremony with little immediate semantic gain. The architectural value emerges when the command boundary is useful.

### 5.2 Controller lifetime differs

The `StateProvider` element creates a new `StateController(initialState)` when its factory rebuilds and disposes the old controller during cleanup. A modern notifier's instance survives dependency rebuilds.

This is tested, and matters if callers retain references to controllers/notifiers or attach controller-level listeners. Changing `StateProvider` to a notifier is not merely deleting `.state =` from call sites.

### 5.3 Notification equality needs a layered explanation

Modern `Notifier` and generated notifier state notification defaults to `previous != next` in this Riverpod 3 checkout. `Provider` similarly compares exposed values with equality. Either modern notifier style can override `updateShouldNotify`.

For `StateProvider`, there are **two layers**:

1. `StateController` inherits the `state_notifier` notification mechanism, which filters identical assignments by default.
2. The Riverpod state-provider element applies its own exposed-state equality filtering.

The probe assigns a nonidentical but equal object: a direct controller listener fires, while the Riverpod provider listener does not. “StateProvider uses identity, so the UI always rebuilds for equal objects” is therefore too simplistic here.

Do not generalize this to every legacy adapter: `StateNotifierProvider` has explicit forwarding to the wrapped notifier's `updateShouldNotify` implementation.

### 5.4 Neither generation nor a notifier makes mutable collections reactive

Mutating a list in place does not create a reliable observable state transition. The same reference often compares equal to itself, and both `select` and downstream notification filters can suppress updates. Prefer immutable replacement or a deliberately designed notification policy.

Likewise, `Provider<MyService>` may expose a mutable service, but calling `service.changeSomething()` does not notify Riverpod unless the service/provider relationship explicitly implements that observation. Our service-field probe verifies this lack of automatic observation.

### 5.5 Legacy status is distinct from declaration style

In this checkout, `StateProvider`, `StateNotifierProvider`, and Flutter's `ChangeNotifierProvider` are legacy exports. Handwritten `Provider`, `NotifierProvider`, `AsyncNotifierProvider`, and `StreamNotifierProvider` are not made legacy by lacking annotations.

For new state-management code, consider modern notifiers first. For a small existing state cell or a library already built around `StateNotifier`/`ChangeNotifier`, compatibility and migration cost can justify keeping the adapter. Generation does not supply a one-annotation drop-in replacement for those adapters.

Sources: [StateProvider][state-provider], [StateController][state-controller], [StateNotifierProvider][state-notifier-provider], [AnyNotifier][class-core].

---

## 6. Families: ergonomic advantage with real identity rules

### 6.1 Manual families are not limited to one *piece of information*

They take one argument, which may be a record or immutable value object:

```dart
final resultProvider = Provider.autoDispose
    .family<int, (int, {String locale})>(
      (ref, args) => args.$1 + args.locale.length,
    );

// Consumer:
ref.watch(resultProvider((7, locale: 'en')));
```

The generated version can express the public API directly:

```dart
@riverpod
int result(Ref ref, int id, {String locale = 'en'}) {
  return id + locale.length;
}

// Consumer:
ref.watch(resultProvider(7));
ref.watch(resultProvider(7, locale: 'fr'));
```

Generation saves parameter plumbing, destructuring, defaults, named-call ergonomics, and for classes, argument accessors. It does **not** create a new runtime capability to key a cache by multiple values. Records already provide that for manual families.

A manually written wrapper function can also offer named/default parameters while calling a stable underlying family. Be aware that provider-analysis tools may not recognize arbitrary wrappers as well as direct family invocations. Do not accidentally construct a fresh independent provider each time the wrapper is called.

### 6.2 What generated keys contain

Here, generated providers use:

- The argument itself for one parameter.
- A Dart record for multiple parameters.
- Additional runtime-type discrimination for generated generic provider instantiations.

Named/default arguments are resolved by the generated call signature before storage. Thus `resultProvider(7)` and `resultProvider(7, locale: 'en')` compare equal.

Family calls can return **distinct descriptor objects that compare equal**, and the container shares the associated state. `identical(a, b)` is not the correct family-cache identity test.

Manual family child equality includes the family origin and argument; unrelated manually constructed families do not collide merely because arguments match. Generated equality uses its declaration-specific generated provider type plus arguments; generic types additionally compare runtime types.

### 6.3 No deep collection equality is manufactured

These are different keys with ordinary mutable lists:

```dart
generatedListFamilyProvider([1]);
generatedListFamilyProvider([1]);
```

Records do not recursively transform identity-based collections into value-based collections. A record containing two fresh lists retains the lists' equality semantics.

Rules for both styles:

- Use stable, immutable cache keys.
- If overriding `==`, implement a compatible and stable `hashCode`.
- Do not mutate equality-relevant key fields while the key is used in the container.
- Normalize equivalent input before selecting the family key if you want it to share state.
- A class name such as `Query` does not prove that it has safe value equality.

The generated-list and record probes verify this behavior. Lints can flag some obvious mistakes; they cannot prove all runtime key properties.

### 6.4 Class-family argument plumbing differs

In manual Riverpod 3 notifier families, use constructor fields:

```dart
class UserController extends Notifier<int> {
  UserController(this.id);
  final int id;

  @override
  int build() => id;
}

final userProvider = NotifierProvider.autoDispose
    .family<UserController, int, int>(UserController.new);
```

For generated notifiers, put family parameters on `build`. The generated base obtains the provider argument through `ref` and exposes accessors such as `id`. They are not ordinary user-constructor injection; do not try to read them before notifier attachment.

Avoid copying Riverpod 2 examples requiring `FamilyNotifier`, `AutoDisposeNotifier`, or provider-specific ref subclasses into this version. The current manual bases are unified; auto-dispose is provider configuration.

### 6.5 Generic generated families are a substantive convenience

This checkout supports declarations such as:

```dart
@riverpod
Type token<T>(Ref ref) => T;
```

`tokenProvider<int>()` and `tokenProvider<num>()` are different keys, even without value arguments. Generic classes and bounded generics are also represented in existing integration fixtures.

Ordinary handwritten families have fixed provider/state type parameters at the family declaration. A generic function that constructs a new provider on each call does not automatically implement a stable type-indexed family. Reproducing a strongly typed generic family without generation requires a deliberately designed cache/abstraction; it is not just passing `Type` and assuming all output typing follows.

Source: [family core][family-core], [family template][family-template], [provider template][provider-template], [notifier template][notifier-template], [existing generic fixtures][sync-fixture].

---

## 7. Hot reload: useful, but precisely bounded

### 7.1 Mechanism

The generated provider overrides `debugGetCreateSourceHash()`. The generator hashes the annotated declaration's `node.toSource()` with SHA-1.

The live element remembers its prior hash. During debug reassembly:

```text
read current hash
if current hash != previously remembered hash:
    invalidateSelf(asReload: false, manual: false)
```

Flutter's provider-scope integration calls `container.debugReassemble()` in debug mode. Manual providers' `LegacyProviderMixin` returns null, so they do not opt into this declaration-change detector.

The hash is a **development invalidation token**, not a production cache key, state serialization fingerprint, or security boundary.

### 7.2 What this buys you

Changing an annotated declaration, regenerating its output, and reloading can cause its live provider to rebuild without restarting the application. Unrelated provider elements are not all forcibly reset, though reactive dependents can legitimately recompute.

By contrast, hot reload may update a handwritten callback/method's executable code without reevaluating its already cached provider state. A subsequent explicit invalidation, dependency change, or fresh mount can use the updated implementation.

Handwritten notifiers are not immune to ordinary Dart hot reload: changing an action method can affect subsequent calls. The missing feature is automatic **provider initialization invalidation based on a generated declaration hash**.

### 7.3 What “stateful hot reload” does not promise

- It does not preserve the edited provider's old exposed state. Its build can run again and return the initial value.
- It does not snapshot and reconcile all private fields, resources, and dependencies.
- A notifier's object may survive the rebuild even as state and build cleanup change.
- It does not hash the transitive source of every helper/service that a declaration calls.
- Without the generator/watch step producing updated output, the hash remains stale.
- Dart VM reload restrictions still apply; some signature/type/initialization changes require restart.
- Changes to top-level initialized provider metadata should not be assumed to take effect merely because a build body reloads. Restart when validating changes to lifetime, dependencies, or provider shape.

The hash covers the **whole annotated class declaration**, not merely `build`. Changing a command method can therefore change the declaration hash and cause build invalidation too. Editing an external helper without changing the annotated declaration does not necessarily change this hash.

### 7.4 What was tested

The new reassembly probe uses an internal provider matching generated structure with a controllable source hash. It verifies:

1. Reassembly with an unchanged hash retains cached state.
2. Changing the hash causes recomputation.
3. A bare provider remains cached through that reassembly.
4. Explicit invalidation recomputes the bare provider.

This is a test of the Riverpod mechanism, **not** evidence that every IDE/build-runner/Flutter hot-reload sequence works identically. One older repository test for changing hashes is skipped; this study does not count that skipped test as passing evidence.

Sources: [hash computation][provider-parser], [hash template][hash-template], [element][element], [manual provider mixin][provider-core], [Flutter scope][flutter-scope].

---

## 8. Scoping and `dependencies`: more than documentation

### 8.1 Two different dependency graphs

`ref.watch(otherProvider)` creates a **runtime reactive edge**: changes can cause recomputation.

`dependencies: [...]` supplies **static scoping metadata**: it helps the container determine where an element belongs when providers are overridden in nested scopes. It is not a replacement for `watch`, not an eager initialization order, and not a hand-maintained list of every normal root dependency.

`ref.read` can also be relevant to scoping correctness even though it does not establish the same reactive edge.

### 8.2 Null versus empty is meaningful

For both styles:

- `dependencies: null` means no opt-in to scoped-dependency metadata.
- `dependencies: []` marks a provider as potentially scoped without scoped dependencies of its own.
- A dependent provider must account for the relevant scoped providers it uses.

Root-level test overrides do not generally require annotating every provider as scoped. The important distinction is overrides in nested scope graphs and the propagation of ownership/dependency metadata.

With manual declarations, the runtime computes transitive dependencies from the supplied provider objects. With generated declarations, the generator emits direct/transitive metadata (and in this version chooses a small list versus a set based on the transitive count).

This reduces mechanical bookkeeping; it does **not** mean the generator infers a perfect dependency list by analyzing arbitrary application execution. You still express the scoped contract.

### 8.3 A meaningful interoperability limit

Manual syntax refers to **provider objects**:

```dart
final dependentProvider = Provider<int>(
  (ref) => ref.watch(generatedScopedProvider) * 3,
  dependencies: [generatedScopedProvider],
);
```

Generated annotation syntax refers to **annotated functions/classes**, not the generated provider variables:

```dart
@Riverpod(dependencies: [currentUser])
String greeting(Ref ref) => ref.watch(currentUserProvider);
```

The annotation parser accepts annotated declarations. It does not offer a general `dependencies: [someHandwrittenProvider]` bridge. A handwritten provider variable is also normally not a const annotation argument.

Therefore:

- Ordinary generated/manual providers can read/watch one another.
- Generated providers can consume unscoped manual root providers; our notifier probes do this.
- Manual consumers can correctly declare generated scoped providers as dependencies; our nested-container probe does this.
- A generated consumer of a **manually scoped dependency** cannot simply list that manual provider in the annotation using the same syntax as a manual constructor.

**Architecture implication:** mix styles deliberately around scoped subgraphs. Convert a scoped dependency to an annotated declaration where appropriate, or keep the consumers requiring that metadata handwritten. Do not hide the problem by omitting dependencies or inserting a wrapper with an empty list; that does not magically reproduce the missing transitive scoping contract.

### 8.4 Tooling advantage, not a proof system

The generated form supports annotation-aware dependency and scope diagnostics. The actual rules and supported patterns live in the lint/parser implementation; dynamic indirection and arbitrary helper abstractions can exceed their analysis.

An annotated class with an abstract `build` declaration is another generated convenience here: the generated base supplies a `MissingScopeException` implementation and marks the provider scoped. Manual code can represent an analogous must-override dependency with an explicit throwing factory/build and dependency metadata, but does not get that exact shorthand automatically.

Sources: [annotation documentation][annotation], [dependency parser][dependency-parser], [generator metadata computation][generator], [scope tests][scope-tests], [dependency tests][dependency-tests].

---

## 9. Testing and overrides: largely shared, not byte-for-byte identical

### 9.1 Both are first-class testable APIs

Both styles support isolated `ProviderContainer`s, dependency overrides, subscriptions, `.future`, invalidation, and controlled teardown. `ProviderContainer.test()` registers disposal with the test framework in this version.

A practical pattern:

1. Override external I/O/services at the appropriate boundary.
2. Listen to auto-disposed state while exercising it.
3. Invoke commands through `.notifier`.
4. Assert exposed state/transitions, not generated implementation names.
5. Close subscriptions/dispose the container and verify lifecycle-sensitive effects.

Do not directly call a notifier's `build` as if it were an independent pure object method when it relies on Riverpod attachment. Extract pure business logic if that is the unit you want to test in isolation.

### 9.2 Override the part you intend to replace

For modern class providers in both styles:

- `overrideWith(...)` replaces notifier creation.
- `overrideWithBuild((ref, notifier) => ...)` replaces initialization while preserving the notifier's command methods and attachment.

Our probes initialize both counters at 7 with `overrideWithBuild`, call `increment`, and observe 8.

Returning a fresh fake/subclass can be appropriate, but do not reuse one notifier instance across multiple provider elements/containers. The runtime rejects already-associated notifiers.

Generated inheritance changes mock/fake design: extend the relevant notifier or generated base in a compatible library arrangement, and do not assume that implementing a public interface supplies the framework's internal attachment state. Service/repository fakes usually require less coupling than mocking notifier internals.

### 9.3 A concrete asymmetry in this checkout

The generator emits `overrideWithValue(T)` for synchronous generated providers, **including synchronous generated notifier providers**. The public manual `NotifierProvider` does not have that method in this checkout.

However, the generated method replaces the provider with `$SyncValueProvider<T>`:

```text
read generatedCounterProvider -> overridden integer, works
read generatedCounterProvider.notifier -> TypeError in the tested version
```

It is a **state-only substitution**, not “a counter initialized to this value.” Use it only when the consuming test/UI needs state and will not call notifier commands. Prefer `overrideWithBuild` when preserving commands matters. The exception is an observed implementation detail, not an API to depend on.

This is a useful correction to the claim “generation only changes spelling and all methods are identical.” Core runtime parity does not imply an identical public surface.

### 9.4 Family overrides need their actual signatures

An override of one family child is not an override of the whole family. Generated multi-argument functional family overrides in this version accept the packed argument record in their family override callback; do not assume the original named parameter list is repeated there.

Manual class families have argument-aware `overrideWith2`; their older zero-argument family `overrideWith` is deprecated here. Generated generic families have additional generated override adapters to capture their type parameters. Inspect the actual generated/API signature rather than copying a Riverpod 2 testing recipe.

Sources: [class override core][class-core], [family override core][family-core], [provider template][provider-template], [family template][family-template], [value override implementation][value-override].

---

## 10. Async behavior: not an annotation-exclusive benefit

Loading/error/data representation, stream subscription handling, `.future`, dependency tracking, and provider initialization retry are properties of the selected runtime provider kind.

A handwritten `FutureProvider` has asynchronous state handling; a handwritten `AsyncNotifierProvider` has both asynchronous initialization and a command API. Generation selects and wires those same mechanisms from the return type.

### 10.1 Commands are ordinary methods

Annotating a notifier does not automatically:

- Turn exceptions in every public method into provider `AsyncError` state.
- Set loading state around every request.
- Serialize commands.
- Roll back optimistic state.
- Retry a command that failed.
- Prevent the older of two concurrent requests from overwriting newer results.
- Cancel underlying HTTP/database work when state is disposed.

Use explicit command implementation, `AsyncValue.guard` where appropriate, operation tokens/serialization, cancellation APIs, and/or the separate mutation facilities according to the desired semantics. Initialization retry is not a universal command retry engine.

### 10.2 Cancellation and stale operations remain application responsibilities

The common async-provider machinery handles delivery/lifecycle of build futures/streams. It cannot automatically abort arbitrary transport work. Register cancellation/cleanup where the transport supports it.

Across asynchronous gaps, remember that a notifier can survive a rebuild. In this implementation its `ref` getter resolves the element's current ref, while each build epoch has its own `Ref`. Checking the newly obtained `ref.mounted` is not the same as checking that the original operation's build epoch is still valid.

Where that distinction matters, capture the initiating ref/token before the asynchronous operation and validate that original epoch before committing its result. An epoch check still does not solve overlapping commands within the same epoch; that needs its own concurrency policy.

### 10.3 Return-type inference is a maintenance tradeoff

Generation reduces duplicated generic declarations. Changing `T` to `Future<T>` changes the generated provider category and consumer state shape. That can be convenient, but it is a substantive API migration, not an innocuous implementation detail.

Manual code forces you to change the provider constructor/type explicitly. This is more verbose but can make the semantic change more conspicuous in code review. In either style, review downstream loading/error handling and `.future` use.

### 10.4 Retry documentation has drifted

The annotation's retry comment describes unlimited retries of all failures. The executable implementation of `ProviderContainer.defaultRetry` in this checkout instead defaults to **10 retries**, excludes `ProviderException` and `Error`, and exponentially increases the delay from 200 ms up to 6.4 seconds.

The runtime resolves retry from provider override/configuration, then container policy, then the default. Both handwritten constructor `retry:` and annotation `retry:` feed that mechanism. This discrepancy is why this report prioritizes source and tests over isolated doc comments.

Sources: [async notifier implementation][async-notifier], [future handling][future-modifier], [Ref lifecycle][ref], [retry implementation][container], [retry tests][retry-tests].

---

## 11. Constructors, composition, inheritance, and public API design

### 11.1 A manual factory has more construction freedom

Handwritten notifier declarations accept a factory. You can select a subtype or construct a notifier with explicit dependencies/arguments captured by the factory, within the provider's required notifier type.

That does not grant reactive dependency tracking to constructor parameters. If the dependency must change reactively, arrange the relevant `ref.watch` in the appropriate build path; do not accidentally freeze a captured service or configuration.

Generated notifier factories emit `MyNotifier()`. The class must have an unnamed constructor callable without required arguments. Optional constructor parameters are possible, but normal generated creation uses their defaults, not arbitrary application injection. Family inputs belong on `build`; test-specific factories can supply constructor options through overrides where appropriate.

The existing generator error tests specifically cover missing/default constructors and required constructor parameters.

### 11.2 Generated inheritance is more prescribed

An annotated class extends `_$ItsName`. With Dart's single class inheritance, this constrains custom superclass designs. Manual notifiers still need a Riverpod-compatible superclass, but can reuse ordinary intermediate subclasses more directly.

Prefer composition and well-targeted `AnyNotifier` mixins where that matches the problem. Do not bind a reusable business-domain model to an app-specific generated private base merely to save a provider declaration.

### 11.3 Reusing implementation is easier to express manually

You can attach a reusable manual notifier class to multiple independent provider declarations, creating a fresh instance per element. This can be attractive for libraries and generic building blocks.

Generated declarations tend to couple a domain declaration to a specific generated provider identity/family. Reusing behavior is still possible through mixins/composition, but the declaration is not simply an interchangeable instance of the public manual `Notifier` class.

### 11.4 Functions are often the right generated form

Do not turn a service provider or pure derivation into a class merely because “the recommended API uses annotations.” Generated functions offer the same generation tooling without adding a notifier object and command surface.

A function provider can perform initialization I/O and return a service with methods. The meaningful distinction is that it does not expose **Riverpod notifier-owned mutable state via `.notifier`**, not that functions are forbidden to have side effects anywhere.

Returning a `Notifier`/`StateNotifier`/`ChangeNotifier` from an annotated function does not automatically transform the function into the appropriate listening adapter. `Raw` can silence/express the intended raw value treatment, but does not magically attach a Riverpod notifier or subscribe/dispose a returned change notifier. Own those resources explicitly, or use the proper adapter.

Sources: [notifier template][notifier-template], [generator error tests][generator-errors], [unsupported-value lint][unsupported-lint], [annotation Raw contract][annotation].

---

## 12. Tooling, observability, and lint coverage

### 12.1 Names and source mapping

Generation gives providers names derived from declarations (or configured names), declaration-specific types, `@ProviderFor` links for analysis, and reload hashes. Manual providers can and often should specify `name:`.

For a manual named provider, observers/traces still know which provider changed. Lack of generation does not remove `ProviderObserver`, container inspection, or the runtime dependency graph.

In this fork, `ProviderTrace` receives the origin provider and emits its `toString()`, so manual names are especially useful for filtered diagnostics. Trace instrumentation is shared runtime behavior, not a feature unlocked by annotations.

This fork's DevTools observer is separately opt-in because timeline events can retain elements/values. `debugTrackProviderCreation` is another optional, debug-only source-navigation aid. A provider name is not the same thing as a captured creation stack. Do not infer app memory behavior or source-navigation availability solely from whether generation is enabled.

### 12.2 Lints are a separate tool installation

An annotation alone does not run every Riverpod lint. Configure and run the matching tooling in development and CI.

The lint implementation in this checkout uses `analysis_server_plugin` integration and `dart analyze`; older online advice about `custom_lint` commands may not match this branch.

Some rules understand both styles (for example, the parameter rule analyzes recognized family invocations, and notifier-property rules use notifier type information). Others are inherently annotation-oriented, including generated declaration shape and scoped dependency contracts.

A particularly relevant rule here is named `only_use_keep_alive_inside_keep_alive`. It warns about a generated retained provider depending on a generated auto-dispose provider. It is not a general compiler-enforced lifetime separation in Riverpod 3, and its analysis is not equivalent for every handwritten/wrapped declaration.

Avoid broad claims such as “manual Riverpod has no lints,” “generation guarantees safe families,” or “analyzer success proves scoping is correct.”

### 12.3 Debugging cost moves, rather than disappears

Generated code removes authoring boilerplate but adds another artifact to inspect. Stack traces/navigation may lead into generated bases/adapters. Manual code is more explicit and has fewer layers of source indirection, but its repetitive plumbing can itself hide mistakes.

Source: [lint README][lint-readme], [lint implementations][lint-dir], [fork trace][trace], [fork DevTools][devtool].

---

## 13. Performance: decompose the question before benchmarking

There is no evidence here for a blanket “generated providers are faster” or “manual providers are faster.” The important costs are different categories.

### 13.1 Steady-state reactive operations

Matching manual/generated provider kinds share the element/container/subscription machinery. Watching, reading cached state, notifying, selecting, scheduling, and disposing are not fundamentally reimplemented by the annotation layer.

Differences in factories, call adapters, metadata layout, and generated specialized types can affect compiled code, but source resemblance is not a quantitative performance result. The Dart compiler can inline or otherwise transform these paths.

### 13.2 Provider creation and family lookup

Manual family calls construct a provider with an argument-capturing factory. Generated family calls construct their specialized provider with an argument/record and a generated adapter. Generated generic keys add type-aware equality/hashing.

Do not infer from this that one allocates zero objects or is always cheaper. Both can create transient descriptors on repeated calls while still sharing one cached element for equal keys. Measure construction and lookup separately from network/build cost if they are actually hot.

### 13.3 Semantic differences usually dominate

A changed auto-dispose policy can cause more refetches, reconnects, and initialization than any factory-call overhead.

A poor family key can create new elements indefinitely. A heavy equality operator can dominate state notification. Watching too broad a state can rebuild expensive widgets. Eager work, retained family working sets, and unbounded diagnostics can overwhelm small differences in declaration form.

Switching a `Provider<T>` to a notifier adds a notifier object/command mechanism because the **state model changed**, not because code generation intrinsically requires it. Generated function providers remain function providers.

### 13.4 Build cost and shipped cost are different

- `build_runner`, the generator, and analyzer dependencies add development/CI work.
- Generated Dart participates in analysis/compilation and can increase source/artifact volume.
- The builder itself is not an annotation interpreter shipped to execute at runtime.
- Tree shaking and compilation determine what metadata/helpers survive into a particular application build.
- Debug hash/reassembly overhead should not be used to predict release performance.

A `.g.dart` line count does not establish AOT size or runtime memory usage.

### 13.5 A meaningful experiment design

If performance is deciding the choice, compare matched variants in the target app/platform:

1. Same provider kind, dependency graph, state equality, arguments, lifetime, and listeners.
2. Cold creation separately from warm read/family lookup/update.
3. Notifier command workload separately from initialization.
4. Mounted/paused/unmounted consumers and nested scopes represented realistically.
5. Debug diagnostics disabled for release conclusions; Flutter profile/release behavior measured appropriately.
6. Allocations, retained heap after disposal, rebuild counts, frame time, and final binary size—not only a tight-loop wall clock.
7. Cold build, warm incremental build, regeneration latency, and IDE analysis measured separately.

This report intentionally provides no invented percentages from an unrepresentative microbenchmark.

---

## 14. Build-system and maintenance tradeoffs

### Handwritten advantages

- Edit/analyze/run without a Riverpod builder dependency.
- Fewer generated artifacts, version constraints, missing-part errors, and generation-order concerns.
- A smaller direct API surface to understand in reusable packages.
- Explicit review of provider kind, lifetime, generic types, and factories.
- Easier one-file examples and experiments.

### Generated advantages

- Less repetitive type/parameter/family plumbing.
- Generated naming and declaration mapping are consistent.
- A standardized pattern across large codebases.
- Provider-aware reload invalidation.
- Scope/dependency tooling and some experimental convenience generators.

### Generated costs that remain even if another builder already exists

An existing Freezed/JSON pipeline lowers adoption cost; it does not make another builder free. There is still incremental work, dependency compatibility, generated review volume, and a watch process to keep healthy.

The generator, annotation package, and runtime cooperate through internal `$` APIs. Upgrade them as a compatible set and regenerate. This checkout itself uses different version numbers for runtime, annotations, and generator; “make all versions identical” is not the compatibility rule.

If generated files are checked in, define how CI checks reproducibility and how merges/renames remove obsolete output. If they are not checked in, generation is a prerequisite before analysis/test/build and must work from a clean checkout. Avoid committing a declaration change with stale generated family signatures/hash/metadata.

For a published library that ships its generated Dart, downstream consumers do not need to rerun that library's generator simply to use its providers. The author owns generation/reproducibility; the consumer still needs compatible runtime dependencies. Avoid leaking generated concrete types into public APIs without considering the nominal-type and migration consequences.

Formatting/style failures, generation failures, Dart type failures, and runtime semantic failures are different categories. A stale file can still compile while carrying outdated reload metadata; some other stale edits fail loudly. Do not rely on compile errors to catch every stale output.

The checked-in [code-generation guide][codegen-guide] currently recommends adopting generation mainly when the project already uses it, explicitly discussing builder cost and cancelled Dart macros. That is practical guidance, not a limitation of handwritten Riverpod. Do not base a migration business case on promised macro performance that is absent from this checkout.

---

## 15. Experimental features: what generation adds, and what it does not

### Offline persistence

The runtime persistence facilities are available to notifiers without code generation. Manual notifiers can provide storage, keys, encoding/decoding, and options explicitly.

`@JsonPersist()` adds generated convenience: a key and JSON-specific persistence method/codec glue, layered over the underlying runtime persistence extension. A plain `@riverpod` annotation does not automatically persist anything. The notifier still participates in the persistence protocol and calls the relevant operation.

Generated persistence keys are an application data-compatibility concern. Review key identity across declaration renames and family-argument changes; do not treat generated names as permanent storage schemas by accident. A stable explicitly chosen key/schema can be preferable for long-lived persisted data.

### Mutations

The separate experimental mutation API is not a reason by itself to annotate every state provider. Its transactions/lifetime coordination are runtime facilities. Generation does not wrap ordinary notifier methods in mutation behavior automatically.

These APIs are explicitly experimental in this checkout. Their additional conveniences may influence a local choice, but should not be presented as permanent incompatibilities of manual Riverpod.

Sources: [JSON annotation][json-annotation], [JSON generator][json-generator], [runtime persistence][persist], [mutation API][mutations], [offline integration fixture][offline-fixture].

---

## 16. Recommended decisions by use case

| Situation | Sensible starting point | Reason/caveat |
|---|---|---|
| No existing builders; a handful of services/derived values | Handwritten `Provider` / async function providers | Minimal infrastructure; full runtime semantics |
| No builders; substantial command-driven state | Handwritten `NotifierProvider` / `AsyncNotifierProvider` | Modern notifier design does not require annotations |
| Existing builder workflow; many application state declarations | Generated functions and classes as appropriate | Family ergonomics and consistent metadata can repay marginal cost |
| Many named/default/generic family APIs | Strong case for generation | Saves significant public API/key plumbing; equality still your responsibility |
| A pure derivation with no command API | Function provider, in either style | No reason to add a notifier just for the annotation |
| Reusable package with framework-neutral domain logic | Domain/service objects plus a thin manual or generated adapter | Keep domain logic independent of generated private bases |
| Reusable notifier factory/subclass hierarchy | Often manual | Greater construction/inheritance flexibility |
| Simple existing `StateProvider` with stable requirements | Retain or migrate deliberately | Legacy status is relevant, but no need to pretend a spelling change is semantic equivalence |
| Existing `StateNotifier`/`ChangeNotifier` integration | Appropriate manual legacy adapter initially | Annotated function return is not the same observation/disposal adapter |
| Scoped overrides across a mixed-style graph | Design the metadata boundary first | Generated dependency annotations cannot simply list handwritten scoped providers |
| Fast edit/reload of provider build logic is important | Strong case for generation | Requires fresh generated hashes and has the reload limits described above |
| Performance problem | Measure actual lifetime/key/subscription behavior first | Annotation status alone is a weak causal hypothesis |

**A sustainable hybrid policy:** choose one default style for ordinary app code, document exceptions, and require explicit review of lifetime and scoped dependencies at boundaries. A manual service leaf consumed by generated state is not inherently suspicious. A mixed scoped graph deserves more care than that simple pattern.

---

## 17. Migration checklist: preserve behavior before changing design

### Handwritten to generated

1. Map the original provider kind to a function or class with the matching return semantics.
2. Preserve `autoDispose`: ordinary retained manual providers usually need `@Riverpod(keepAlive: true)`.
3. Carry over `retry`, naming expectations, and scoped-dependency contracts.
4. Move manual family constructor arguments into generated `build` parameters as appropriate.
5. Preserve cache-key equivalence; defaults and parameter packing can change call/API shape.
6. Audit helpers/mixins/tests bound to `Provider<T>`, `Notifier<T>`, or other concrete manual classes.
7. Audit constructor injection; normal generated creation calls the zero-required-argument unnamed constructor.
8. Keep public provider names stable where downstream code/logging relies on them.
9. Revisit family override callback signatures and state-only overrides.
10. Generate, analyze, and test mounting/unmounting, invalidation, dependency rebuild, root overrides, and nested scopes.
11. Review persistence keys separately if enabled.
12. Validate app reload behavior; use a clean restart for lifetime/metadata changes.

### Generated to handwritten

1. Select the same provider kind from the annotated return type, including `Raw` intent.
2. Add `.autoDispose`/`isAutoDispose: true` unless the annotation deliberately retained state.
3. Replace the generated base with the correct public notifier base and explicit `build` signature.
4. Introduce constructor fields for family inputs; use a record/value object with stable equality for multiple inputs.
5. Reproduce scoped dependency lists using actual provider objects.
6. Preserve retry/names and test override intent, not merely method spelling.
7. Replace generated generic-family behavior deliberately; a fresh generic provider factory is not an equivalent cache.
8. Accept the loss of source-hash reload invalidation and adjust the development workflow.
9. Update tests/helpers that used generated-specific types or conveniences.
10. Remove obsolete generated declarations/artifacts only after their consumers are migrated.

### `StateProvider` to either notifier style

Treat this as a **state-model migration** in addition to any declaration migration:

- Replace public setter sites with an intentional command API.
- Check retained references/direct controller listeners.
- Test watched-dependency resets and controller/notifier identity expectations.
- Review equality, mutable state, disposal, and lifetime defaults.
- Do not preserve accidental unrestricted setters unless that remains the desired API.

---

## 18. Common claims, corrected

| Claim | More accurate statement for this checkout |
|---|---|
| “Annotations are required for modern Riverpod.” | Modern handwritten notifiers/providers are supported. |
| “Codegen is purely cosmetic.” | It shares the engine but changes defaults, nominal types, metadata/reload behavior, family ergonomics, and some surface APIs. |
| “A generated class is equivalent to a bare Provider.” | It is a notifier-backed state model; a generated function is the closer `Provider` equivalent. |
| “Only generated providers handle loading/errors.” | Appropriate manual async providers do too. |
| “Generated notifiers extend `Notifier<T>`.” | Not in this version: both extend a shared internal base through different branches. |
| “All providers keep state unless you add autoDispose.” | Generated providers auto-dispose by default. |
| “keepAlive prevents rebuilds.” | It changes retention, not reactive invalidation. |
| “Stateful reload preserves the edited counter's current value.” | Hash change invalidates; build may reset its exposed state. |
| “Changing any helper triggers generated provider reload.” | The hash is declaration-local, not a transitive source dependency hash. |
| “A family can only take one value without codegen.” | One argument can be a record/value object; generated call syntax is more ergonomic. |
| “Codegen gives lists deep equality as keys.” | It does not. |
| “All manual providers have no static tooling.” | Some lints support both; some require annotated declaration information. |
| “A notifier value override leaves its methods available.” | The generated sync value-only override removes the class-provider element in the tested implementation. |
| “Offscreen equals disposed.” | Pausing subscriptions differs from removing them, and retention also depends on configuration. |
| “The annotation makes mutations safe/cancellable.” | Command concurrency, errors, cancellation, and invariants still need design. |
| “One style is obviously faster in production.” | No such conclusion follows without a matched representative measurement. |

---

## 19. Reproduction and evidence ledger

### New probes

[The test file][probes] contains these 18 tests (the manual/generated rebuild case is expanded into two tests):

| Probe | Established result |
|---|---|
| Default retention matrix | Manual retained, manual auto disposed, generated default disposed, generated retained/pinned retained |
| Paused strong subscriptions | Pause alone does not dispose; closing them permits disposal |
| Manual notifier rebuild/invalidation | Instance survives; build/state recomputed; new instance after actual disposal |
| Generated notifier rebuild/invalidation | Same lifecycle result |
| StateProvider dependency rebuild | Controller is replaced |
| Equal nonidentical modern notifier state | Both suppress ordinary provider notification |
| StateController versus provider filtering | Direct controller listener fires while provider listener is suppressed |
| Family defaults and records | Default normalization/equal keys share state; unrelated manual families differ |
| List family keys | No generated deep collection equality |
| Generic family keys | Type instantiations distinguish keys |
| Nominal types | Generated provider/notifier are not public manual concrete subtypes |
| Raw Future | Raw future versus `AsyncValue` exposure |
| Mixed-style nested scoping | Generated and manual consumers see the correctly scoped value |
| `overrideWithBuild` | Both retain command behavior |
| Generated notifier value-only override | State works, notifier access fails; manual class lacks the convenience |
| Metadata | Generated name/hash, manual explicit name and null hash |
| Service field mutation | Bare Provider does not observe arbitrary object mutation |
| Controlled-hash reassembly | Hash-driven invalidation versus bare cached state |

### Commands

From `packages/riverpod_generator`:

```sh
# The generated fixture is checked in, so ordinary testing needs no regeneration.
dart test test/provider_tradeoffs_test.dart --reporter expanded

dart analyze \
  test/provider_tradeoffs_test.dart \
  test/integration/provider_tradeoffs.dart

# Regenerate the fixture when its annotated declarations change.
dart run build_runner build \
  --build-filter='test/integration/provider_tradeoffs.g.dart'

# Focused wider run used for this report: 80 passing tests.
dart test \
  test/provider_tradeoffs_test.dart \
  test/sync_test.dart test/notifier_test.dart \
  test/async_test.dart test/async_notifier_test.dart \
  test/stream_test.dart test/stream_notifier_test.dart \
  test/auto_dispose_test.dart test/dependencies_test.dart \
  test/scoped_test.dart test/hash_test.dart test/retry_test.dart \
  test/offline_test.dart \
  --reporter expanded
```

Inspect `git status` after running builders. On this checkout's initial cached build state, the first filtered build removed unrelated tracked generated integration outputs; those were restored without changing their contents. That build-system side effect is not a provider behavior. Avoid treating an arbitrarily filtered build as guaranteed to leave every other generated artifact untouched.

Intentional probes use dynamic calls for absent APIs, explicit default arguments for normalization, and noncanonical equal objects. Local lint suppressions explain those cases; they are not recommended application coding conventions. The only custom `$`-internal provider is the hash simulation, isolated in the test file.

### Audit map

| Question | Primary implementation |
|---|---|
| Manual default and factory | [Provider][provider-impl], [manual Notifier][notifier-orphan] |
| Annotation default, dependencies, Raw | [Riverpod annotation][annotation] |
| Generated provider kind/API | [provider template][provider-template] |
| Generated base/argument accessors | [notifier template][notifier-template] |
| Generated family calls/overrides | [family template][family-template] |
| Declaration hashing/type selection | [analyzer provider model][provider-parser] |
| Manual identity/source hash | [provider base/mixin][provider-core] |
| Shared notifier creation/state/overrides | [class-provider core][class-core] |
| Rebuild/disposal/reassembly | [element][element], [scheduler][scheduler], [Ref][ref] |
| Legacy controller behavior | [state provider][state-provider], [state controller][state-controller] |
| Scoping parser/emission | [dependency parser][dependency-parser], [generator][generator] |
| Flutter reassembly | [provider scope][flutter-scope] |
| Fork diagnostics | [trace][trace], [DevTools][devtool] |
| Persistence generation | [JSON generator][json-generator] |

## Bottom line

**Choose state semantics first, lifetime/scope second, declaration style third.**

Handwritten modern providers give up conveniences—not Riverpod's core engine. Generated declarations buy real ergonomic and tooling advantages, but bring different defaults, nominal types, build-system obligations, and a few interoperability constraints. A good choice follows the application's API shapes and engineering workflow, not the belief that one spelling is inherently more “advanced.”

[probes]: ../../packages/riverpod_generator/test/provider_tradeoffs_test.dart
[fixture]: ../../packages/riverpod_generator/test/integration/provider_tradeoffs.dart
[output]: ../../packages/riverpod_generator/test/integration/provider_tradeoffs.g.dart
[annotation]: ../../packages/riverpod_annotation/lib/src/riverpod_annotation.dart
[provider-parser]: ../../packages/riverpod_analyzer_utils/lib/src/nodes/generated_providers/providers.dart
[dependency-parser]: ../../packages/riverpod_analyzer_utils/lib/src/nodes/dependencies.dart
[provider-template]: ../../packages/riverpod_generator/lib/src/templates/provider.dart
[notifier-template]: ../../packages/riverpod_generator/lib/src/templates/notifier.dart
[family-template]: ../../packages/riverpod_generator/lib/src/templates/family.dart
[hash-template]: ../../packages/riverpod_generator/lib/src/templates/hash.dart
[generator]: ../../packages/riverpod_generator/lib/src/riverpod_generator.dart
[provider-core]: ../../packages/riverpod/lib/src/core/provider/provider.dart
[class-core]: ../../packages/riverpod/lib/src/core/provider/notifier_provider.dart
[family-core]: ../../packages/riverpod/lib/src/core/family.dart
[provider-impl]: ../../packages/riverpod/lib/src/providers/provider.dart
[notifier-orphan]: ../../packages/riverpod/lib/src/providers/notifier/orphan.dart
[state-provider]: ../../packages/riverpod/lib/src/providers/legacy/state_provider.dart
[state-controller]: ../../packages/riverpod/lib/src/providers/legacy/state_controller.dart
[state-notifier-provider]: ../../packages/riverpod/lib/src/providers/legacy/state_notifier_provider.dart
[element]: ../../packages/riverpod/lib/src/core/element.dart
[scheduler]: ../../packages/riverpod/lib/src/core/scheduler.dart
[ref]: ../../packages/riverpod/lib/src/core/ref.dart
[container]: ../../packages/riverpod/lib/src/core/provider_container.dart
[flutter-scope]: ../../packages/flutter_riverpod/lib/src/core/provider_scope.dart
[sync-fixture]: ../../packages/riverpod_generator/test/integration/sync.dart
[scope-tests]: ../../packages/riverpod_generator/test/scoped_test.dart
[dependency-tests]: ../../packages/riverpod_generator/test/dependencies_test.dart
[value-override]: ../../packages/riverpod/lib/src/core/override_with_value.dart
[async-notifier]: ../../packages/riverpod/lib/src/providers/async_notifier.dart
[future-modifier]: ../../packages/riverpod/lib/src/core/modifiers/future.dart
[retry-tests]: ../../packages/riverpod_generator/test/retry_test.dart
[generator-errors]: ../../packages/riverpod_generator/test/error_test.dart
[unsupported-lint]: ../../packages/riverpod_lint/lib/src/lints/unsupported_provider_value.dart
[lint-readme]: ../../packages/riverpod_lint/README.md
[lint-dir]: ../../packages/riverpod_lint/lib/src/lints
[trace]: ../../packages/riverpod/lib/src/core/provider_trace.dart
[devtool]: ../../packages/riverpod/lib/src/core/devtool.dart
[codegen-guide]: ../../website/docs/concepts/about_code_generation.mdx
[json-annotation]: ../../packages/riverpod_annotation/lib/experimental/json_persist.dart
[json-generator]: ../../packages/riverpod_generator/lib/src/json_generator.dart
[persist]: ../../packages/riverpod/lib/experimental/persist.dart
[mutations]: ../../packages/riverpod/lib/experimental/mutation.dart
[offline-fixture]: ../../packages/riverpod_generator/test/integration/offline.dart
