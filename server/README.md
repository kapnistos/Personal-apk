# Hub server (Windows laptop)

The laptop stays on and does the jobs a phone cannot do alone.

| Job | Status |
| --- | --- |
| Proton Mail on the phone (Bridge runs here, phone connects over Tailscale) | Ready, run the setup script |
| Private network between phone and laptop (Tailscale) | Ready, run the setup script |
| Sync notes, tasks, calendar and wallet between phone and PC | Ready: Me → Sync in Hub |
| Automatic bank sync through Enable Banking | Planned |

## Setup

1. Copy this folder to the laptop.
2. Open PowerShell **as Administrator** in this folder and run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\setup-hub-server.ps1
   ```

3. Answer the questions. Each step asks before changing anything.

Nothing is opened to the internet: the Bridge ports only accept connections
from devices in your own Tailscale network (100.64.0.0/10).

## How sync works

Hub on the laptop is the server ("Server" in Me → Sync). Every other
device points at the laptop's Tailscale address with the sync key it shows.
Each change carries the time it was made, and the newest edit wins. Deletions
sync too. Mail accounts and passwords never leave the device they were added on,
and subscribed calendars are downloaded by each device itself.
