# Stop the sim (so we snapshot authored USD, not runtime/warp state) then save the stage.
# Injected globals (via isaacsim_send.py --arg):
#   usd_path: str  destination INSIDE Isaac Sim (default: mounted data volume)

import os

import isaacsim.core.experimental.utils.app as app_utils
import omni.usd

if "usd_path" not in dir():
    usd_path = "/isaac-sim/.local/share/ov/data/scene.usda"  # noqa: F841

if app_utils.is_playing():
    app_utils.stop()
    await app_utils.update_app_async(steps=30)

ctx = omni.usd.get_context()
stage = ctx.get_stage()
root = stage.GetRootLayer()

# save_as_stage() returns ok=True even when the write is refused, so report the two
# things that actually distinguish "nothing to write" from "could not write":
#   DIRTY    — does the root layer hold unsaved edits? (session-layer edits never persist)
#   WRITABLE — can this process (uid 1234) actually write the destination?
dirty = bool(root.dirty)
target = usd_path if os.path.exists(usd_path) else os.path.dirname(usd_path) or "."
writable = os.access(target, os.W_OK)

ok = ctx.save_as_stage(usd_path)  # synchronous save-as
n = sum(1 for _ in stage.Traverse()) if stage else 0
print(f"SAVED path={usd_path} ok={ok} prims={n} DIRTY={dirty} WRITABLE={writable}")
