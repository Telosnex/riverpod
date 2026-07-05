part of '../core.dart';

/// A function that can also listen to providers
///
/// See also [Consumer]
@internal
typedef ConsumerBuilder =
    Widget Function(BuildContext context, WidgetRef ref, Widget? child);

/// {@template riverpod.consumer}
/// Build a widget tree while listening to providers.
///
/// [Consumer]'s main use-case is for reducing the number of rebuilt widgets.
/// when a provider changes.
///
/// As an example, consider:
///
/// ```dart
/// @riverpod
/// Future<User> fetchUser(Ref ref) async {
///   // ...
/// }
/// ```
///
/// Normally, we would use a [ConsumerWidget] as followed:
///
/// ```dart
/// class Example extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return Scaffold(
///      appBar: AppBar(title: Text('User')),
///      body: switch (ref.watch(userProvider) {
///        AsyncValue(:final value?) => Text(value.name),
///        AsyncValue(hasError: true) => Text('Error'),
///        _ => CircularProgressIndicator(),
///      },
///   }
/// }
/// ```
///
/// However, this would rebuild the entire `Scaffold` when the user changes.
/// If we are looking to reduce this, have two options:
/// - Extract the `body` into a separate [ConsumerWidget]. Then only the `body` will rebuild.
///   This is the recommended approach, but is a bit more verbose.
/// - Use [Consumer] to only rebuild the `body` when the user changes.
///   This is less recommended, but avoids creating a new widget.
///
/// Using [Consumer], the resulting code would look like:
/// ```dart
/// class Example extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///      appBar: AppBar(title: Text('User')),
///      body: Consumer(
///        builder: (context, ref, child) {
///          return switch (ref.watch(userProvider) {
///            AsyncValue(:final value?) => Text(value.name),
///            AsyncValue(hasError: true) => Text('Error'),
///            _ => CircularProgressIndicator(),
///          };
///        }),
///      );
///   }
/// }
/// ```
///
/// ## Performance considerations
///
/// To optimize performance by avoiding unnecessary network requests and
/// pausing unused streams, [Consumer] will temporarily stop listening to
/// providers when the widget stops being visible.
///
/// This is determined using [TickerMode.of], and will invoke
/// [ProviderSubscription.pause] on all currently active subscriptions.
///
/// See also:
///
/// - [ConsumerWidget], a base-class for widgets that wants to listen to providers.
/// - [child], a way to optimize the widget tree by passing a child widget that
///   won't rebuild when the provider changes.
/// {@endtemplate}
/// {@category Core}
final class Consumer extends ConsumerWidget {
  /// {@macro riverpod.consumer}
  const Consumer({super.key, required this.builder, this.child});

  /// The builder that will be called when the provider is updated.
  ///
  /// The `child` parameter will be the same as [child] if specified, or null otherwise.
  ///
  /// **Note**
  /// You can watch as many providers inside [Consumer] as you want to:
  /// ```dart
  /// Consumer(
  ///   builder: (context, ref, child) {
  ///     final value = ref.watch(someProvider);
  ///     final another = ref.watch(anotherProvider);
  ///     ...
  ///   },
  /// );
  /// ```
  ///
  /// See also [child].
  final ConsumerBuilder builder;

