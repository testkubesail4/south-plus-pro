# Forum Task Quick Claim RCA

Date: 2026-06-17

## Observed Facts

- The forum task pages have three relevant states:
  - `plugin.php?H_name-tasks.html.html`: new/available tasks.
  - `plugin.php?H_name-tasks-actions-newtasks.html.html`: in-progress tasks.
  - `plugin.php?H_name-tasks-actions-endtasks.html.html`: completed rewards.
- On the available page, daily and weekly tasks can show cooldown text such as:
  - `周常 ... 上次领取未超过 158 小时`
  - `日常 ... 上次领取未超过 18 小时`
- Cooldown text on the available page is not a claim failure by itself. It means the task is not currently available to start.
- The completed page showed daily reward completed:
  - `日常 ... 已完成 100 % 完成时间 2026-06-17 AM:11:37:46`
- The in-progress page showed weekly task still waiting for reward claim:
  - `周常 ... 奖励 : SP币 7 G`
  - `无所事事的周常 ... 已完成 100 %`
  - Reward action HTML:

```html
<a style="cursor:pointer" onclick="startjob('14');" title="领取此奖励">
  <img src="hack/tasks/image/god.png">
</a>
```

## Verified Runtime Result

On 2026-06-17, the real browser was used to click the weekly in-progress reward action once.

Before clicking:

- Completed page had only `日常`, completed at `2026-06-17 AM:11:37:46`.
- Available page showed:
  - `周常 ... 上次领取未超过 158 小时`
  - `日常 ... 上次领取未超过 18 小时`
- In-progress page showed:
  - `周常 ... 已完成 100 %`
  - `title="领取此奖励"`
  - `onclick="startjob('14')"`

After clicking:

- Completed page showed `周常`, completed at `2026-06-17 PM:13:28:02`.
- Completed page still showed `日常`, completed at `2026-06-17 AM:11:37:46`.
- In-progress page was empty.
- Available page still showed cooldown rows for both daily and weekly tasks.

Conclusion: the completed page is the authoritative confirmation after a reward action. The available page cooldown remains present after success and must not be treated as a failed claim result.

## 2026-06-17 Recheck

The real in-app browser was used again after the weekly reward was claimed.

- New/available page:
  - `周常 ... 奖励 : SP币 7 G ... 上次领取未超过 158 小时`
  - `日常 ... 奖励 : SP币 2 G ... 上次领取未超过 18 小时`
  - No `startjob(...)` action buttons were present on either row.
- In-progress page:
  - Header: `您在进行中任务`
  - Body: `你无任何进行任务`
- Completed page:
  - `周常 ... 已完成 100 % 完成时间 2026-06-17 PM:13:28:02`
  - `日常 ... 已完成 100 % 完成时间 2026-06-17 AM:11:37:46`

In this state the correct one-click result is `本周期任务奖励已领取`. The client must not call the job endpoint for weekly or daily rewards because there is no runnable action on the page and both tasks are already confirmed in completed history.

## What Was Wrong

The implementation mixed up two different concepts:

1. `available` page cooldown is a state signal, not a one-click claim result.
2. `in-progress` task at `100%` with `title="领取此奖励"` is still actionable and must be claimed before the whole flow is complete.

As a result, one-click claim could surface the weekly cooldown message:

```text
周常距离上次领取没超过158小时
```

even while the real actionable state was on the in-progress page:

```text
周常 已完成 100%，领取此奖励
```

That is poor UX and incorrect task semantics.

## Root Cause

The one-click flow treats cooldown rows from the available page as user-facing output.

Current problematic behavior:

- Fetch in-progress tasks.
- Try to claim rewards from parsed in-progress tasks.
- Fetch available tasks.
- Collect available-page cooldowns into `ForumTaskQuickClaimResult.cooldowns`.
- If nothing was claimed, show a snackbar like `任务处于冷却中：周常 158h 后`.

This is wrong because cooldown and completed/in-progress state describe the same task cycle from different pages. Cooldown should update local state, not become a scary result toast.

There is also a parsing/adaptation risk:

