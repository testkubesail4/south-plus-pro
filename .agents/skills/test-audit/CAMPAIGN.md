# Test-pruning campaign

Campaign mode reviews one subsystem's whole test surface as a coherent change:
a module, service, adapter, library, or application area. The value bar,
retention bar, candidate evidence, and validation in [SKILL.md](SKILL.md) apply
to every lane. Use a single reviewable change when practical, or dependency-
ordered batches that each preserve coverage.

Each step ends on its completion criterion. Record blockers explicitly rather
than treating uninspected or unexecuted work as complete.

## 1. Baseline

Pin the repository revision. Record the subsystem's test and support line
counts, production counts separately, and every in-scope test file's pass/fail
state. Keep baseline failures in their own list: they may be real product bugs,
not stale tests. Identify unavailable credentials, services, platforms, and
other execution prerequisites without exposing secrets.

Done when every in-scope test file has a recorded baseline result or an explicit
execution blocker. Resolve blockers affecting a proposed deletion before
removing its coverage.

## 2. Lanes and inventory

Split the surface into **lanes** along production ownership boundaries, not
file prefixes. Examples include configuration, commands, dispatch, persistence,
transport, shared logic, and test harnesses. Include subsystem cases exercised
at shared boundaries and any integration, end-to-end, manual QA, or live-service
scenarios. Run live checks only with the required authorization and safeguards.

Done when every owned test file and QA scenario belongs to exactly one lane,
with cross-lane dependencies noted.

## 3. Read-only ledger per lane

Assign independent read-only reviewers when available; otherwise review lanes
sequentially. Read every assigned test in full, including parameter tables,
and inspect production owners, entry points, callers, history, and CI routing.
Record every test declaration in a **ledger** with one mark. A parameterized
test is one declaration unless its rows need different marks; then mark rows
individually.

- `R`: retain, naming the contract and regression it catches. A retained test
  moved to a clearer location stays `R`, with the move noted.
- `F`: retain the contract but repair the assertion, such as a vacuous negative
  that succeeds for an unrelated reason.
- `C`: consolidate, naming the owner that absorbs the assertion first: a sibling
  parameterized case, a stronger boundary suite, or a shared owner's tests.
- `D`: delete, naming the proof that remains or explaining why no meaningful
  contract exists.

Judge tests by their assertions, not their names. A test called "clears state"
may only assert that state remains unchanged.

Done when every declaration has a mark and an evidence line. Flag unresolved
evidence as blocking rather than assigning a speculative deletion.

## 4. Layer plan per lane

Treat the ledger as input, not the edit list. Make a second read-only pass to
look for redundant **layers**, such as several mocked adapter suites replaying
a shared helper already covered through a stronger observable boundary.

Name the **keeper** suite for each contract: the suite that owns its remaining
proof. Prefer a real protocol or transport boundary with controlled external
I/O over mocks that reproduce collaborator behavior, when that boundary owns
the risk. Retain distinct lower-level invariants and failure modes. Correct
ledger mistakes found during this pass.

Done when every lane plan names retired files, a keeper per contract,
assertions to transfer, and test-only production seams unlocked.

## 5. Cutover

Edit lane by lane. Give shared harness and support-file changes one owner to
avoid conflicting edits. Transfer assertions before deleting their old tests.
Remove the obsolete test-only production seams each lane unlocks, including
injection parameters, getters, reset exports, and unnecessary indirection.

Update existing CI routing and test inventories for moved suites. If the
repository maintains size budgets, update them without weakening their gates.
Record durable test-ownership rules in existing scoped guidance only when
needed to explain the new ownership; avoid adding policy or tracking systems
for speculative future use.

Done when every lane plan is applied and each lane's keepers pass, with any
unchanged baseline failures tracked separately.

## 6. Preservation review

Compare deleted coverage with the keepers, preferably using independent
reviewers per boundary group. If they are unavailable, perform a separate
self-review pass and disclose that limitation. Look for contracts that lost
their only proof and new assertions that cannot fail, such as a rejection case
the production code never reaches.

For every restored contract, deliberately mutate its production owner and
confirm the keeper fails for the intended reason. Use an isolated working copy
or a reversible patch; preserve existing user changes. Restore the source
exactly and confirm the keeper passes again.

Before mutation:

- [ ] The intended failure and its keeper are identified.
- [ ] The starting source state is saved and restoration is scoped safely.
- [ ] No test process is using the files being modified.

Done when every reported gap is restored or rejected with source evidence,
every restored contract catches its mutation, and all temporary changes are
removed.

## 7. Product defects

A meaningful baseline failure that survives into a keeper needs diagnosis.
Distinguish product defects from environment or harness failures. Repair
confirmed product defects at their owner within the authorized scope, isolated
from pruning edits, preferably in a separate commit when commits are authorized.

Prove a repair through the real flow using the same harness for a **control**
without the fix and a **candidate** with it. The control must fail for the
intended reason and the candidate must pass. Use a safe isolated comparison,
not a destructive restore of the user's checkout. Record unrelated or
out-of-scope defects as follow-ups rather than expanding the campaign.

Done when every baseline failure has a disposition and each repaired defect
has failing-control and passing-candidate evidence.

## 8. Reconcile and hand off

Refresh against the current target branch using the repository's authorized
merge or rebase policy. If upstream changed a retired file, inspect the new
contract before resolving the conflict. Transfer new coverage into the keeper
when the deletion remains valid; revisit the plan if ownership has changed.
Confirm every new upstream regression has a test owner.

Rerun the whole subsystem suite and applicable integration or live proof on
the reconciled revision. Large diffs can truncate review-tool output: verify
the full file inventory was reviewed. Resolve gate findings with evidence or
authorized exceptions, not by weakening checks.

Done when upstream coverage is reconciled, final validation is recorded, and
no unexplained coverage gap or temporary mutation remains. Explicitly label
blocked campaigns as incomplete.

Hand off with the [SKILL.md](SKILL.md) report, plus:

- baseline and final test/support line counts, with production counted separately;
- lanes, retired layers, and keepers;
- preservation gaps found and mutation results;
- product defects with control and candidate proof;
- unresolved blockers, deferred findings, and the final tested revision.