  /// The [child] parameter is an optional parameter for the sole purpose of
  /// further performance optimizations.
  ///
  /// If your `builder` function contains a subtree that does not depend on the
  /// animation, it is more efficient to build that subtree once instead of
  /// rebuilding it on every provider update.
  ///
  /// If you pass the pre-built subtree as the `child` parameter, the
  /// Consumer will pass it back to your builder function so that you
  /// can incorporate it into your build.
  ///
  /// Using this pre-built child is entirely optional, but can improve
  /// performance significantly in some cases and is therefore a good practice.
  ///
  /// This sample shows how you could use a [Consumer]
  ///
  /// ```dart
  /// final counterProvider = NotifierProvider<Counter, int>(Counter.new);
  /// class Counter extends Notifier<int> {
  ///   @override
  ///   int build() => 0;
  ///
  ///   void increment() => state++;
  /// }
  ///
  /// class MyHomePage extends ConsumerWidget {
  ///   MyHomePage({Key? key, required this.title}) : super(key: key);
  ///   final String title;
  ///
  ///   @override
  ///   Widget build(BuildContext context, WidgetRef ref) {
  ///     return Scaffold(
  ///       appBar: AppBar(
  ///         title: Text(title)
  ///       ),
  ///       body: Center(
  ///         child: Column(
  ///           mainAxisAlignment: MainAxisAlignment.center,
  ///           children: <Widget>[
  ///             Text('You have pushed the button this many times:'),
  ///             Consumer(
  ///               builder: (BuildContext context, WidgetRef ref, Widget? child) {
  ///                 // This builder will only get called when the counterProvider
  ///                 // is updated.
  ///                 final count = ref.watch(counterProvider);
  ///
  ///                 return Row(
  ///                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  ///                   children: <Widget>[
  ///                     Text('$count'),
  ///                     child!,
  ///                   ],
  ///                 );
  ///               },
  ///               // The child parameter is most helpful if the child is
  ///               // expensive to build and does not depend on the value from
  ///               // the notifier.
  ///               child: Text('Good job!'),
  ///             )
  ///           ],
  ///         ),
  ///       ),
  ///       floatingActionButton: FloatingActionButton(
  ///         child: Icon(Icons.plus_one),
  ///         onPressed: () => ref.read(counterProvider.notifier).increment(),
  ///       ),
  ///     );
  ///   }
  /// }
  /// ```
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return builder(context, ref, child);
  }
}

/// {@template riverpod.consumer_widget}
/// The equivalent of a [StatelessWidget] that can listen to providers.
///
/// Using [ConsumerWidget], this allows the widget tree to listen to changes on
/// provider, so that the UI automatically updates when needed.
///
/// Do not modify any state or start any http request inside [build].
///
/// As a usage example, consider:
///
/// ```dart
/// final helloWorldProvider = Provider((_) => 'Hello world');
/// ```
///
/// We can then subclass [ConsumerWidget] to listen to `helloWorldProvider` like so:
///
/// ```dart
/// class Example extends ConsumerWidget {
///   const Example({Key? key}): super(key: key);
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final value = ref.watch(helloWorldProvider);
///     return Text(value); // Hello world
///   }
/// }
/// ```
///
/// **Note**
/// You can watch as many providers inside [build] as you want to:
///
/// ```dart
/// @override
/// Widget build(BuildContext context, WidgetRef ref) {
///   final value = ref.watch(someProvider);
///   final another = ref.watch(anotherProvider);
///   return Text(value); // Hello world
/// }
/// ```
///
/// See also:
/// - [ConsumerStatefulWidget], for a [StatefulWidget] variant.
/// - [Consumer], to help reducing the number of rebuilt widgets without making
///   a new widget.
/// {@endtemplate}
/// {@category Core}
abstract class ConsumerWidget extends ConsumerStatefulWidget {
  /// {@macro riverpod.consumer_widget}
  const ConsumerWidget({super.key});

  /// Describes the part of the user interface represented by this widget.
  ///
  /// The framework calls this method when this widget is inserted into the tree
  /// in a given [BuildContext] and when the dependencies of this widget change
  /// (e.g., an [InheritedWidget] referenced by this widget changes). This
  /// method can potentially be called in every frame and should not have any side
  /// effects beyond building a widget.
  ///
  /// The framework replaces the subtree below this widget with the widget
  /// returned by this method, either by updating the existing subtree or by
  /// removing the subtree and inflating a new subtree, depending on whether the
  /// widget returned by this method can update the root of the existing
  /// subtree, as determined by calling [Widget.canUpdate].
  ///
  /// Typically implementations return a newly created constellation of widgets
  /// that are configured with information from this widget's constructor and
  /// from the given [BuildContext].
  ///
  /// The given [BuildContext] contains information about the location in the
  /// tree at which this widget is being built. For example, the context
  /// provides the set of inherited widgets for this location in the tree. A
  /// given widget might be built with multiple different [BuildContext]
  /// arguments over time if the widget is moved around the tree or if the
  /// widget is inserted into the tree in multiple places at once.
  ///
  /// The implementation of this method must only depend on:
  ///
  /// * the fields of the widget, which themselves must not change over time,
  ///   and
  /// * any ambient state obtained from the `context` using
  ///   [BuildContext.dependOnInheritedWidgetOfExactType].
  ///
  /// If a widget's [build] method is to depend on anything else, use a
  /// [StatefulWidget] instead.
  ///
  /// See also:
  ///
  ///  * [StatelessWidget], which contains the discussion on performance considerations.
  Widget build(BuildContext context, WidgetRef ref);

