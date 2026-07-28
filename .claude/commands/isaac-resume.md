---
description: Reopen a saved Isaac Sim scene (default: your last saved scene)
argument-hint: [scene-name]
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
Reopen a saved scene into the running Isaac Sim.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh resume $ARGUMENTS` (no name = the last saved scene). This pushes the scene file to the instance, sets the 6.x asset root, and opens the stage.

Report which scene was opened and its prim count. If the sim isn't up, tell the user to run `/isaac-up` first.
