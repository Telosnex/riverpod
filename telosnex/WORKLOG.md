# Worklog

## 2026-10-31: first sort of the fork

- Listed the 49 fork commits since upstream `2fa6ad2ae`, and tried each
  one alone on upstream `e0bd6a673` with `git cherry-pick --no-commit`.
- 3 are covered by upstream: `343278018`, `879cd27b4`, `e30a6843a`.
- Ready alone: `f67cc8baa`, `2b922384a`, `48553acc0`, `423642b8b`,
  `0baf71a3c` with `aba09ad39`, and the scheduler half of `05ba4bdcb`.
- Most conflicts come from fork commits that change the same code, not
  from upstream:
  - `d8d78c121` replaces `_canMarkNeedsBuild` from `72c83d3da` with
    `BuildPhaseGuard`, so R2 is the final form of both.
  - `05ba4bdcb` changes `consumer.dart` code that `98edb6a61` added.
  - `9e519ed46` renames type parameters in code from `d8d78c121` and in
    the example app.
- Upstream fixes since the base that this fork does not have (see the
  upstream analysis): `05534890a` (#4812, frozen scheduler), `02b11c3fb`
  (#4805, TickerMode resume), `73118601f` (#4345, listener leak),
  `a4174afa3` (#4953), `1ba4b2208` (#4872), `3acd98ded` (#4786).
  R2 and P1 touch the same code as `02b11c3fb`; compare them before a
  merge.

### Next

1. Split `05ba4bdcb` into R1, the P1 hub fix and D1.
2. Split `98edb6a61` into P1 and P2.
3. Squash R2, R3, R6 and T3.
4. Build each patch on upstream `master` and run its test with and without
   the fix.

## 2026-10-31: red, then green, for the first patches

- Upstream's workspace needs a newer `test_api` than Flutter 3.47.1 pins.
  Use Flutter `master`, as upstream's CI does
  (`~/dev/flutter-upstream-pr`, 3.50.0-1.0.pre-171, Dart 3.15.0-56.0.dev).
- Added `telosnex/verify_patch.dart`.
- R1: on upstream, the test did not fail; it hung. After the stuck task,
  the devtool's frame loop (`devtool.dart`, `addEvent`) waits on
  `scheduler.pendingFuture` in a microtask loop, so timers never run
  again in debug mode. Found by pausing the isolate through the VM
  service. The test now runs each scenario in an isolate with a 5 s
  timeout. That change is in the test only.
- R1 is smaller than the fork's commit: `try`/`finally` in `_task` and a
  guard around each `flush()` are enough for its tests. The rest is R7 and
  R8.
- R2: the scope test passes on upstream (`02b11c3fb` does not schedule a
  refresh while an element flushes), so only the consumer half is a patch.
  Ported by hand: the fork's version builds on the TickerMode hub and
  `ProviderTrace`.
- R3, R5: upstream's `1d24615b5` removed `StateProvider` from these test
  files. The tests use `Provider.autoDispose` and the `Counter` notifier
  of `test/src/utils.dart` instead.
- R6: upstream's `a46ad90fb` moved `test/feature/mutation_test.dart` to
  `test/src/core/mutations_test.dart`. The fix only changes dart2js, so the
  check runs on Chrome. `whenData preserves isLoading/isRefreshing` fails
  on Chrome on upstream too (see X3), so the check runs only the patch's
  two tests.
- P4: added a test. It breaks the pause count by hand and checks that the
  assertion runs when the switch is on, and not when it is off.

### Next

1. R7 and R8 from the rest of `05ba4bdcb`.
2. P1 (TickerMode hub) with its isolation fix, then P2, P3.
3. D1 to D3, T1 to T3, A1, A2. X1 to X4 are test-only and have no
   red/green.
4. Make the patches pass `scripts/tested.sh`.

## 2026-10-31: R7, P1, P3

- R7: the regression reports one dependent build instead of two without the
  fix. After the dispose pass, the scheduler flushes refreshes that the
  dispose pass added. The branch stacks on R1. All 1,639 riverpod tests pass.
- R8: a throwing `ref.onDispose` does not stop other disposes with R1.
  Removed the trial branch. The extra dispose guard and stale-task recovery
  remain excluded until a regression needs them.
- P1: consumers share a TickerMode notifier through an identity set. The
  per-element error guard stays with the hub. Without that guard, the
  isolation test fails because other consumers stay paused.
- P1 regression: unmount the last 4,000 of 8,000 consumers under one real
  TickerMode. Compare against plain StatefulWidgets. Upstream takes about
  3.1–3.7 times as long. The hub takes about 0.95–1.13 times as long. The
  test limit is 2. This timing test needs validation on CI hardware.
- The first performance probes were misleading. Without a TickerMode
  ancestor, Flutter supplies a constant notifier. Watching one shared
  provider also adds a separate quadratic teardown cost. The final probe
  uses a real TickerMode and consumers that watch no providers.
- P1: all 161 flutter_riverpod tests pass. `scripts/tested.sh` passes.
- P2: making the debug ID lazy saves roughly 0.5 µs per scoped container
  locally. No regression test yet. No patch branch was created.
- P3: deterministic allocation regression checks that the child initially
  stores only its local override. Reading an inherited provider caches
  one entry, with the same pointer as its parent. Red without the fix,
  green with it.
- P3: existing layout assertions now inspect local storage where needed.
  Disposal still checks that lookups across all scopes return null.
  All 1,637 riverpod tests pass. `scripts/tested.sh` passes. Removed the
  unrelated loop optimizations from the fork's commit.
- Fixed `verify_patch.dart`: Flutter accepts `--name`, not `-n`.

### Next

1. D1 to D3, T1 to T3, A1, A2.
2. Find a regression check for P2, or keep it outside the verified set.
3. Validate P1's timing regression on CI hardware.
4. Resolve the remaining `scripts/tested.sh` failures for the earlier patches.
