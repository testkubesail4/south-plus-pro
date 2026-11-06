---
name: test-audit
license: MIT
description: "Use when writing, changing, reviewing, or auditing tests; assessing redundant or implementation-coupled coverage; or pruning a subsystem's test suite and test-only production seams. Do NOT use for production-only refactoring or general code review without a test-quality question."
---

# Test Audit

Adapted from the [upstream test-audit skill](https://github.com/openclaw/openclaw/tree/main/.agents/skills/test-audit). The upstream copyright and MIT license terms are preserved in [LICENSE](LICENSE).

Three modes, one value bar. Optimize for confidence, not deletion count.

- **Authoring:** gate each new or changed test at write time.
- **Audit:** inspect a focused set of low-value or overlapping tests and the
  test-only production seams they keep alive.
- **Campaign:** review one subsystem's entire test surface. Read
  [CAMPAIGN.md](CAMPAIGN.md) before starting.

The **production owner** is the code responsible for a behavior. Its **owning
boundary** is the interface where that behavior can be independently observed.
A **test-only production seam** is an export, flag, wrapper, or injection hook
needed by tests but not by production callers or a supported external contract.

## Authoring gate

Before adding or changing a test, answer four questions. A missing answer means
it is not ready:

1. What observable behavior, invariant, or independent contract does it protect?
2. What credible regression makes it fail?
3. Why does existing coverage not already catch that failure? Give each contract
   one primary test owner at the strongest practical boundary. Another layer
   needs a distinct risk, such as transport or lifecycle behavior the primary
   test cannot reach. Prefer extending a parameterized case or existing fixture
   over duplicating a test; consolidate repeated setup in the same change.
4. Does it need a production seam no production caller or supported contract
   needs? If so, test through the real boundary instead.

Check every [junk pattern](#junk-patterns). A match fails the gate unless the
[retention bar](#retention-bar) identifies an independent contract it protects.
A test that breaks under behavior-preserving refactoring is suspect: rewrite
it around observable behavior unless the inspected structure is itself an
explicit contract.

A bug regression test must fail on the pre-fix code for the intended reason and
pass after the owning-boundary repair. Demonstrate both states; if the control
cannot run, record the blocker rather than claiming the regression is proved.
Do not replay the same scenario at every layer it crosses.

## Junk patterns

Use this checklist in all three modes:

- assertion-free coverage probes with no meaningful failure signal;
- self-comparisons and identity copiers;
- copied fixtures, inventories, manifests, or export lists;
- exact source, import, or string greps without an independent contract;
- private predicate or call-shape tests duplicated at real boundaries;
- repeated invocations of the same contract;
- adapter-local replays of shared helpers;
- tests whose only purpose is preserving test-only exports, globals, or wrappers;
- dead production code whose only callers are tests;
- expected values produced by the helper or renderer under test;
- mocks that implement the behavior being asserted, or one identical mock
  standing in for APIs with different contracts;
- fixtures that supply the acknowledgement, admission decision, or callback
  ordering the production owner should produce;
- persistence assertions against a store the exercised path never writes;
- capability tests that restate declared flags instead of exercising the
  behavior those flags promise;
- negative controls that pass for an unrelated reason, such as a rejection by
  a different guard or a path the production code never reaches;
- names or fixtures that promise more than their inputs and assertions exercise.

## Value bar and context

Tests justify their maintenance cost by protecting behavior, a credible
regression, or an independently meaningful contract. Implementation coupling
is a reason to investigate, not automatic permission to delete.

Read repository-wide and scoped contributor or agent instructions first.
Identify the actual test runner, test discovery and CI routing, validation
commands, and required execution environment. Use existing tools; do not invent
repository commands or introduce a framework just for an audit.

Before judging a candidate, read the complete test and production owner, entry
points, callers, callees, sibling implementations, overlapping tests, and
relevant history. Check public consumers and dynamic discovery before declaring
a seam unused. For dependency-backed behavior, inspect the relevant dependency
source or types. Record unavailable evidence as uncertainty.

## Discovery

Keep discovery read-only and report evidence before editing. A review-only
request ends with findings; apply changes only within the authorized scope.

For broad scope, divide discovery by actual repository boundaries: core
modules, libraries, adapters, applications, tooling, and a cross-cutting pattern
sweep. Use parallel read-only reviewers when available, or inspect sequentially.
Outside campaign mode, prefer a few high-confidence candidates over a large
speculative inventory.

Done when each proposed candidate has the evidence below, and uncertain
candidates are explicitly deferred.

## Retention bar

Keep a test when it independently enforces a public API, extension interface,
protocol, configuration, migration, storage, security, platform, default,
byte-exact output, generated cross-language artifact, packaging, release, or
architecture contract. Also keep:

- call ordering when order is observable behavior;
- regressions with a credible failure mode;
- source inspection when it is the cheapest independent guard: it detects a
  contract change, such as a user-facing key, byte, or path, and survives an
  identifier-only refactor;
- a meaningful test that fails on the baseline: investigate a possible product
  defect instead of deleting the evidence.

Static or slow is not a deletion reason. A test that resembles implementation
may still be the independent contract; prove otherwise before removing it.

## Candidate evidence

Record every field before editing. A missing field blocks deletion:

- exact test name and location;
- what failure it can actually detect;
- non-test callers or supported external consumers of the covered seam;
- stronger remaining owning-boundary proof, or why no proof is needed;
- relevant history and why the test or seam exists;
- production or test-support deletion unlocked, if any;
- risk and the actual focused validation command.

## Edit shape

Choose one coherent owning-boundary batch. Remove obsolete test-only exports,
globals, wrappers, and dead production paths rather than preserving aliases.
Move retained regressions to their canonical owners. Consolidate repeated
package or dependency assertions into one shared contract test.

Prefer net-negative production code, but never trade away a distinct contract
for a smaller diff. Do not replace deleted tests with the same implementation
assertions in another form or delete uncertain candidates to inflate counts.

Before removing coverage, confirm:

- [ ] The candidate evidence is complete.
- [ ] Each meaningful contract has a named remaining test owner.
- [ ] Any transferred assertion is in place before its old test is removed.
- [ ] Removed seams have no required production or external consumers.

## Validation

Keep the tested checkout stable while tests run. Use the repository's approved
runner, environment, and resource limits; follow its isolation rules for heavy
or integration checks.

1. Record the focused baseline, then run the smallest affected owner and sibling
   suites after the change.
2. For removed source greps or plan assertions, exercise the executable behavior
   or dry-run that owns the real contract.
3. Run targeted formatting and whitespace checks, such as `git diff --check`
   in a Git repository.
4. Run the repository's required changed-file gates and broader checks dictated
   by the affected contracts. Verify moved tests remain discoverable in CI.
5. Inspect the diff and line counts; report production/tooling separately from
   tests and test support.
6. Review the final diff for lost contracts and assertions that cannot fail.
   Use an independent reviewer when available; state when only self-review ran.

Done when required checks pass and coverage preservation has been reviewed.
Report unavailable checks and pre-existing failures explicitly; partial
validation is not a clean pass.

## Guardrails

| Temptation | Required response |
| --- | --- |
| "It is slow or static, so it is junk." | Identify its independent contract before judging its value. |
| "The name says it covers the bug." | Read the assertions and demonstrate the intended failure. |
| "Another suite probably covers it." | Name the remaining proof and check the actual failure mode. |
| "The baseline is red, so remove the test." | Investigate the failure; preserve meaningful defect evidence. |
| "More deleted lines means a better audit." | Optimize for confidence and simpler ownership, not counts. |

## Landing and handoff

Commit, push, open a pull request, or merge only when authorized, using the
repository's established workflow. Keep batches coherent. Before continuing a
broad audit, refresh against the current target branch and repeat read-only
discovery; earlier conclusions may no longer hold.

Report:

- root cause and removed low-value categories;
- production owner simplifications;
- retained false positives and their contracts;
- checks actually run, results, and validation gaps;
- production versus test/support line changes;
- commit, review, and merge state, where applicable;
- named follow-ups.
