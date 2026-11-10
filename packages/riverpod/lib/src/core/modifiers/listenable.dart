part of '../../framework.dart';

/// Adds [listenable] to [ProviderListenable].
extension ProviderListenableListenable<ValueT> on ProviderListenable<ValueT> {
  /// Exposes a [ValueListenable] that tracks the state of this provider.
  ///
  /// Note:
  /// A unique [ValueListenable] is created per listener on this modifier. As such,
  /// doing `ref.read(provider.listenable)` will have the [ValueListenable] immediately get disposed of.
  /// Consider using `listen/watch` methods instead.
  ProviderListenable<ValueListenable<ValueT>> get listenable {
    return _ListenableListenable(this);
  }
}

@immutable
class _ListenableListenable<ValueT>
    extends CustomProviderListenable<ValueT, ValueListenable<ValueT>> {
  _ListenableListenable(this.source);

  @override
  final ProviderListenable<ValueT> source;

  @override
  _ListenableTransformer2<ValueT> createTransformer() {
    return _ListenableTransformer2();
  }

  @override
  bool operator ==(Object other) =>
      other is _ListenableListenable<ValueT> && other.source == source;

  @override
  int get hashCode => Object.hash(ValueT, source);
}

final class _ListenableTransformer2<ValueT>
    extends
        SyncProviderTransformer2<
          ValueT,
          ValueListenable<ValueT>,
          _ListenableListenable<ValueT>
        >
    with ChangeNotifier
    implements ValueListenable<ValueT> {
  void _checkSubscriptionIsAlive() {
    final innerSub = _innerSub;
    if (innerSub == null || innerSub.closed) {
      throw StateError(
        'The subscription backing this `.listenable` was closed. Obtain '
        '`.listenable` through `ref.watch`, `ref.listen` or '
        '`container.listen`, not `read`.',
      );
    }
  }

  @override
  ValueT get value {
    _checkSubscriptionIsAlive();
    return read();
  }

  @override
  ValueListenable<ValueT> initState() {
    // Start paused so that if no listener is added to the listenable,
    // the source provider is paused.
    pause();
    return this;
  }

  @override
  void onEvent(AsyncResult<ValueT> prev, AsyncResult<ValueT> next) {
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    _checkSubscriptionIsAlive();
    if (!hasListeners) resume();

    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    final hadListeners = hasListeners;
    super.removeListener(listener);

    if (!hasListeners && hadListeners) pause();
  }

  @override
  void onClose() {
    dispose();
  }
}
