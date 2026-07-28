---
description: Run Python code inside the running Isaac Sim (remote-control)
argument-hint: <python code>  |  --file <path> [--arg k=v ...]
allowed-tools: Bash(/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh:*)
---
Execute Python inside the running Isaac Sim via the remote-control tunnel.

The user's request: $ARGUMENTS

Run it through `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/bin/isaacctl.sh send ...`, passing the user's code or `--file`/`--arg` options straight through (quote inline code as a single argument). For anything non-trivial, prefer writing a small script under `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/scripts/` and sending it with `send --file ...`.

Follow the `isaac-sim-remote` skill's API conventions and known 6.0.1 pitfalls (pure USD Physics; read poses via `omni.usd.get_world_transform_matrix`; capture via `/Users/shauryatiwari/Desktop/Projects/gits/isaac-sim-workspace/scripts/capture_viewport.py`). Report the output. If the tunnel is down the script auto-opens it; if that fails, suggest `/isaac-up`.
