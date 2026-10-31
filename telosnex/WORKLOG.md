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
