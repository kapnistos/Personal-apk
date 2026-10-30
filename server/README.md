# Hub server (Windows laptop)

The laptop stays on and does the jobs a phone cannot do alone.

| Job | Status |
| --- | --- |
| Proton Mail on the phone (Bridge runs here, phone connects over Tailscale) | Ready, run the setup script |
| Private network between phone and laptop (Tailscale) | Ready, run the setup script |
| Sync notes, tasks, calendar and wallet between phone and PC | Ready: Me → Sync in Hub |
| Automatic bank sync through Enable Banking | Planned |
| Claude plan for AI (Claude Code on the laptop) | Ready: see below |

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

## Claude plan for AI (Claude Code on the laptop)

With **AI → AI settings → Claude Code (my plan)**, Hub answers chat,
Hub agent and shopping price checks with Claude Code's headless mode
(`claude -p`), which counts toward your own Claude Pro or Max plan's usage
limits instead of costing per question. On a desktop it runs Claude Code there;
phones send the question to this laptop over Tailscale (`POST /ai` on port
8787, with the same sync key), one question at a time.

1. Install Claude Code on the laptop using Anthropic's official instructions
   (https://code.claude.com/docs/en/setup).
2. Open a terminal and run `claude` once. Sign in with the Claude account that
   has your Pro or Max plan, then quit. Hub never sees this login or its tokens.
3. Keep Hub running on the laptop in **Server** mode (Me → Sync), and point the
   phone at it as a client.
4. In the AI tab tap the model chip, pick **Claude Code (my plan)** and tap **Test**.

If the laptop cannot be reached, or Claude Code there is missing or signed out,
Hub opens the Claude app with the question instead. When your plan's usage
limit is reached, Hub says so; it resets later.
