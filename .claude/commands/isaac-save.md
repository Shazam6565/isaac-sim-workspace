---
description: Save the current Isaac Sim scene and push it to GitHub
argument-hint: [scene-name]
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
Save the current Isaac Sim scene as a checkpoint.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh save $ARGUMENTS`.
- If the user provided a name it's used; otherwise it saves as `latest`.
- Note: this **stops the simulation** first so the snapshot is clean authored USD.

Report the saved file path and confirm the **git commit + push** succeeded (or surface any push error). This checkpoint is now versioned on GitHub.
