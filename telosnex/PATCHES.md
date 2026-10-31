# Telosnex patches on Riverpod

This fork is upstream `rrousselGit/riverpod` plus the changes below. This
file is the list of those changes. Each patch is one fix and the test
that shows it, so it can be applied to upstream `master` alone.

The `telosnex/` folder is for this fork only. Do not include it in a patch.

- Fork base: upstream `2fa6ad2ae` (2026-06-13). The fork also merged
  upstream once, on 2026-07-05 (`7ada43c3d`).
- Last check against upstream: `e0bd6a673` (2026-10-31). Patch branches
  are on `b34e73cd5` (2026-10-31).
- Fork commits since the base: 49 (no merges).

## Patch branches

Each verified patch is a local branch `patch/<ID>-<name>`. Most have one
commit on upstream `master`. R7 has one commit on R1. `telosnex/verify_patch.dart` checks it: the patch's tests
pass with the fix, and fail (or time out) with the `lib/` files of the
commit put back to upstream. Run it with a Flutter `master` SDK, because
upstream's workspace does not resolve on Flutter stable:

```sh
dart telosnex/verify_patch.dart patch/R1-scheduler-exception-safe
```

| Branch | Commit | Red, then green | Options | `scripts/tested.sh` |
|---|---|---|---|---|
| `patch/R1-scheduler-exception-safe` | `d28a48e38` | yes | | passes |
| `patch/R2-no-dirty-built-ancestor` | `66e3670ed` | yes | `--name 'notifications during a build'` | passes |
| `patch/R3-invalidate-self-during-build` | `e196c2f41` | yes | | passes |
| `patch/R4-weak-listener-releases-future` | `7df9050ee` | yes | | passes |
| `patch/R5-weak-only-not-initialized` | `151669683` | yes | | passes |
| `patch/R6-dart2js-stack-trace-identity` | `bf71df224` | yes | `--platform chrome --name 'MutationError keeps the stack trace\|AsyncValue.guard does not notify listeners again\|keeps its stack trace'` | passes |
| `patch/R7-refresh-during-dispose` | `faec4d0f5` | yes | `--base patch/R1-scheduler-exception-safe` | passes |
| `patch/P1-ticker-mode-hub` | `32f5e1b4a` | yes | `--name 'unmounting many consumers'` | passes |
| `patch/P3-lazy-scoped-directories` | `4e9990604` | yes | `--name 'child scopes do not copy inherited orphan pointers until read'` | passes |
| `patch/P4-debug-validate-internal-state` | `86798f432` | yes | | passes |
| `patch/A1-prefixed-manual-providers` | `644782f70` | yes | | passes |
| `patch/T3-avoid-sub-read` | `f2b284f8c` | yes | `--name 'reports sub.read\|throws the error of\|withFrameCache returns\|listenables of the same'` | passes |

`scripts/tested.sh` is upstream's rule that each changed `lib/x.dart` comes
with a change to its `test/x_test.dart`. All branches pass it.

On Chrome, 68 riverpod tests fail on upstream `master` too (VM-only stack
trace and timing assumptions; see X1 to X4). R6 does not change that set.

## Status

| Status | Meaning |
|---|---|
| verified | The regression fails without the fix and passes with it on the stated platform |
| ready | Applies to upstream `master` alone, with its test |
| split | One or more fork commits hold this and other changes; separate them first |
| squash | Several fork commits make one change; combine them |
| covered | Upstream has the same change; drop it at the next upstream merge |
| fork-only | Telosnex CI, tooling or notes; not a patch |

"Applies" means that `git cherry-pick` onto upstream `master` gave no
conflict. It does not mean that the tests pass.

## Runtime fixes

Changes to the behavior of `riverpod` and `flutter_riverpod`. These are
the reason the fork exists.

| ID | Change | Fork commits | Status | Test |
|---|---|---|---|---|
| R1 | `ProviderScheduler._task()` is exception-safe. One exception in `flush()` left the task pending forever, and every later refresh and dispose was dropped. This was the iOS "stuck overnight" bug. Upstream still has it. Issue #4806 reports it. | `05ba4bdcb` (scheduler half) | verified | `riverpod/test/src/core/scheduler_test.dart` |
| R7 | A refresh scheduled during the dispose pass (from `ref.onDispose`) is not dropped. | `05ba4bdcb` (scheduler half) | verified, on R1 | `scheduler_test.dart` |
| R8 | The fork's other R1 parts: each dispose guarded, and `_scheduleTask` replaces a completed task that `_task` did not finish. Not needed for R1's tests; only keep them with a test that needs them. | `05ba4bdcb` (scheduler half) | not included | Throwing `ref.onDispose` already allows the other disposes to run. No failing regression yet. |
| R2 | A consumer notified during another consumer's build is marked dirty on the next frame, not during the build. In release, Flutter leaves it dirty for good, and it never rebuilds again. The scope half of `d8d78c121` is covered upstream by `02b11c3fb` (#4805): that test passes on upstream. | `72c83d3da`, `d8d78c121`, part of `9e519ed46` | verified (consumer half) | `flutter_riverpod/test/src/core/build_phase_guard_test.dart` |
| R3 | `invalidateSelf` during build gives a clear error in debug mode, and the check applies only to manual invalidation. | `0baf71a3c`, `aba09ad39` | verified | `flutter_riverpod/test/framework_test.dart`, `riverpod/test/src/core/ref_test.dart` |
| R4 | A weak listener that keeps a disposed provider alive no longer keeps its completed future (memory). | `f67cc8baa` | verified | in the commit (199 lines) |
| R5 | Refreshing dependents does not initialize providers that only weak listeners use. | `2b922384a` | verified | in the commit |
| R6 | Errors rethrown on dart2js keep the same stack trace, so `AsyncValue` and `MutationError` equality hold. | `48553acc0`, `b80cdcd99` (test) | verified (Chrome) | `b80cdcd99` |

