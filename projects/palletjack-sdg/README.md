# Palletjack SDG (Isaac Sim 6.0.1)

Synthetic data generation for warehouse palletjack detection, adapted from
[NVIDIA-AI-IOT/synthetic_data_generation_training_workflow](https://github.com/NVIDIA-AI-IOT/synthetic_data_generation_training_workflow).

Upstream pins `isaac-sim:2022.2.1` and `tao-toolkit:4.0.0-tf1.15.5`. This version
runs on the **Isaac Sim 6.0.1** container already on the `isaac-sim` box, so
there's no second image to pull and no second GPU to pay for.

## Why it was ported rather than run as-is

- **`omni.isaac.kit` no longer exists.** Renamed to `isaacsim.*` in Isaac Sim 4.5;
  `Semantics.SemanticsAPI` became `LabelsAPI` in 5.0.
- **The L40S is Ada (sm_89).** TAO 4.0 is TensorFlow 1.15 on CUDA 11.8, whose
  shipped cubins stop at sm_86. Train with PyTorch instead (see below).

## Verified working

Confirmed live in the viewer on 2026-08-13 — 12 frames, KITTI output, varied
per-frame bounding boxes:

```
sdg_out2/Camera/{rgb, object_detection, semantic_segmentation,
                 instance_segmentation, semantic, depth}

frame 0 : [0 320 318 543] [392 0 528 106] [780 39 891 165] [0 40 75 221] ...
frame 4 : [693 0 959 127]
frame 10: [246 125 575 303] [26 155 157 263] [341 166 418 249] ...

palletjack 0.00 0 0.00  435 0 793 271  0.00 0.00 0.00 0.00 0.00 0.00 0.00
```

Six palletjacks load with `{'class': ['palletjack']}` labels, and the writer's
`semantic_filter_predicate` correctly emits *only* palletjack rows — no warehouse
props leak into the labels.

**Not yet re-run headless** with the final fixes. `run_sdg.sh` should work, but
the last full headless run predates the `send_og_event` fix.

## Port map

Every replacement was verified present in the 6.0.1 container before use.

| Upstream (2022.2.1) | Here (6.0.1) |
|---|---|
| `from omni.isaac.kit import SimulationApp` | `from isaacsim import SimulationApp` |
| `omni.isaac.core.utils.nucleus` | `isaacsim.storage.native` |
| `omni.isaac.core.utils.stage` | `isaacsim.core.utils.stage` |
| `pxr.Semantics.SemanticsAPI` traversal | **deleted** — writer-side filter |
| `semantics=[("class", "palletjack")]` | `semantics={"class": ["palletjack"]}` |
| `rep.trigger.on_frame(num_frames=N)` | `rep.trigger.on_custom_event("randomize")` |
| `orchestrator.run()` + busy-wait | `send_og_event()` + `orchestrator.step()` |
| `rep.WriterRegistry.get("KittiWriter")` | unchanged |

### 1. `update_semantics()` deleted

Upstream traversed the stage stripping the semantics API off every non-palletjack
prim. That schema is gone, and the workaround is unnecessary — `KittiWriter` now
takes `semantic_filter_predicate`:

```python
writer.initialize(output_dir=out, omit_semantic_type=True,
                  semantic_filter_predicate="class:palletjack")
```

### 2. The orchestrator hang

`rep.orchestrator.run()` + `while not get_is_started(): app.update()` spins
forever in Replicator 1.13 — ~130% CPU, GPU idle, nothing written.
`run_until_complete()` hangs identically. Isaac Sim 6.0.1's own samples
(`/isaac-sim/standalone_examples/replicator/scene_based_sdg/`) step explicitly:

```python
rep.orchestrator.step(delta_time=0.0, rt_subframes=16)
```

Note `step()` is standalone-only; inside a live Kit session use `step_async()`.

### 3. Randomizers must be event-driven

Under explicit stepping with `delta_time=0.0` the frame counter never advances,
so **`on_frame` triggers never fire**. Symptom: every frame renders an identical
bounding box. Fix — register on a custom event and fire it per frame:

```python
with rep.trigger.on_custom_event(event_name="randomize"):
    ...randomizers...

for i in range(n):
    rep.utils.send_og_event("randomize")
    rep.orchestrator.step(delta_time=0.0, rt_subframes=16)
```

### 4. `--materials` is off by default

Replicator 1.13's `_get_last_exec_attrs` walks the graph downstream of each
attaching node with **no visited-set** — its only cycle guard is
`conn.get_node() != cur_node`, which catches self-loops but not convergent paths.
Cost therefore explodes with chain depth. Upstream chains nine randomizers under
one trigger; attaching the ninth (`rep.randomizer.materials` on `SM_Wall`) never
returns. Confirmed by `py-spy`:

```
_get_last_exec_attrs   (replicator/core/scripts/utils/utils.py:494)
_attach_scheduled_exec (utils.py:663)
main                   (palletjack_sdg.py:331)
```

Camera + object pose randomization (a shallow chain) attaches instantly. Material
and lighting randomization is therefore behind `--materials`. To use it, add the
randomizers incrementally and watch for the attach stalling.

### 5. `--headless` bug

Upstream declared it `type=bool`, so `--headless False` parsed as `True`. Now
`--headless` / `--no-headless`.

## Running headless

```bash
brev copy ./projects/palletjack-sdg isaac-sim:/home/ubuntu/
brev exec isaac-sim "chmod +x ~/palletjack-sdg/run_sdg.sh"
brev exec isaac-sim "~/palletjack-sdg/run_sdg.sh"                    # 20-frame smoke test
brev exec isaac-sim "NUM_FRAMES=2000 DISTRACTORS=warehouse  ~/palletjack-sdg/run_sdg.sh"
brev exec isaac-sim "NUM_FRAMES=2000 DISTRACTORS=additional ~/palletjack-sdg/run_sdg.sh"
brev exec isaac-sim "NUM_FRAMES=1000 DISTRACTORS=None       ~/palletjack-sdg/run_sdg.sh"
```

| Var | Default | Meaning |
|---|---|---|
| `NUM_FRAMES` | `20` | frames to render |
| `DISTRACTORS` | `warehouse` | `warehouse`, `additional`, `None` |
| `WIDTH`/`HEIGHT` | `960`/`544` | resolution |
| `OUT_DIR` | `~/palletjack-sdg/data` | host output dir |

`run_sdg.sh` mirrors the volume layout in
`IsaacSim/tools/docker/docker-compose.yml` so the Nucleus asset cache is shared.

## Running live in the viewer

`./bin/isaacctl.sh up`, then drive it with `send`. Inside Kit, use the **async**
orchestrator API:

```python
import asyncio, omni.replicator.core as rep
async def run(n):
    for i in range(n):
        rep.utils.send_og_event("randomize")
        await rep.orchestrator.step_async(delta_time=0.0, rt_subframes=16)
    await rep.orchestrator.wait_until_complete_async()
asyncio.ensure_future(run(12))
```

Write to `/isaac-sim/.local/share/ov/data/<name>`, which is bind-mounted to
`~/docker/isaac-sim/data/<name>` on the host.

## Known artifact

At low `rt_subframes` the bottom half of each frame renders black — the hydra
texture hasn't resized before capture. `rt_subframes=16` (the default here)
resolves it. If you see half-black frames, raise it.

## Training

Don't use the TAO TF1.15 container on Ada. Options, easiest first:

- **Ultralytics YOLO** — a few GB, native sm_89, reads KITTI with a small
  conversion script. Best fit for a small project.
- **TAO 5.x/6.x** — if you want DetectNet_v2 specifically. Supports Ada; the
  upstream spec files need updating.

## Disk

The box is 117GB and **cannot be resized** — Brev exposes no resize command
(`create`/`delete`/`ls`/`search`/`reset`/`start`/`stop` only). ~34GB was
reclaimed by removing unused host CUDA toolkits; `cuda-13.2` is the only one
left and is the active one (`/usr/local/cuda` → it, plus `nvcc`). Original
PATH/LD_LIBRARY_PATH is saved at `/etc/profile.d/dlami.sh.bak`.

Unrelated pre-existing issue: `~/.cache/ov/hub` is owned by uid 1000 but the
container runs as 1234, so OmniHub can't cache asset downloads and first loads
are slow. Fix with `sudo chown -R 1234:1234 ~/.cache/ov/hub`.