  @override
  // ignore: library_private_types_in_public_api
  _ConsumerState createState() => _ConsumerState();
}

class _ConsumerState extends ConsumerState<ConsumerWidget> {
  @override
  Widget build(BuildContext context) => widget.build(context, ref);
}

/// {@template riverpod.consumer_stateful_widget}
/// A [StatefulWidget] that has a [State] capable of reading providers.
///
/// This is used exactly like a [StatefulWidget], but with a [State] that must
/// subclass [ConsumerState] :
///
/// ```dart
/// class MyConsumer extends ConsumerStatefulWidget {
///  const MyConsumer({Key? key}): super(key: key);
///
///   @override
///   ConsumerState<MyConsumer> createState() => _MyConsumerState();
/// }
///
/// class _MyConsumerState extends ConsumerState<MyConsumer> {
///   @override
///   void initState() {
///     // All State life-cycles can be used
///     super.initState();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     // "ref" is a property of ConsumerState and can be used to read providers
///     ref.watch(someProvider);
///   }
/// }
/// ```
/// {@endtemplate}
/// {@category Core}
abstract class ConsumerStatefulWidget extends StatefulWidget {
  /// {@macro riverpod.consumer_stateful_widget}
  const ConsumerStatefulWidget({super.key});

  @override
  ConsumerState createState();

  @override
  ConsumerStatefulElement createElement() => ConsumerStatefulElement(this);
}

/// The [State] for a [ConsumerStatefulWidget].
///
/// It has all the life-cycles if a normal [State], with the only difference
/// being that it has a [ref] property.
///
/// It must be used in conjunction with a [ConsumerStatefulWidget] :
///
/// ```dart
/// class MyConsumer extends ConsumerStatefulWidget {
///  const MyConsumer({Key? key}): super(key: key);
///
///   @override
///   ConsumerState<MyConsumer> createState() => _MyConsumerState();
/// }
///
/// class _MyConsumerState extends ConsumerState<MyConsumer> {
///   @override
///   void initState() {
///     // All State life-cycles can be used
///     super.initState();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     // "ref" is a property of ConsumerState and can be used to read providers
///     ref.watch(someProvider);
///   }
/// }
/// ```
/// {@category Core}
abstract class ConsumerState<WidgetT extends ConsumerStatefulWidget>
    extends State<WidgetT> {
  /// {@macro flutter_riverpod.widget_ref}
  late final ref = context as WidgetRef;
}

/// Multiplexes one TickerMode notifier to many [ConsumerStatefulElement]s.
///
/// Why: [ChangeNotifier.addListener]/[ChangeNotifier.removeListener] are
/// O(listeners) with closure-equality scans. Upstream riverpod registers one
/// `_updateTickerMode` tear-off per consumer element on the *shared*
/// per-route TickerMode notifier. With hundreds of consumer elements alive
/// under one route, a burst of unmounts (e.g. tiles crossing a scroll
/// view's cache extent) costs O(unmounted × alive) `_Closure.==` calls —
/// measured at ~3.6% of UI-thread CPU while scrolling a conversation in
/// telosnex (test-results/dart_devtools_2026-06-12_10_35_06.170.json).
///
/// The hub registers exactly ONE listener on the notifier and tracks its
/// elements in an identity [HashSet], making attach/detach O(1).
///
/// Lifecycle: hubs are stored in an [Expando] keyed by the notifier, so a
/// hub (and its single listener) lives exactly as long as its notifier and
/// is collected with it. The hub intentionally never removes its own
/// listener when it becomes empty: the notifier is owned by [TickerMode],
/// which disposes it wholesale, and staying attached avoids add/remove
/// thrash as elements come and go.
class _TickerModeHub {
  _TickerModeHub._(this._notifier) {
    _notifier.addListener(_onChanged);
  }

  factory _TickerModeHub.of(ValueListenable<bool> notifier) {
    return _hubs[notifier] ??= _TickerModeHub._(notifier);
  }

  static final Expando<_TickerModeHub> _hubs = Expando<_TickerModeHub>(
    '_TickerModeHub',
  );

  final ValueListenable<bool> _notifier;
  final HashSet<ConsumerStatefulElement> _elements =
      HashSet<ConsumerStatefulElement>.identity();

  void add(ConsumerStatefulElement element) => _elements.add(element);

  void remove(ConsumerStatefulElement element) => _elements.remove(element);

