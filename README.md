# isaac-sim-workspace

Daily driver for running **NVIDIA Isaac Sim 6.0.1 on a Brev GPU instance** and driving it
remotely from a local Claude Code agent. Your scene work lives here in Git (source of truth);
the cloud instance is disposable.

## Architecture
```
Local Mac (Claude Code agent)
  │  isaacctl.sh  +  /isaac-* slash commands
  │  SSH tunnel  localhost:8226  ──────────────┐
  ▼                                            ▼
Brev instance "isaac-sim" (g6e.2xlarge, 1x L40S)
  Isaac Sim 6.0.1 container (docker compose, project "isim")
    • python_server  :8226  ← remote Python control (via tunnel)
    • WebRTC viewer  :8210  ← you watch here (public IP, ports opened in Brev console)
```
Scenes are saved as `.usda` (text, git-friendly) — heavy assets are *referenced* from NVIDIA's
asset server, not embedded, so snapshots stay tiny and diffable.

## Daily use (slash commands from Claude Code)
| Command | What it does |
|---|---|
| `/isaac-up` | Start (or create) the instance, tunnel in, **resume your last scene**. Prints the viewer URL. |
| `/isaac-save [name]` | Stop sim → export scene → copy back → **git commit + push** (default name `latest`). |
| `/isaac-resume [name]` | Reopen a saved scene (default: last / `latest`). |
| `/isaac-status` | Instance + tunnel + Isaac Sim health + viewer link. |
| `/isaac-shot [name]` | Capture a viewport screenshot into `captures/` and show it. |
| `/isaac-send <code>` | Run arbitrary Python inside the running Isaac Sim. |
| `/isaac-down` | Auto-save, then `brev stop` (fast resume next time; small storage cost). |
| `/isaac-teardown` | Auto-save, then `brev delete` ($0 when off; full ~20-40 min rebuild next time). |

Or run the script directly: `bin/isaacctl.sh {up|save|resume|status|shot|send|down|teardown|tunnel}`.

## Layout
```
bin/isaacctl.sh            the driver (all logic)
scenes/                    saved .usda snapshots (committed — your work history)
scripts/                   helper Python (capture, save, compose-patch)
skills/isaac-sim-remote/   vendored remote-control skill (isaacsim_send.py + refs)
captures/  logs/  state/   local runtime artifacts (gitignored)
```

## First-time / new-machine setup
1. `git clone <this repo> ~/isaac-sim`
2. Ensure `brev` CLI is installed and logged in (`brev login`), and the `isaac-*` commands are in `~/.claude/commands/`.
3. `/isaac-up` — creates the instance if none exists (one-time ~20-40 min), then resumes.
4. In the Brev console, open ports **8210 / 49100 / 47998** to your IP so the viewer stream loads.

## Notes / gotchas (Isaac Sim 6.0.1)
- Use **pure USD Physics** (the old `isaacsim.core.api` `World` is deprecated and its `reset_async` is buggy here).
- Read prim poses via `omni.usd.get_world_transform_matrix` (not `xform.get_world_pose` → warp-array error).
- Capture via `scripts/capture_viewport.py` (the skill's screenshot scripts need a `test.utils` module not present in the streaming app).
- The instance's **public IP changes on every start** — `isaacctl.sh up` recomputes it and re-ups the container; the viewer URL is new each day.
