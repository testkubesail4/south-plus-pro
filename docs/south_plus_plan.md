# South Plus Rewrite Plan

## Goal
Build a mobile-first Flutter client that fully rewrites the forum experience for South Plus.

## Target Site
- Main site: https://south-plus.net/index.php
- Mobile/simple site: https://south-plus.net/simple/index.php
- Login page: https://south-plus.net/login.php
- Register page: https://south-plus.net/register.php
- Search page: https://south-plus.net/search.php
- RSS page: https://south-plus.net/rss.php

## Current Product Scope
- Login-first flow
- Mobile-friendly browsing
- Thread detail view
- Reply composer
- Later: posting, search, attachments, images, profile, favorites, notifications

## Design Inputs
- Desktop forum home: `https://south-plus.net/index.php`
- Mobile/simple forum home: `https://south-plus.net/simple/index.php`
- The mobile/simple page is the primary structure reference for layout and information hierarchy

## Structure Observed From The Site
- Desktop home shows:
  - login/register links
  - forum navigation
  - login form
  - site stats
  - announcements
  - category tables
- Mobile/simple home shows:
  - login/register links
  - latest discussion list
  - hot categories
  - section groups
  - a desktop version link

## Current App Structure
- `lib/main.dart`
  - Boots the app
- `lib/app.dart`
  - MaterialApp wrapper and theme
- `lib/features/auth/login_screen.dart`
  - Login screen
  - Entry point to the main shell
- `lib/features/home/home_shell.dart`
  - Bottom navigation shell
  - Home feed
  - Hot categories
  - Forum sections
- `lib/features/thread/thread_detail_screen.dart`
  - Thread detail placeholder
  - Reply entry point
- `lib/features/reply/reply_sheet.dart`
  - Reply composer bottom sheet
- `lib/models/forum_models.dart`
  - Forum data models
- `lib/services/forum_repository.dart`
  - Temporary mock repository for UI wiring

## Current Flutter Entry Points
- App package: `south_plus_rewrite`
- Android entry: `android/app/src/main/kotlin/com/example/south_plus_rewrite/MainActivity.kt`
- App theme and launch shell are in `lib/app.dart`

## Implemented Functionality
- App launches to a login screen
- Username/password form
- Login validation placeholder
- Main shell with bottom navigation
- Latest discussion list
- Hot forum category chips
- Section list rendering
- Thread detail navigation
- Reply composer bottom sheet
- Basic responsive layout for mobile-first screens

## UI Flow
1. Start at login
2. Optional skip into public browsing
3. Browse latest discussions
4. Open thread detail
5. Open reply composer
6. Expand later into section browsing and authenticated actions

## What Is Still Mocked
- Login does not yet talk to the real forum
- Thread lists are hardcoded sample data
- Thread detail content is placeholder text
- Reply submission is UI-only
- Category taps are not wired
 - No real cookie/session persistence yet
 - No real HTML parsing yet
 - No upload/image pipeline yet

## Next Implementation Steps
1. Build a real forum session layer
   - login request
   - cookie/session persistence
   - CSRF handling if needed
   - persist login state across launches
2. Replace mock repository with real HTML fetch + parse
   - homepage
   - section pages
   - thread list pages
   - thread detail pages
3. Implement authenticated reply flow
4. Add section navigation
5. Add search
6. Add compose/post flow
7. Add image/attachment handling
8. Add account/profile state
9. Add tests for the session layer and HTML parsing

## Notes
- Flutter is the chosen UI layer.
- The app should stay mobile-first and use the simple/mobile forum page as the structural baseline.
- The current codebase is intentionally minimal so the real network layer can be swapped in cleanly.
- The rewrite is meant to be full-client, not a WebView wrapper.
