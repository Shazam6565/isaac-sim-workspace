---
description: Auto-save your scene, then DELETE the instance (zero cost when off)
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
Tear the instance all the way down (for when you'll be away a while — pay nothing while off).

This is **destructive to the instance** (not your work): it runs `brev delete`. Your scene is auto-saved and pushed to GitHub first, so nothing is lost — but the next `/isaac-up` will do a full ~20-40 min rebuild (re-pull the 15 GB image).

Run `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh teardown`. Then confirm to the user that the scene was pushed to GitHub and the instance was deleted. If they only meant to pause billing (fast resume), remind them `/isaac-down` is the gentler option.