- The weekly reward button has no visible text.
- The action exists in `title="领取此奖励"` and `onclick="startjob('14')"`.
- Any parser or UI logic that relies on visible link text or `href` will miss it.

## Correct Model

Task state should be merged by task name across pages:

- `completed` and `coolingDown` both mean the reward has already been handled for the current cycle.
- `inProgress + progressPercent >= 100 + actionLabel contains 领取` means reward is claimable.
- `available + actionLabel contains 申请` means task can be started.
- `available + cooldownRemaining != null` means not startable now; it should not be treated as a failure.

Priority should be:

1. Claimable in-progress reward.
2. Available task that can be started.
3. Completed/cooling down state.
4. Empty/no action.

## Expected One-Click Flow

Manual one-click should respect the user's explicit action and must fetch the forum state. The local cache is for display and passive auto-refresh throttling only; it must not prevent a manual claim attempt.

Production flow:

1. Fetch completed tasks first.
2. Fetch new/available tasks.
3. Build target names from the known daily/weekly tasks.
4. Treat a task as pending when it is not in completed history, or when the available page explicitly shows a fresh `按这申请此任务` action. This handles the next-cycle case where old completed history can still exist while a new task is available.
5. Start only pending tasks whose action label is an application action.
6. If a task cannot be started and is not completed, or if any task was just started, fetch the in-progress page.
7. Claim only in-progress tasks that have `领取此奖励` or `已完成 100 %`.
8. Re-fetch completed and available pages after any action that may have changed server state.
9. Treat available-page cooldowns and action-endpoint cooldown replies as handled state, not user-facing failures.

## Production State Matrix

| Completed page | Available page | In-progress page | Correct behavior |
| --- | --- | --- | --- |
| Daily/weekly present | Cooldown rows, no actions | Empty | Show already handled; do not call job endpoint |
| Missing a task | `按这申请此任务` | Empty | Start that task, then fetch in-progress and claim if reward action appears |
| Old completion exists | `按这申请此任务` for the same task | Empty | Treat as a new cycle and start it |
| Missing a task | Cooldown/no start action | `领取此奖励` or 100% | Claim reward from in-progress |
| Missing a task | Cooldown/no start action | Task exists but <100% | Show in-progress, no failure |
| Missing a task | Cooldown/no start action | Empty | Treat cooldown as handled state |
| Any state | Job endpoint says task already received | Fetch in-progress and continue |
| Any state | Job endpoint says reward already received/completed | Treat as handled and refresh pages |
| Any state | Job endpoint says cooldown / distance from last claim | Treat as handled/cooling state, not a failure toast |
| Any state | Login/permission HTML from endpoint | Surface a real failure and let login/session flow handle it |

## Expected User Messages

Good messages:

- `日常奖励领取完成SP+2`
- `周常奖励领取完成SP+7`
- `任务奖励已领取`

Bad messages for the one-click button:

- `任务处于冷却中：周常 158h 后`
- `周常距离上次领取没超过158小时`
- `任务申领失败：距离上次申领没超过168小时`

Cooldown may be shown as secondary status text, but not as a failure toast.

## Regression Checks To Add

- Parser test: in-progress weekly task with `onclick="startjob('14')"` and `title="领取此奖励"` is parsed as claimable even when link text is empty.
- Repository test: if in-progress weekly is 100% claimable and available page says weekly cooldown, one-click claims weekly reward and does not show cooldown as final result.
- Repository test: if completed history plus available cooldown shows both tasks handled, one-click does not call the job endpoint.
- Repository test: if available page shows a fresh start action while completed history still has an old record, one-click treats it as a new cycle.
- Repository test: action endpoint cooldown such as `任务申领失败：距离上次申领没超过168小时。` is not surfaced as a failure toast.
- Repository test: non-claimable in-progress tasks are reported as in-progress instead of failed.
- UI test: snackbar never displays available-page cooldown as an error or primary one-click result.

## Key Lesson

Do not use the available task page as the source of truth for reward completion. It is only one projection of the task cycle. The in-progress page owns claimable reward actions, and the completed page owns reward completion history.
