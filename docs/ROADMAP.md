# Roadmap

What to work on next, most valuable first. Reliability comes before new features: an app you open twenty times
a day has to be right every time. Each item says why it matters and roughly how big it is (S, M or L).

## Done in the last quality pass

- Home's date, greeting and Today strip ("Next up", "Due today") keep up with the clock. Before, they stayed on
  the time the app was opened, so you could see "Good morning" in the evening.
- The weather on Home loads again when you come back to the app and every ten minutes. It also tries again
  after a first load that failed offline. Rain times that have passed are no longer shown ("Rain from 11:50" at
  13:00).
- Opening a note to read it, or tapping around in it, no longer counts as an edit. Before, the note jumped to
  the top as "edited just now".
- A note is saved as soon as the app goes to the background, so text typed just before switching apps is kept.
- Search results update when the data changes: a task ticked off in the results shows as done, and a deleted
  note leaves the list instead of opening a note that no longer exists.
- If the AI chat hits an error nobody planned for, you now see an error message. Before, your question was
  left with no answer.
- Smaller fixes: tasks under "Today" and "Tomorrow" no longer repeat that word, Notes shows a count for
  "Others" as it does for "Pinned", News explains an empty topic, and the Shopping toggles line up with the
  list.

## Next: reliability (do these first)

1. **Monthly and yearly repeats drift (M).** A task due on the 31st that repeats monthly moves to the 28th in
   February and stays on the 28th after that. The fix is to keep the original day of the month and use it for
   each new date. Old tasks need a migration, so plan it with the next schema change.
2. **Pages that stay open over midnight (S).** Habits, the Calendar's "today" marker and the dashboard's habit
   and countdown widgets work out "today" once, when they are built. Wrap them in `ClockBuilder` the way Home
   now is.
3. **Saving drafts in other editors (S).** The task, event and space-item sheets keep what you typed when you
   close them, but not when the phone closes the app in the background. Use the same save-on-pause as the note
   editor.
4. **One error style for network screens (M).** Weather, News, Shopping prices, calendar feeds and the AI each
   word and show errors in their own way. Use one small "couldn't load, try again" banner that keeps the last
   good data on screen and shows how old it is.
5. **Background sync status (S).** When syncing with your own computer fails, only the status line in Me says
   so. Show a
   quiet dot on the profile picture after a few failures in a row.

## Then: everyday comfort

6. **Pull to refresh everywhere it makes sense (S).** Calendar (subscribed calendars), Shopping (prices) and
   Spaces should refresh on pull, as News and Weather do.
7. **Undo for removing a city (S).** Tasks, notes, habits, shopping and space items can be undone. A city in
   Weather goes with one tap on its cross and can't be brought back. The city list is a sheet, so the Undo bar
   has to show above it.
8. **Quick add that understands more (M).** "next friday", "in 3 days", "every other week" and "the 15th" in
   To-do quick add, and the same parser for calendar quick create.
9. **Notes: checklist reordering and archive (M).** Drag checklist lines, and archive a note instead of
   deleting it.
10. **Search: jump to a result's place (S).** Open the calendar on the event's day, or the space tab the item
    lives in, instead of only the item.

## Later: bigger pieces

11. **Home screen widgets on Android (L).** Today, tasks and money left to spend, outside the app.
12. **Share sheet (M).** Share a link or text into Hub as a note, a task or a space item.
13. **Accessibility pass (M).** Screen reader labels on every icon button and chart, and checks at the largest
    text size on the smallest phone.
14. **Faster start on older phones (M).** Measure the time to the first frame and move more of the startup work
    after it.

## How to keep it reliable

- Every bug fix gets a test that fails without the fix (see `test/bugfix_test.dart` and
  `test/quality_pass_test.dart`).
- Date code uses `addDays`, `daysBetween` and `dateOnly` from `core/format.dart`, never `Duration(days: n)`, so
  changes to and from summer time can't shift a date.
- Network calls have a timeout and a plain-language error, and the last good data stays on screen.
