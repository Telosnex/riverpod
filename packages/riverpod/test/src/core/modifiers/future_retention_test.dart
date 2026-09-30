import 'dart:async';

import 'package:riverpod/src/internals.dart';
import 'package:test/test.dart';

import '../../matrix.dart';

// All four async provider kinds share ElementWithFuture, but have different
// paths for synchronous completion, stream cancellation, and notifier reuse.
final _providers = <
  String,
  $ProviderBaseImpl<AsyncValue<Object?>> Function(
    FutureOr<Object?> Function() create,
  )
>{
  'FutureProvider':
      (create) => FutureProvider.autoDispose<Object?>((ref) => create()),
  'AsyncNotifierProvider':
      (create) => AsyncNotifierProvider.autoDispose<
        DeferredAsyncNotifier<Object?>,
        Object?
      >(() => DeferredAsyncNotifier((ref, self) => create())),
  'StreamProvider':
      (create) => StreamProvider.autoDispose<Object?>(
        (ref) => Stream.fromFuture(Future<Object?>.sync(create)),
      ),
  'StreamNotifierProvider':
      (create) => StreamNotifierProvider.autoDispose<
        DeferredStreamNotifier<Object?>,
        Object?
      >(
        () => DeferredStreamNotifier(
          (ref, self) => Stream.fromFuture(Future<Object?>.sync(create)),
        ),
      ),
};

void main() {
  for (final entry in _providers.entries) {
    group(entry.key, () {
      for (final listenToFuture in [false, true]) {
        group('weak ${listenToFuture ? 'future' : 'state'} observer', () {
          for (final fails in [false, true]) {
            test(
              'releases completed ${fails ? 'error' : 'data'} on retirement without notifying observers',
              () async {
                final container = ProviderContainer.test(
                  retry: (count, error) => null,
                );
                var builds = 0;
                var notifications = 0;
                final provider = entry.value(() {
                  builds++;
                  if (fails) throw StateError('failure $builds');
                  return Object();
                });
                final element =
                    container.readProviderElement(provider)
                        as ElementWithFuture<AsyncValue<Object?>, Object?>;
                final weak =
                    listenToFuture
                        ? container.listen(
                          provider.future!,
                          (previous, next) => notifications++,
                          weak: true,
                        )
                        : container.listen(
                          provider,
                          (previous, next) => notifications++,
                          weak: true,
                        );
                final active = container.listen(provider, (previous, next) {});
                final oldFuture = container.read(provider.future!);
                if (fails) {
                  await expectLater(oldFuture, throwsStateError);
                } else {
                  await oldFuture;
                }
                final notificationsBeforeDisposal = notifications;

                active.close();
                await container.pump();

                expect(container.readProviderElement(provider), same(element));
                expect(element.value, const AsyncLoading<Object?>());
                expect(element.futureNotifier.result, isNull);
                expect(weak.closed, isFalse);
                expect(builds, 1);
                expect(notifications, notificationsBeforeDisposal);
                // Removing the provider's cache must not alter a future already
                // held by a caller, or close the persistent weak observer.
                if (fails) {
                  await expectLater(oldFuture, throwsStateError);
                } else {
                  await expectLater(oldFuture, completes);
                }

                final reopened = container.listen(
                  provider,
                  (previous, next) {},
                );
                final newFuture = container.read(provider.future!);
                expect(newFuture, isNot(same(oldFuture)));
                if (fails) {
                  await expectLater(newFuture, throwsStateError);
                } else {
                  await newFuture;
                }
                expect(builds, 2);
                expect(notifications, greaterThan(notificationsBeforeDisposal));
                reopened.close();
                await container.pump();
                expect(element.futureNotifier.result, isNull);
              },
            );
          }
        });
      }

      test('preserves a pending future for the replacement build', () async {
        final container = ProviderContainer.test();
        final original = Completer<Object?>();
        final replacement = Completer<Object?>();
        var builds = 0;
        final provider = entry.value(() {
          builds++;
          return builds == 1 ? original.future : replacement.future;
        });
        final weak = container.listen(
          provider,
          (previous, next) {},
          weak: true,
        );
        final active = container.listen(provider, (previous, next) {});
        final element =
            container.readProviderElement(provider)
                as ElementWithFuture<AsyncValue<Object?>, Object?>;
        final pending = container.read(provider.future!);

        active.close();
        await container.pump();
        expect(
          element.futureNotifier.requireResult.valueOrRawException,
          same(pending),
        );
        expect(weak.closed, isFalse);

        container.listen(provider, (previous, next) {});
        expect(container.read(provider.future!), same(pending));
        final value = Object();
        replacement.complete(value);
        expect(await pending, same(value));
        expect(container.read(provider).value, same(value));

        original.complete(Object());
        await container.pump();
        expect(container.read(provider).value, same(value));
      });

      test('keeps an in-flight future across invalidation', () async {
        final container = ProviderContainer.test();
        final original = Completer<Object?>();
        final replacement = Completer<Object?>();
        var builds = 0;
        final provider = entry.value(() {
          builds++;
          return builds == 1 ? original.future : replacement.future;
        });
        container.listen(provider, (previous, next) {});
        final pending = container.read(provider.future!);
        container.invalidate(provider);
        expect(container.read(provider.future!), same(pending));
        final value = Object();
        replacement.complete(value);
        expect(await pending, same(value));

        original.complete(Object());
        await container.pump();
        expect(container.read(provider).value, same(value));
      });

      test('fully disposed element drops its completed future cache', () async {
        final container = ProviderContainer.test();
        final provider = entry.value(Object.new);
        final active = container.listen(provider, (previous, next) {});
        final element =
            container.readProviderElement(provider)
                as ElementWithFuture<AsyncValue<Object?>, Object?>;
        final oldFuture = container.read(provider.future!);
        await oldFuture;
        active.close();
        await container.pump();
        expect(container.exists(provider), isFalse);
        expect(element.futureNotifier.result, isNull);
        await expectLater(oldFuture, completes);
      });
    });
  }
}
