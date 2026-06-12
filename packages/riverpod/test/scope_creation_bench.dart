// Micro-benchmark for ProviderContainer child-scope creation/disposal cost.
//
// Models the telosnex hot path: a root container with many live providers
// (the app), and a ProviderScope with a couple of value overrides per list
// tile (2-3 scopes per tile, ~dozens of tiles per scroll burst).
//
// Run: dart test test/scope_creation_bench.dart --plain-name bench
// ignore_for_file: avoid_print

import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('bench scope creation', () {
    _run(orphanCount: 300, familyCount: 60);
    _run(orphanCount: 1200, familyCount: 240);
  });
}

void _run({required int orphanCount, required int familyCount}) {
  {
    const membersPerFamily = 5;
    const childScopes = 2000;

    final orphans = [
      for (var i = 0; i < orphanCount; i++) Provider<int>((ref) => i),
    ];
    final families = [
      for (var i = 0; i < familyCount; i++)
        Provider.family<int, int>((ref, arg) => arg),
    ];
    final overridden = Provider<int>((ref) => -1);

    final root = ProviderContainer();
    for (final p in orphans) {
      root.read(p);
    }
    for (final f in families) {
      for (var m = 0; m < membersPerFamily; m++) {
        root.read(f(m));
      }
    }

    // Warmup.
    for (var i = 0; i < 200; i++) {
      ProviderContainer(
        parent: root,
        overrides: [overridden.overrideWithValue(i)],
      ).dispose();
    }

    final swCreate = Stopwatch();
    final swDispose = Stopwatch();
    for (var i = 0; i < childScopes; i++) {
      swCreate.start();
      final child = ProviderContainer(
        parent: root,
        overrides: [overridden.overrideWithValue(i)],
      );
      // Typical tile behavior: read a couple of root providers through the
      // child, which exercises the upsert/inherit path.
      child.read(orphans[i % orphanCount]);
      child.read(overridden);
      swCreate.stop();
      swDispose.start();
      child.dispose();
      swDispose.stop();
    }
    print(
      '[$orphanCount orphans/$familyCount families] '
      'create+2 reads: ${swCreate.elapsedMicroseconds / childScopes} us/scope, '
      'dispose: ${swDispose.elapsedMicroseconds / childScopes} us/scope',
    );
    root.dispose();
  }
}
