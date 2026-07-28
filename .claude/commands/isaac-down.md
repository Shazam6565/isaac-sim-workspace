---
description: Auto-save your scene, then stop the instance (halts hourly billing)
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
End the session: save work, then stop the instance to halt the ~$2.69/hr compute charge.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh down`. This **auto-saves** the current scene (commits + pushes to GitHub) and then runs `brev stop` — the disk is kept, so `/isaac-up` next time is fast (~2-4 min) and your scene comes back.

Confirm to the user that the scene was saved/pushed and the instance is stopped. Note there's a small EBS storage cost while stopped; use `/isaac-teardown` to delete entirely and pay nothing when off.
