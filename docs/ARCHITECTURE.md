# Architecture

## Code layout

```
lib/
  main.dart               App start: database, settings, notifications, routes from notifications
  core/
    db/database.dart      drift tables, migrations and queries (one file, generated part in database.g.dart)
    db/my_recurring.dart  The owner's starting list of recurring payments (empty in the public copy)
    sync/                 Sync schema (triggers), engine (merge) and service (HTTP client and server)
    reminders.dart        Local notifications for tasks, events and applications
    settings.dart         Settings stored in the database, plus free-form "raw" keys
    theme.dart            Colours (Palette), typography and component themes
    format.dart           Dates (DST-safe), money, repeats
    widgets.dart          Shared widgets: Section, ContentWidth, EmptyState, AppGlyph, undo snackbars
  shell/
    shell.dart            Bottom navigation (phone) or navigation rail (desktop)
    home_page.dart        Greeting and the dashboard host
    dashboard.dart        Home widgets: layout model, editing, gallery and every widget
    shortcuts.dart        App shortcut catalogue and launcher
  apps/
    registry.dart         The mini-apps on the home screen
    <app>/                One folder per mini-app (weather, calendar, todo, notes, wallet, shopping,
                          spaces, news, mail, claude)
test/                     Unit, widget and migration tests
screenshots/              Golden tests that render the README screenshots from demo data
server/                   Windows laptop setup script for sync and Proton Mail Bridge
```

## Data

All data is in one SQLite database (`hub.sqlite` in the app's support folder), accessed through
[drift](https://drift.simonbinder.eu/). The schema version is in `AppDatabase.schemaVersion`; every
version step has a migration in `onUpgrade`, and `test/migration_test.dart` upgrades a real database from an
older version (`test/fixtures/`) to make sure updates keep data.

Main tables:

| Area | Tables |
| --- | --- |
| Notes, tasks | `notes`, `todos` |
| Calendar | `calendars`, `events` |
| Wallet | `entries`, `subscriptions`, `budgets`, `accounts`, `savings_goals`, `savings_moves`, `holdings` |
| Spaces | `spaces`, `space_items`, `work_days` |
| Other | `applications`, `shopping_items`, `cities`, `mailbox_accounts`, `settings` |

Settings that do not need their own column (home layout, news sources, shop rules, selected weather place)
are JSON strings under "raw" keys in `settings`, for example `home.layout`, `news.sources`,
`shopping.cheapest`, `weather.city`.

## Sync

Sync works without any cloud service:

1. **Triggers** (`lib/core/sync/sync_schema.dart`) add three hidden columns to every synced table:
   `gid` (a global id shared by all devices), `modified` (when a person last edited the row) and `srv`
   (when this database last changed it). Deletes leave a tombstone.
2. **The engine** (`sync_engine.dart`) sends rows changed since the last sync and applies incoming rows when
   they are newer. Foreign keys travel as gids, so ids can differ per device.
3. **The service** (`sync_service.dart`) is a small HTTP server on port 8787 on the device you choose as
   server, and a client on the others. A shared sync key authorises requests. The intended network is
   Tailscale, so nothing is exposed to the internet.

Rows that every install creates (the starter calendars, spaces and bank cards) get fixed gids so two
devices merge them instead of duplicating.

## Notifications

`lib/core/reminders.dart` schedules local notifications with `flutter_local_notifications`:

- Task reminders with **Done** and **Snooze** actions, exact alarms where allowed.
- Event reminders, including repeats (only the next occurrences are scheduled, and the schedule is rebuilt
  when data changes).

Tapping a notification opens the right page.

## Home dashboard

`lib/shell/dashboard.dart` stores the layout as a list of `DashItem`s (type, size, shape, style, colour, and
for shortcuts, the chosen apps). Sizes map to spans of a 2-column grid on phones and a 6-column grid on wide
screens. `DashFrame` applies shape, style and colour by overriding the card theme for the widget inside it,
so existing cards pick up the look without knowing about the dashboard.

## External services

All are free and need no account unless noted. See [PRIVACY.md](PRIVACY.md) for what is sent.

| Service | Used for |
| --- | --- |
| Buienradar | Rain in the next two hours |
| Open-Meteo | Forecast and place search |
| Google Weather (optional, your key) | Forecast |
| BigDataCloud | Place name for "use my location" |
| Yahoo Finance chart API | Investment prices and exchange rates |
| Public RSS feeds | News |
| Microsoft identity platform | Outlook sign-in |
| Claude app / claude.ai | Opening Claude with a prompt (no API) |
