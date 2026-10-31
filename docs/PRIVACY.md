# Privacy

Hub keeps your data on your devices. There is no Hub account, no analytics and no crash reporting.

## What leaves the device, and when

| When | Sent to | What |
| --- | --- | --- |
| Weather opens or refreshes | Open-Meteo, Buienradar | The coordinates of the selected place |
| Weather with your Google key | Google Weather API | Coordinates and your key |
| "Use my location" | BigDataCloud | Your coordinates, to get the place name |
| Shopping "Best prices" | PrijsProfeet (prijsprofeet.nl) | The names of the items on your list, one search each, no account or key |
| Searching for a place | Open-Meteo geocoding | The search text |
| Investing prices refresh | Yahoo Finance | Ticker symbols you entered |
| News refreshes | Each enabled feed's website | A normal web request |
| Mail | Your mail provider (or Proton Mail Bridge) | Your login, over TLS |
| Sync | Your own sync server | Changed rows, with your sync key |
| Claude buttons | The Claude app or claude.ai | The prompt shown, only when you tap |
| Shortcuts | The app or site you tapped | Nothing from Hub |

## On the device

- The database is in the app's private storage.
- Mail passwords and tokens are in the operating system's secure storage (Android Keystore, Windows
  Credential Manager).
- Optional API keys stay in the local settings.

## The public repository

The public source contains no personal data. The starting list of recurring payments
(`lib/core/db/my_recurring.dart`) is empty there; fill it with your own if you build Hub for yourself.