## Performance

Measured in Telosnex scroll profiles. They change internals, not
behavior.

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| P1 | One TickerMode listener per notifier (`_TickerModeHub`) instead of one per consumer. Includes the fix that keeps one throwing element from leaving the others paused. | `98edb6a61` (hub half), `05ba4bdcb` (hub half) | verified locally | Both tests are in `consumer_test.dart`. Timing-based regression needs CI validation. The isolation test fails with the hub but without its per-element guard. |
| P2 | The container debug id (a UUID) is made when first read, not on every container. | `98edb6a61` (`provider_container.dart` half) | pending regression | 1 line. Local benchmark saves roughly 0.5 µs per scope. No red/green test yet. |
| P3 | Scoped containers copy the parent's provider directory on read, not on creation. | `6ff0dca7f` | verified | Allocation regression in `provider_container_test.dart`. Existing assertions follow lazy storage. Unrelated loop optimizations are not included. |
| P4 | `riverpodDebugValidateInternalState`: apps can turn off internal checks in debug builds. Default unchanged. | `423642b8b` | verified | New test in `element_test.dart`. Exported by `7a67f0549` (see T1) |

## Diagnostics and debug options

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| D1 | `ProviderScheduler.health` and `tickerModeHealth`/`resyncTickerMode`, for app watchdogs. | `05ba4bdcb` (diagnostics) | fork only | The Telosnex app does not use it. |
| D2 | `ProviderTrace`: opt-in trace of dirty, refresh and flush for chosen providers. | `ff851c748`, `a2ca05a59` | fork only | The Telosnex app does not use it. |
| D3 | `debugRiverpodDevtoolEnabled`: the devtool observer is off by default, because its event history keeps providers alive. | `12584b4c3` | superseded | Upstream keeps only current states and releases disposed providers (`keeps current states and releases disposed providers` in `devtool_test.dart`); history is off by default. |

## Public API housekeeping

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| T1 | Export the debug flags from the public libraries. | `7a67f0549` | folded into P4 | P4 exports `riverpodDebugValidateInternalState` from all three packages. The devtool flag goes with D3. |
| T2 | `DevtoolObserver` is `@internal`, not `@visibleForTesting`. | `428069ac4` | superseded | Upstream already marks `DevtoolObserver` `@internal`; the analyzer reports nothing. |
| T3 | Do not call `sub.read()` inside riverpod (the `avoid_sub_read` lint), and fix the lint's message. | `e7e50526d`, `e28366cd0`, `8a20eb3bc` | verified | The `{0}` in the message made the rule throw, so it never reported. That also hid 5 `generic_name` warnings, now fixed. |

## Analyzer tooling

For `riverpod_analyzer_utils`, which `riverpod_lint` and Telosnex's lint
tools use.

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| A1 | Decode manual providers whose modifier is an import prefix or a `PrefixedIdentifier`. | `751b31568`, `a9e1c110c` | verified | Tests in `riverpod_analyzer_utils_tests` and a unit test of `identifierChain`. |
| A2 | `internal_lint` `generic_name` crashed the analyzer plugin on analyzer 14.6. | `401e0e1c0` | superseded | Upstream `2daadbf9` fixed the crash another way, with a test. |

## Test fixes

Tests that failed in the fork's CI (dart2js, Chrome, newer analyzer, or
timing). No library change.

| ID | Change | Fork commits | Notes |
|---|---|---|---|
| X1 | VM-only tests are marked VM-only. | `2c6ff0f39`, `7c2fe6bdd` | |
| X2 | Timing in four riverpod tests. | `944fc44d1`, `097a369ce`, `cbbf450c3`, `01eff8910` | Flaky in the fork's CI |
| X3 | Compare stack traces by string on dart2js. | `63eb67045` | Related to R6 |
| X4 | Analyzer 14.6 and 14.7 output in the analyzer utils tests. | `2f054873e`, `4b1ae0d95`, `7639d9a86` | `7639d9a86` is upstream #4958, written again by hand |

## Covered by upstream

| Fork commit | Upstream |
|---|---|
| `343278018` Only one task can be scheduled at a time | Same change in `provider_scope.dart` |
| `879cd27b4` Analyzer 14 and Freezed 4 in the tooling | Upstream supports analyzer 13–14 |
| `e30a6843a` `ClassMembers` is `@internal` | `2daadbf9` |

## Fork-only

| Fork commits | What |
|---|---|
| `09ed27dfe`, `9e411e6fc`, `7d6a867ff`, `6e6207da3`, `439cf54ce`, `02ee1a7af`, `01bfaaeca`, `4e9e21ab6` | CI on telosnex_ci_tools |
| `d3f6ff157`, `cdb197c9d`, `f4c3b77d5`, part of `9e519ed46` | Flutter 3.47.1, Freezed 4 output, website lint, example app |
| `cc198bf52` | Research: handwritten providers versus `@riverpod` |
