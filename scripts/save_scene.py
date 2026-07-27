# Stop the sim (so we snapshot authored USD, not runtime/warp state) then save the stage.
# Injected globals (via isaacsim_send.py --arg):
#   usd_path: str  destination INSIDE Isaac Sim (default: mounted data volume)

import isaacsim.core.experimental.utils.app as app_utils
import omni.usd

if "usd_path" not in dir():
    usd_path = "/isaac-sim/.local/share/ov/data/scene.usda"  # noqa: F841

if app_utils.is_playing():
    app_utils.stop()
    await app_utils.update_app_async(steps=30)

ctx = omni.usd.get_context()
ok = ctx.save_as_stage(usd_path)  # synchronous save-as
stage = ctx.get_stage()
n = sum(1 for _ in stage.Traverse()) if stage else 0
print(f"SAVED path={usd_path} ok={ok} prims={n}")
