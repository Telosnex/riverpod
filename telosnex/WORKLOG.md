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
