# Telosnex patches on Riverpod

This fork is upstream `rrousselGit/riverpod` plus the changes below. This
file is the list of those changes. Each patch is one fix and the test
that shows it, so it can be applied to upstream `master` alone.

The `telosnex/` folder is for this fork only. Do not include it in a patch.

- Fork base: upstream `2fa6ad2ae` (2026-06-13). The fork also merged
  upstream once, on 2026-07-05 (`7ada43c3d`).
- Last check against upstream: `e0bd6a673` (2026-10-31).
- Fork commits since the base: 49 (no merges).

## Status

| Status | Meaning |
|---|---|
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
| R1 | `ProviderScheduler._task()` is exception-safe. One exception in `flush()` left the task pending forever, and every later refresh and dispose was dropped. This was the iOS "stuck overnight" bug. Upstream still has it. Issue #4806 reports it. | `05ba4bdcb` (scheduler half) | split, then ready | `riverpod/test/src/core/scheduler_wedge_test.dart` |
| R2 | Never mark an already-built ancestor dirty during a build pass. In release, Flutter drops the mark, and the element never rebuilds again. Replaces the debug-only probe of `72c83d3da`. | `72c83d3da`, `d8d78c121`, part of `9e519ed46` | squash | `flutter_riverpod/test/build_phase_wedge_test.dart` |
| R3 | `invalidateSelf` during build gives a clear error in debug mode, and the check applies only to manual invalidation. | `0baf71a3c`, `aba09ad39` | squash, then ready | `flutter_riverpod/test/framework_test.dart`, `riverpod/test/src/core/ref_test.dart` |
| R4 | A weak listener that keeps a disposed provider alive no longer keeps its completed future (memory). | `f67cc8baa` | ready | in the commit (199 lines) |
| R5 | Refreshing dependents does not initialize providers that only weak listeners use. | `2b922384a` | ready | in the commit |
| R6 | Errors rethrown on dart2js keep the same stack trace, so `AsyncValue` and `MutationError` equality hold. | `48553acc0`, `b80cdcd99` (test) | squash, then ready | `b80cdcd99` |

## Performance

Measured in Telosnex scroll profiles. They change internals, not
behavior.

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| P1 | One TickerMode listener per notifier (`_TickerModeHub`) instead of one per consumer. Includes the fix that keeps one throwing element from leaving the others paused. | `98edb6a61` (hub half), `05ba4bdcb` (hub half) | split, squash | The hub caused the second half of the overnight bug. Its isolation fix must stay with it. Test: `flutter_riverpod/test/src/core/ticker_mode_hub_test.dart` |
| P2 | The container debug id (a UUID) is made when first read, not on every container. | `98edb6a61` (`provider_container.dart` half) | split, then ready | 1 line |
| P3 | Scoped containers copy the parent's provider directory on read, not on creation. | `6ff0dca7f` | conflict in a test | Conflict is in `auto_dispose_test.dart` only |
| P4 | `riverpodDebugValidateInternalState`: apps can turn off internal checks in debug builds. Default unchanged. | `423642b8b` | ready | Exported by `7a67f0549` (see T1) |

## Diagnostics and debug options

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| D1 | `ProviderScheduler.health` and `tickerModeHealth`/`resyncTickerMode`, for app watchdogs. | `05ba4bdcb` (diagnostics) | split | The Telosnex watchdog uses these. Separate from R1 and P1. |
| D2 | `ProviderTrace`: opt-in trace of dirty, refresh and flush for chosen providers. | `ff851c748`, `a2ca05a59` | squash; conflicts | Made for the flutter-pi wedge. Telosnex-specific in purpose. |
| D3 | `debugRiverpodDevtoolEnabled`: the devtool observer is off by default, because its event history keeps providers alive. | `12584b4c3` | conflict | Changes upstream's default. Check upstream `dc85ff6a` (devtool memory leak) first; it may make this unneeded. |

## Public API housekeeping

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| T1 | Export the debug flags from the public libraries. | `7a67f0549` | conflict | Depends on P4 and D3 |
| T2 | `DevtoolObserver` is `@internal`, not `@visibleForTesting`. | `428069ac4` | conflict | Small |
| T3 | Do not call `sub.read()` inside riverpod (the `avoid_sub_read` lint), and fix the lint's message. | `e7e50526d`, `e28366cd0`, `8a20eb3bc` | squash, then ready | No behavior change |

## Analyzer tooling

For `riverpod_analyzer_utils`, which `riverpod_lint` and Telosnex's lint
tools use.

| ID | Change | Fork commits | Status | Notes |
|---|---|---|---|---|
| A1 | Decode manual providers whose modifier is an import prefix or a `PrefixedIdentifier`. | `751b31568`, `a9e1c110c` | squash; conflicts | Test in `a9e1c110c` |
| A2 | `internal_lint` `generic_name` crashed the analyzer plugin on analyzer 14.6. | `401e0e1c0` | conflict | Repository tooling |

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
