---
description: Show Isaac Sim instance, tunnel, and health status
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
Report the current state of the Isaac Sim environment.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh status` and summarize for the user:
- Instance status (running / stopped / none) and machine type
- Whether the control tunnel (localhost:8226) is open
- Isaac Sim health (version, stage prim count, timeline state) if reachable
- The viewer URL and the last saved scene name
