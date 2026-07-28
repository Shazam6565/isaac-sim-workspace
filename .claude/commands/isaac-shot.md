---
description: Capture a viewport screenshot of the running Isaac Sim
argument-hint: [name]
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*), Read
---
Capture what Isaac Sim is currently rendering.

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh shot $ARGUMENTS`. It prints the local PNG path under `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/captures/`.

Then **Read that PNG path** so the image is shown to the user, and briefly describe what's in frame. If the sim isn't up, tell the user to run `/isaac-up` first.
