# Headless-safe viewport capture for the streaming Isaac Sim app.
# The skill's viewport_screenshot.py / capture_annotator.py import isaacsim.test.utils,
# which is NOT loaded in the streaming (.exp.full.streaming.kit) app. This uses the core
# viewport utility instead, which works in --no-window streaming mode.
#
# Injected globals (via isaacsim_send.py --arg):
#   output_path: str  file path INSIDE Isaac Sim (default: mounted data volume so it lands on host)

import isaacsim.core.experimental.utils.app as app_utils
import omni.kit.viewport.utility as vp_utils

if "output_path" not in dir():
    output_path = "/isaac-sim/.local/share/ov/data/capture.png"  # noqa: F841

vp = vp_utils.get_active_viewport()
if vp is None:
    print("ERROR: no active viewport")
else:
    # render a few frames so the scene is fully shaded, then capture and flush
    await app_utils.update_app_async(steps=15)
    vp_utils.capture_viewport_to_file(vp, output_path)
    await app_utils.update_app_async(steps=15)
    print("captured ->", output_path)
