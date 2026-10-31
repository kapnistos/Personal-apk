# Changelog

Builds are numbered by the CI run. Notable changes, newest first.

## October 2026

### Home layout fixes
- The ask bar and the tab bar are one frosted panel, so apps no longer peek through between them.
- A small widget alone on its row takes its wide form instead of leaving half the row empty.
- The Edit home button is now on the left and your profile picture on the right.
- Small widgets keep their figure in the middle of the card, and Home scrolls far enough that the last widget clears
  the bottom bar, in Edit home too.

### Your tabs, an agent that can change things, and 22 fixes
- **Choose your bottom tabs**: pick which tabs sit next to Home (Calendar, Wallet, To-do, AI, Notes), drag them into
  order and choose the tab Hub opens on. Hold the bar, or go to Me > Navigation.
- **Top of Home**: switch the greeting, weather card, Today strip and apps on or off, show apps grouped or as one
  grid, and drag apps into your own order.
- **Text size**: Standard, Larger or Largest on top of your phone's own setting. The black dark background is now
  called True black.
- **The Hub agent can change things**: edit, reschedule or delete tasks and events, add to or rewrite notes, edit
  recurring payments, add savings deposits, set your monthly budget, log Job hours, add important dates to a space
  and tick habits. Every change is a card with what it was before; deletes are red. **Add all** for several cards,
  and **Undo** after any of them.
- **Ask AI from inside apps**: Explain my month (Wallet), Plan my week (Calendar), Prioritise (To-do), Summarise
  (Notes).
- Home and Wallet always agree on what is left to spend. The Work widget shows overtime or hours owed. The Clock
  widget opens Calendar.
- Fixes: edits in the task, shopping and event sheets are no longer lost when you swipe them away or press back;
  date pickers no longer crash on old or far-off dates; Undo always undoes the last thing; "Clear all" done tasks
  asks first; Duplicate keeps a task's details; an all-day event's start no longer jumps to 23:00; new events start
  on the hour; mail dates show the year when needed; several sheets no longer overflow with large text or the
  keyboard up; the Job + button no longer covers the day counts; Wallet scrolls under the glass bar.

### Wallet tab, an agent that knows your data, Job hours
- **Wallet is a tab** next to Home, Calendar, To-do and AI. Back from any tab goes to Home; back on Home closes the app.
- **Am I on track?** Wallet's "Day by day" card: a bar per day, no-spend days, safe to spend today, where the month will
  end, and bills still to come. Rent and other recurring bills count as fixed costs, so an early-month rent payment
  no longer looks like overspending. Savings goals with a deadline say whether you are ahead or behind plan.
- **The Hub agent sees everything**: calendar for any dates (all calendars, repeats, all-day events), recurring
  payments and subscriptions, transactions, balances, savings, investments, notes, tasks with or without dates,
  habits, shopping, spaces, work log and weather. Changes still wait for your tap on Add.
- **Chat history**: every conversation is kept, with a History page to reopen, search, rename or delete them.
- **Token usage**: per message, per conversation, and totals for today, this month and all time, with cost for
  OpenRouter models.
- **Job hours**: hours worked or planned per day (or start and end times), contract hours per week or per weekday,
  and an overtime balance or hours still owed for the week, month and year.
- **Edit home, reworked**: tap or hold anywhere on a widget, Done sits at the bottom, one damaged widget no longer
  resets the whole layout, and Weather shows a "Choose a city" card instead of an empty slot.
- **Widgets open their app after resizing**: at Medium and Large the whole card opens Wallet, Tasks, Habits and so
  on, not just the small link in the corner.
- The ask bar on Home uses the same see-through glass and font as the tab bar.

### Fixes
- Empty screens scroll instead of overflowing on small phones.

### Simpler AI tab, and OpenRouter
- The AI tab is now the chat itself: a Chat or Hub agent switch, the conversation and a box to type in. A small model chip at the top opens AI settings. There is a Stop button while it thinks, a copy button under each answer, and a New chat button.
- OpenRouter: one key, any model. Paste any API key and Hub works out whose it is (OpenRouter, Anthropic, OpenAI, DeepSeek or Groq), checks it and is ready. With OpenRouter you pick from its live model list, with prices, and a few suggestions on top.
- Busy or rate-limited providers are retried once or twice before Hub shows a plain message.
- Claude Code (your Claude plan) is now in both builds.

### Claude plan through Claude Code
- Personal build only: AI chat, the Hub agent and the shopping price check can use your own Claude plan through Claude Code, on your computer or on the laptop running Hub in Server mode. If it cannot be reached, Hub opens the Claude app instead.

### iPhone
- Hub now builds for iPhone. The release has an unsigned `Hub.ipa` you install with Sideloadly or AltStore and a free Apple ID, no paid developer account.
- Reminders work on iPhone too; Hub asks for notification permission the first time you set one.

