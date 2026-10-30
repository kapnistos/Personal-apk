# Self-hosting

Hub has no cloud. To share data between your phone and PC, or to read Proton Mail on the phone, one
always-on computer of yours does the work. The included script sets up a Windows laptop.

## What the laptop does

| Job | How |
| --- | --- |
| Sync notes, tasks, calendar, wallet, spaces and more | Hub runs as the sync server (Me → Sync → Server) |
| Private network between your devices | Tailscale |
| Proton Mail on the phone | Proton Mail Bridge on the laptop, reachable only over Tailscale |

## Setup

1. Copy the `server/` folder to the laptop.
2. Open PowerShell **as Administrator** in that folder:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\setup-hub-server.ps1
   ```

3. Each step asks before it changes anything. The script installs Tailscale and Proton Mail Bridge with
   `winget`, forwards the Bridge ports to the Tailscale address only, opens Hub's sync port (8787) to
   Tailscale devices, and starts Hub with Windows.

4. In Hub on the laptop: Me → Sync → **Server**. It shows its address and a sync key.
5. On the phone: Me → Sync → **Connect**, enter the laptop's Tailscale address and the key.

## Safety

- Nothing is opened to the internet. Firewall rules allow only `100.64.0.0/10`, the Tailscale range.
- Every sync request needs the sync key.
- Mail passwords never sync; each device keeps its own in the system keystore.
