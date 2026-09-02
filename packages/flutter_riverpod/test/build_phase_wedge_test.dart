// Regression tests for a release-only wedge observed on flutter-pi.
//
// Flutter builds dirty elements in depth order. If an element that has
// *already* been built in the current build pass is marked dirty again by a
// deeper element's build, `BuildScope._flushDirtyElements` never revisits it:
// in debug the framework throws ("setState() or markNeedsBuild() called
// during build"); in release the element is silently dropped with
// `dirty == true`, and since `Element.markNeedsBuild` early-returns on
// `dirty`, that element never rebuilds again for the life of the app.
//
// Riverpod reaches that path in two places:
//   1. `ProviderScope`'s vsync calls `setState` from `scheduleRefresh`. When a
//      consumer's `ref.watch` flushes a dirty provider during build and that
//      invalidates a dependent, the scope (an ancestor that already built this
//      frame) is marked dirty and wedges. Its build-driven task never runs
//      again; only the zero-duration timer fallback does, racing every frame.
//   2. Once (1) leaves active providers dirty at frame start, the first deep
//      consumer to `ref.watch` them flushes them, notifying ancestor consumers
//      that already built (or were clean) this frame. Those wedge too.
//
// Debug mode surfaces the same conditions as framework exceptions, so these
// tests are red without the guards even though the production symptom is
// release-only.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/src/internals.dart'
    show InternalProviderContainer, ProviderTrace;
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/legacy.dart';
import 'package:riverpod/src/internals.dart' show Task, Vsync;

/// A vsync that never runs its task: stands in for a wedged ProviderScope.
final class _WedgedVsync implements Vsync {
  @override
  void Function()? scheduleRefresh(Task task) => null;
  @override
  void Function()? scheduleDispose(Task task) => null;
}

void main() {
  tearDown(() {
    ProviderTrace.hook = null;
    ProviderTrace.filter = null;
  });

  testWidgets(
    'a scope refresh scheduled during a descendant build runs from the next '
    'frame build, without setState-during-build and without timers',
    (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);

      final dep = StateProvider((ref) => 0, name: 'dep');
      final flushed = Provider((ref) => ref.watch(dep), name: 'flushed');
      final dependent = Provider(
        (ref) => ref.watch(flushed),
        name: 'dependent',
      );
      final events = <String>[];
      final taskFlushes = <String>[];
      ProviderTrace.filter = (origin) => origin.name == 'dependent';
      ProviderTrace.hook = (event, fields) {
        events.add(event);
        if (event == 'flush' && fields['fromTask'] == true) {
          taskFlushes.add(fields['provider'] as String);
        }
      };

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: Container()),
      );

      // Alive without any Flutter listener, so the scheduler task skips them
      // (inactive) and the consumer below is the one that flushes `flushed`
      // during its build, which invalidates `dependent` mid-build.
      container.read(flushed);
      container.read(dependent);
      container.read(dep.notifier).state++;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder:
                (context, ref, _) => Text(
                  '${ref.watch(flushed)}',
                  textDirection: TextDirection.ltr,
                ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsOneWidget);
      expect(events, contains('scheduleRefresh'));
      expect(
        events,
        isNot(contains('vsync.buildCallTask')),
        reason: 'the refresh must not run inside the current build pass',
      );
      events.clear();

      // `pump()` without a duration does not fire zero-duration timers, so
      // only the scope's own build path can run the task here.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        events,
        contains('vsync.buildCallTask'),
        reason: 'the scope must rebuild on the next frame and run the task',
      );

      // And the scope must remain a working vsync afterwards: with an active
      // listener the refresh must come from the scheduler task, on the next
      // frame, again without timers.
      container.listen(dependent, (_, _) {});
      container.read(dep.notifier).state++;
      taskFlushes.clear();
      await tester.pump();
      expect(taskFlushes, contains(endsWith('dependent')));
    },
  );

  testWidgets(
    'an ancestor consumer notified by a descendant build-time flush is '
    'rebuilt on the next frame instead of being dropped by the build scope',
    (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final dep = StateProvider((ref) => 0);
      final x = Provider((ref) => ref.watch(dep));

      final middle = GlobalKey<_RebuildableState>();
      final deep = GlobalKey<_RebuildableState>();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Column(
            children: [
              // Shallow consumer (the `App` analog). Clean this frame.
              Consumer(
                builder:
                    (context, ref, _) => Text(
                      'ancestor:${ref.watch(x)}',
                      textDirection: TextDirection.ltr,
                    ),
              ),
              // A dirty element between the two in depth order. This is what
              // defeats BuildScope's contiguous-dirty walk-back in release.
              _Rebuildable(
                key: middle,
                builder:
                    (_) => _Rebuildable(
                      key: deep,
                      builder:
                          (_) => Consumer(
                            builder:
                                (context, ref, _) => Text(
                                  'descendant:${ref.watch(x)}',
                                  textDirection: TextDirection.ltr,
                                ),
                          ),
                    ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('ancestor:0'), findsOneWidget);

      // Simulate a wedged scope: the task that would normally flush `x` at
      // the top of the frame never runs.
      container.scheduler.flutterVsyncs
        ..clear()
        ..add(_WedgedVsync());

      container.read(dep.notifier).state++;
      middle.currentState!.rebuild();
      deep.currentState!.rebuild();

      // The deep consumer's ref.watch flushes `x`, which notifies the ancestor
      // consumer while the deep one is building.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('descendant:1'), findsOneWidget);

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('ancestor:1'), findsOneWidget);

      // Not wedged: a later, ordinary notification still rebuilds it.
      container.read(dep.notifier).state++;
      deep.currentState!.rebuild();
      await tester.pump();
      await tester.pump();
      expect(find.text('ancestor:2'), findsOneWidget);
    },
  );
}

/// Rebuilds its subtree on demand. Uses a builder (not a `child`) so the
/// subtree gets fresh widget instances and really rebuilds.
class _Rebuildable extends StatefulWidget {
  const _Rebuildable({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<_Rebuildable> createState() => _RebuildableState();
}

class _RebuildableState extends State<_Rebuildable> {
  void rebuild() => setState(() {});
  @override
  Widget build(BuildContext context) => widget.builder(context);
}