### Taps and more
- Every tap on Home lands: the gaps between app and shortcut rows used to swallow taps, and holding an app tile now starts editing Home instead of only showing a tooltip.
- Shortcuts open their apps more reliably on Android 11 and newer.
- AI chat remembers your last conversation, offers starter suggestions and can use a short summary of your day if you allow it.
- Search also finds recurring payments, saved space items, shopping and habits, and remembers recent searches.
- Optional end-of-day summary, and a tidier settings page with an About section.

### AI that works
- Two ways to pay: your subscription (through the Claude app, no API cost) or your own API key for Anthropic, OpenAI, DeepSeek or Llama. Keys live only in secure storage, with a test button and plain error messages.
- AI chat and a Hub agent: say "12 euro lunch" or "note: call the landlord" and confirm the cards it proposes.
- Shopping price check runs in the app with an API key.

### Fixes and polish
- Repeating tasks no longer duplicate; notes no longer double-save; calendar events right on clock-change days; notification taps open the right page.
- Wallet: no double saves, recurring payments booked once, cents kept on edit, "1.234,56" style numbers parse.
- Flatter cards, sliding pill toggles, quiet loading placeholders, no overflow on small phones or with large text.

### Spaces, customization and polish
- Spaces: make your own sections with a name, icon and colour; each gets dates, meetings, a plan, saved items and its own calendar, and appears on Home. Choose which apps Home shows.
- Home: widgets move out of the way as you drag, undo after removing, live previews in the gallery, new Month, Countdown and Focus widgets.
- Appearance: six accent colours, black or dark grey background, compact spacing, hide the greeting.
- To-do: hold a task to move it to today, tomorrow or next week, duplicate or delete; undo after ticking; sort options; quick add shows what it understood.
- Notes: hold a card to pin, recolour, copy or delete; list or grid; sort options.
- Habits: hold for a month view and tick any past day.
- Wallet: budgets on track or over, search, swipe to delete, spending patterns, upcoming bills strip, price-change notes, "remind me to cancel", save on payday.
- Faster start and lighter redraws; fixes for Weather and Mail spinners, calendar times on clock-change days, and small-screen overflows.

### AI tab and easier editing
- AI replaces Me in the bottom bar. Settings now open from your profile picture on Home.
- AI tab: what works today (shopping price check, Claude) and what is coming: DeepSeek, a model picker with a recommendation for each, your own API key, a Hub agent and personal agents.
- Hold any Home widget to start editing; controls now sit above each widget instead of covering it. Resetting the layout asks first.

### Wallet targets
- Monthly spending target: what is left, a daily allowance, whether you are on pace, bills still to come, no-spend days.
- Net worth across cards, savings and investments; round-ups into a savings goal; categories compared with your usual month.

### New look
- Black background in dark mode, flat cards without outlines, pill-shaped tabs and filters, round icons.
- Big balances with smaller cents; Wallet opens on the month's net figure with round Add, Recurring, Year and Import buttons.
- Plain sentence-case headings instead of small capitals.

### Automations, backup and habits
- Automations (Me → Automations): morning briefing, bill reminder the evening before, low-balance warning two days ahead, Sunday week review, overdue-task nudge, habit reminders. Each can be switched off or retimed.
- Backup (Me → Backup): save everything to a file, restore it on any device, and an automatic daily copy kept for two weeks.
- New Habits app and Home widget: daily or chosen days, streaks, 30-day rate, reminders.
- A fresh install starts with your open tasks as well as your recurring list.
- Small vibrations when ticking tasks and shopping items.

### Home and shortcuts
- Home is now a dashboard. Hold a widget to resize, reshape, restyle, recolour, move or remove it; add from 18 widget types.
- Shortcuts widget: open X, Instagram, Reddit, TikTok, GitHub, LinkedIn, Outlook, Gmail, banks or any link in one tap.

### Shopping
- New Shopping list: one line of input, items sorted by the cheapest shop for their kind, editable rules, remembered choices, and a Claude check for current prices.

### Wallet
- Bank cards with balances, monthly in and out, next payment and per-card recurring payments.
- Starter list of recurring payments, restorable from Recurring → "Add back my usual list".
- Savings goals and an investment portfolio with live prices.
- Month picker with "Now", swipe between months, year overview, CSV export.

### Planning
- Job and University spaces with dates, meetings, plans and saved items; Job has a work-day log.
- To-do: quick add in plain words, repeating tasks, Done and Snooze from the notification.
- Notes: colours, checklists, masonry layout.
- Calendar: swipe between periods and an endless agenda.

### Everything else
- News with General, Netherlands, Greece, Politics, AI, Tech, Investing, Economy, Sports and Science.
- Weather place picker and "use my location"; Buienradar for the next hours, Google Weather optional.
- Larger, cleaner text throughout.
- Fixed: daylight-saving days shifting dates; stale months showing in Wallet; Today missing items.
