---
name: stop-describing-ui
description: Strip explanatory copy out of user interfaces. Use when writing, editing, or reviewing any UI text, including headings, empty states, button labels, toggle and setting descriptions, helper text, dialogs, banners, permission notices, and onboarding, and whenever a screen leans on sentences to explain what it does. Replaces descriptions of features, side effects, backend behavior, and missing capabilities with specific verbs, controls, icons, and spacing.
---

# Stop describing UI

An interface shows what the user can do. It does not explain itself. Every sentence is something the user has to read before acting, so keep a sentence only when the user would make a real mistake without it.

When writing UI, apply the rules below as you write. When reviewing UI, go through every string, apply each rule, and present the result as before and after.

## Rules

### 1. Don't describe the feature

Name the action instead. A heading, a control, and its label already say what the screen is for.

Before

```
# Projects
## No projects yet.
### Choose a GitHub repository and we'll deploy on every push.
+ New
```

After

```
# Projects
+ Connect repository
```

### 2. Use specific verbs

Pick the verb that names what actually happens, and give it the object it acts on. Avoid generic verbs such as New, Create, Manage, Set up, Configure, Go, or OK when a more precise one exists. In the example above, "New" becomes "Connect repository".

### 3. Keep only the most critical consequence

When an action has several effects, state the one that matters most and drop the rest. Effects that follow from it are implied. In a booking service that takes reservations through AI auto-replies, turning off auto-replies obviously stops reservations too.

Before

```
Turning this off stops AI auto-replies and web reservations. Customer messages are saved only to the conversation log. You can turn it back on anytime from "Replies off" in the header.
```

After

```
Temporarily turns off AI auto-replies.
```

Irreversible or destructive effects, such as deleting data, charging money, or notifying customers, are the critical consequence and always stay.

### 4. Don't describe backend behavior

Where data is stored, what gets logged, what syncs, and what runs in the background are not the user's concern. In the example above, "Customer messages are saved only to the conversation log" goes.

### 5. Don't explain undo when the same control undoes it

A toggle that turns something off also turns it back on. Explain how to undo only when undoing needs a different control or place.

### 6. Don't explain what the page already tells

The page title, navigation, and section structure carry meaning. On an Options page, the user already knows they are looking at options.

Before

```
# Other options
### Options that become available with a contract. They cannot be toggled on or off.
```

After

```
# Other
```

### 7. Don't state what doesn't exist

Don't say there are no items yet, that something can't be toggled, or that a feature isn't available, when the screen already shows it. An empty list with a clear action says "nothing here yet". A row without a toggle says "can't be toggled".

The exception is a restriction the user would otherwise try and fail at, such as an action their role can't perform. Keep it, in one short line with an icon, as in rule 9.

### 8. Show how to enable, don't write it

If something becomes available by subscribing, upgrading, connecting, or turning on a setting, put the button or toggle that does it on the screen. Don't write a sentence telling the user where to go or what to do.

Before

```
Sign up for the Pro plan to use this option.
```

After

```
[Upgrade to Pro]
```

### 9. Don't rely on text alone

Break prose into short lines, each led by an icon. Use spacing and grouping for structure.

Never use `->`, `>`, `|`, `✔️`, `!`, `→`, or `:` as separators, arrows, bullets, or emphasis. Use an icon or spacing instead.

Before

```
Searches across all stores and shows the results. Stores you don't belong to are shown as Operator, and every action records who did what in which store. You can't change applications, payment methods, or plans, or send messages to customers (replies, approving or declining tentative reservations).
```

After

```
(icon) Every action is recorded
(icon) You can't change applications, payment methods, or plans, or send messages to customers
```

Here "Searches across all stores and shows the results" goes by rule 1, "shown as Operator" by rule 6 because the UI already labels them, and the detailed record format by rule 4.

## Checklist

For each string, ask in order.

1. Does it explain what the feature is? Delete it, or turn it into a specific action label.
2. Is the verb generic? Replace it with one that names the real action and its object.
3. Does it list several consequences? Keep the most critical one.
4. Does it mention storage, logging, syncing, or other internals? Delete it.
5. Does it explain how to undo with the same control? Delete it.
6. Does the page title or navigation already say it? Delete it.
7. Does it say something is missing or unavailable? Delete it, unless the user would otherwise try and fail.
8. Does it tell the user how to enable something? Replace it with the button or toggle.
9. Is it a paragraph, or does it use symbols as separators? Split it into icon-led lines and use spacing.

If nothing is left after the checklist, leave nothing. An empty helper text slot is better than a filler sentence.