  void _onChanged() {
    // Iterate a copy: pausing/resuming subscriptions can synchronously
    // mark elements dirty, and a TickerMode flip is rare (route
    // transitions), so the allocation is irrelevant.
    for (final element in _elements.toList()) {
      try {
        element._updateTickerMode();
      } catch (exception, stack) {
        // Isolate elements from one another, matching upstream semantics:
        // upstream registers one listener per element and
        // ChangeNotifier.notifyListeners catches each listener's exceptions
        // individually. With the hub multiplexing every element behind a
        // single listener, an exception thrown by one element (e.g. a
        // provider rebuild triggered synchronously by resuming its
        // subscriptions) would otherwise skip all remaining elements --
        // leaving their subscriptions permanently paused while visible:
        // their widgets would show stale provider values until the *next*
        // full TickerMode off/on cycle on the same notifier, if any.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'flutter_riverpod',
            context: ErrorDescription(
              'while updating the TickerMode pause state of a Consumer',
            ),
          ),
        );
      }
    }
  }
}

/// The [Element] for a [ConsumerStatefulWidget]
@internal
base class ConsumerStatefulElement extends StatefulElement
    implements WidgetRef {
  /// The [Element] for a [ConsumerStatefulWidget]
  ConsumerStatefulElement(ConsumerStatefulWidget super.widget);

  @override
  BuildContext get context => this;

  @override
  late ProviderContainer container = ProviderScope.containerOf(
    this,
    listen: false,
  );
  var _dependencies =
      <ProviderListenable<Object?>, ProviderSubscription<Object?>>{};
  Map<ProviderListenable<Object?>, ProviderSubscription<Object?>>?
  _oldDependencies;
  final _listeners = <ProviderSubscription<Object?>>[];
  List<ProviderSubscription<Object?>>? _manualListeners;
  ValueListenable<bool>? _tickerModeNotifier;
  _TickerModeHub? _tickerModeHub;
  bool? _isActive;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    try {
      // Forcibly listen to the container, to guarantee that didChangeDependencies
      // is called when the container changes.
      ProviderScope.containerOf(this);
    } catch (e) {
      // Silence 'no scope' error. It is already reported by the container variable.
    }
  }

  @override
  void activate() {
    super.activate();
    _updateTickerModeNotifier();
  }

  void _applyTickerMode(ProviderSubscription sub) {
    if (_isActive == false) sub.pause();
  }

  void _updateTickerModeNotifier() {
    final newTickerModeNotifier = TickerMode.getNotifier(context);

    if (_tickerModeNotifier != newTickerModeNotifier) {
      // O(1) hub membership instead of per-element listeners on the shared
      // notifier; see _TickerModeHub.
      _tickerModeHub?.remove(this);
      _tickerModeHub = _TickerModeHub.of(newTickerModeNotifier)..add(this);
      _tickerModeNotifier = newTickerModeNotifier;
      _updateTickerMode();
    }
  }

  void _updateTickerMode() {
    final isActive = _tickerModeNotifier!.value;
    if (isActive != _isActive) {
      _isActive = isActive;
      for (final sub in _dependencies.values) {
        if (isActive) {
          sub.resume();
        } else {
          sub.pause();
        }
      }
    }
  }

  /// Diagnostic snapshot of this element's TickerMode pause wiring.
  ///
  /// Intended for app-level watchdogs that want to detect, in release
  /// builds, consumers whose subscriptions are stuck paused while their
  /// surrounding [TickerMode] is enabled (or vice versa).
  ///
  /// - `isActive` is the pause state this element last applied to its
  ///   subscriptions (null before the first build).
  /// - `notifierValue` is the current value of the [TickerMode] notifier
  ///   this element is subscribed to (null before the first build).
  ///
  /// A persistent `isActive != notifierValue` indicates a missed
  /// notification; [resyncTickerMode] repairs it.
  @internal
  ({bool? isActive, bool? notifierValue}) get tickerModeHealth =>
      (isActive: _isActive, notifierValue: _tickerModeNotifier?.value);

  /// Re-derives the TickerMode pause state from the current notifier value,
  /// pausing/resuming subscriptions if they are out of sync.
  ///
  /// Safe to call at any time; no-op when already in sync or before the
  /// first build.
  @internal
  void resyncTickerMode() {
    if (_tickerModeNotifier == null) return;
    _updateTickerMode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newContainer = ProviderScope.containerOf(this);
    if (container != newContainer) {
      container = newContainer;
      for (final dependency in _dependencies.values) {
        dependency.close();
      }
      _dependencies.clear();
    }
  }

  @override
  Widget build() {
    if (_tickerModeNotifier == null) {
      _updateTickerModeNotifier();
    }

    try {
      _oldDependencies = _dependencies;
      for (var i = 0; i < _listeners.length; i++) {
        _listeners[i].close();
      }
      _listeners.clear();
      _dependencies = {};
      return super.build();
    } finally {
      for (final dep in _oldDependencies!.values) {
        dep.close();
      }
      _oldDependencies = null;
    }
  }

  void _assertNotDisposed() {
    if (!context.mounted) {
      throw StateError(
        'Using "ref" when a widget is about to or has been unmounted is unsafe.\n'
        'Ref relies on BuildContext, and BuildContext is unsafe to use when the widget is deactivated.\n'
        'To safely refer to the state of providers inside State.dispose(), save the provider state in a field of your State class.',
      );
    }
  }

  @override
  StateT watch<StateT>(ProviderListenable<StateT> target) {
    _assertNotDisposed();
    return _dependencies
            .putIfAbsent(target, () {
              final oldDependency = _oldDependencies?.remove(target);

              if (oldDependency != null) {
                return oldDependency;
              }

              final sub = container.listen<StateT>(
                target,
                (_, _) => markNeedsBuild(),
              );
              _applyTickerMode(sub);
              return sub;
            })
            .readSafe()
            .valueOrProviderException
        as StateT;
  }

  @override
  void unmount() {
    /// Calling `super.unmount()` will call `dispose` on the state
    /// And [ListenManual] subscriptions should be closed after `dispose`
    super.unmount();
    _tickerModeHub?.remove(this);
    _tickerModeHub = null;
    _tickerModeNotifier = null;

    for (final dependency in _dependencies.values) {
      dependency.close();
    }
    for (var i = 0; i < _listeners.length; i++) {
      _listeners[i].close();
    }
    final manualListeners = _manualListeners?.toList();
    if (manualListeners != null) {
      for (final listener in manualListeners) {
        listener.close();
      }
      _manualListeners = null;
    }
  }

  @override
  void listen<StateT>(
    ProviderListenable<StateT> provider,
    void Function(StateT? previous, StateT value) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool weak = false,
  }) {
    _assertNotDisposed();
    assert(
      debugDoingBuild,
      'ref.listen can only be used within the build method of a ConsumerWidget',
    );

    // We can't implement a fireImmediately flag because we wouldn't know
    // which listen call was preserved between widget rebuild, and we wouldn't
    // want to call the listener on every rebuild.
    final sub = container.listen<StateT>(
      provider,
      listener,
      onError: onError,
      weak: weak,
    );
    _listeners.add(sub);
  }

  @override
  bool exists(ProviderBase<Object?> provider) {
    _assertNotDisposed();
    return ProviderScope.containerOf(this, listen: false).exists(provider);
  }

  @override
  StateT read<StateT>(ProviderListenable<StateT> provider) {
    _assertNotDisposed();
    return ProviderScope.containerOf(this, listen: false).read(provider);
  }

  @override
  ValueT refresh<ValueT>(Refreshable<ValueT> provider) {
    _assertNotDisposed();
    return ProviderScope.containerOf(this, listen: false).refresh(provider);
  }

  @override
  void invalidate(ProviderOrFamily provider, {bool asReload = false}) {
    _assertNotDisposed();
    container.invalidate(provider, asReload: asReload);
  }

  @override
  ProviderSubscription<ValueT> listenManual<ValueT>(
    ProviderListenable<ValueT> provider,
    void Function(ValueT? previous, ValueT next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
    bool weak = false,
  }) {
    _assertNotDisposed();
    final listeners = _manualListeners ??= [];

    // Reading the container using "listen:false" to guarantee that this can
    // be used inside initState.
    final container = ProviderScope.containerOf(this, listen: false);

    final sub = container.listen<ValueT>(
      provider,
      listener,
      onError: onError,
      fireImmediately: fireImmediately,
      weak: weak,
    );

    // Hook-up on onClose to avoid memory leaks.
    final previousOnClose = sub.impl.onClose;
    sub.impl.onClose = () {
      previousOnClose?.call();
      // If the subscription is closed, we remove it from the manual listeners
      // so that it doesn't leak.
      _manualListeners?.remove(sub);
    };

    listeners.add(sub);

    return sub;
  }
}
