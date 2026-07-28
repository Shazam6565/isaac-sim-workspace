---
description: Spin up the Isaac Sim Brev instance and resume your last scene
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*), Read
---
Bring the Isaac Sim environment up for today's session.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh up` **in the background** (duration varies: ~2-4 min if the instance was stopped, ~20-40 min if it was torn down and must be rebuilt). Poll the background output until you see the `✅ Isaac Sim is UP` banner or an error.

Then report to the user:
- The **viewer URL** (`http://<ip>:8210`) and the reminder that ports **8210 / 49100 / 47998** must be open to their IP in the Brev console for the stream to load.
- Whether the **last scene was resumed** and its name.
- That the **control tunnel** (localhost:8226) is up, so you can now drive the sim with `/isaac-send` or the `isaac-sim-remote` skill.

If it fails, show the relevant error lines and suggest `/isaac-status`.
