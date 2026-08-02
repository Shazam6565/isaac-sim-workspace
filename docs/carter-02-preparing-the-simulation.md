# Preparing the Simulation — Carter, adapted for Isaac Sim 6.0.1

Adaptation of NVIDIA's [Preparing the Simulation](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/02-preparing-the-simulation.html)
lesson. The published lesson documents **Isaac Sim 4.2 and 4.5 only**. We run **6.0.1**, and
several menu paths and UI field names have moved since 4.5.

Every 6.0.1 path below was verified by reading the Isaac Sim source at
`/mnt/data/isaacsim/IsaacSim/source/extensions` (version `6.0.1-rc.7`) — from the extensions'
own menu registrations and UI test suites, not from documentation. Anything I could not verify
is marked **unverified**.

---

## Learning objectives

The lesson's five stated objectives, and what each is actually teaching:

1. **Construct a simulation environment** — adding a ground plane and physics.
   *Why it matters:* a robot with no ground and no physics scene is inert geometry. Physics in
   USD is opt-in; gravity, collision and solver settings all come from a `PhysicsScene` prim.

2. **Examine Carter's joints and their configuration.**
   *Why it matters:* a URDF's joints become USD `PhysicsRevoluteJoint` prims. Which axis they
   rotate on, which two bodies they connect, and whether they have a *drive* determines whether
   the robot can be actuated at all. This is the concept that bit us on `SimpleRobot` — joints
   without a `DriveAPI` are free-spinning hinges no controller can command.

3. **Simulate motion to validate the physics setup.**
   *Why it matters:* pressing Play is the cheapest correctness test you have. A robot that sinks,
   explodes, or drifts tells you the mass, collider or joint setup is wrong before you invest in
   controllers or sensors.

4. **Add a differential controller driven by the keyboard.**
   *Why it matters:* differential drive converts a single (linear, angular) velocity command into
   two wheel speeds. It's the standard abstraction for two-wheeled ground robots, and the same
   OmniGraph pattern generalises to ROS 2 `/cmd_vel` control.

5. **Modify velocity limits for realistic motion.**
   *Why it matters:* the physical limit lives in the *joint drive*, while the commanded limit
   lives in the *controller*. Understanding which one is clamping you is a recurring debugging
   skill.

---

## Version deltas — what changed since the lesson was written

| Action | 4.2 | 4.5 | **6.0.1 (ours)** |
|---|---|---|---|
| Open URDF importer | `Isaac Utils > Workflows > URDF Importer` | `File > Import` | **`File > Import`** ✔ |
| Add ground plane | `Create > Isaac > Environments > Flat Grid` | `Create > Environments > Flat Grid` | **`Create > Environments > Flat Grid`** ✔ |
| Differential controller | `Isaac Utils > Common OmniGraphs > Differential Controller` | `Tools > Robotics > OmniGraph Controllers > Differential Controller` | **`Tools > Robotics > OmniGraph Controllers > Differential Controller`** ✔ |

✔ = verified in 6.0.1 source.

`Create > Environments > Flat Grid` creates the prim at **`/FlatGrid`**, referencing
`/Isaac/Environments/Grid/default_environment.usd`.

### The big one: the importer no longer imports into your stage

In 6.0.1 the URDF importer (`isaacsim.asset.importer.urdf-3.11.2`) has **no option to add the
robot to the currently open stage**. Its complete config is:

```
urdf_path              usd_path               ros_package_paths
merge_fixed_joints     merge_mesh             fix_base
collision_type         collision_from_visuals allow_self_collision
joint_drive_type       joint_target_type      link_density
override_joint_damping override_joint_stiffness
robot_type             run_asset_transformer  run_multi_physics_conversion
```

There is no `make_default_prim`, no "add to stage". The importer's job is URDF → a **standalone
USD asset**, which it then opens — replacing whatever stage you had. Older versions injected
directly into the open stage, which is what the lesson assumes.

**So import is two steps in 6.0.1, not one:** import to an asset, then *reference* that asset
into your working stage.

---

## Step 0 — Get Carter into your stage

The lesson assumes Carter is already imported (that's lesson 01). Do this first.

Asset locations already staged for us:

| Machine | Path |
|---|---|
| Brev instance | `/isaac-sim/.local/share/ov/data/carter/urdf/carter.urdf` (persistent) |
| `instrux` box | `/home/instrux/Documents/carter/urdf/carter.urdf` |

### 0.1 Import

1. **`File > Import`**
2. Select `carter.urdf`
3. Set **`ros_package_paths`** to the **parent** of `carter/` — e.g. `/home/instrux/Documents`

   > **Do not skip this.** Carter's URDF references meshes as
   > `filename="package://carter/meshes/chassis.obj"`. No ROS package named `carter` is
   > registered, so without this the robot imports with correct joints and **no visible
   > geometry**.

4. **`Base Type` → `Mobile`** — **not** "Fix Base Link unchecked"; that control does not exist
   in 6.0.1. `Base Type` is a tri-state dropdown:

   | Dropdown | `fix_base` | Result |
   |---|---|---|
   | `Source` (default) | `None` | honours the URDF. Carter's is fixed-base → you get a world-anchored `root_joint` that **welds the robot in mid-air** |
   | `Fixed` | `True` | adds the world joint *and* relocates the articulation root |
   | **`Mobile`** | `False` | removes the world-to-root fixed joint → floating base ← **use this** |

5. Leave everything else at defaults
6. Import — this writes a USD asset and opens it as its own stage

> **Joint target types cannot be set at import in 6.0.1.** The lesson says to set
> `left_wheel`/`right_wheel` → Velocity and `rear_axle`/`rear_pivot` → None during import.
> `joint_target_type` exists in `UrdfImporterConfig` but has **no widget** in the import
> dialog. Same for `collision_type` and the drive stiffness/damping overrides. All of these
> must be fixed on the stage after import — see
> [`carter-worklog.md`](./carter-worklog.md) sections 2 and 4.

### 0.2 Reference it into your working stage

Open (or create) the stage you actually want to work in, then:

1. Select `/World` in the Stage panel
2. Add the produced `carter.usd` as a **reference** (`Create > Reference`, or drag the `.usd`
   from the Content browser onto `/World`)

You should end up with `/World/carter` in *your* stage, environment intact.

---

## Step 1 — Build the environment

1. **`Create > Environments > Flat Grid`** → creates `/FlatGrid`
2. In **Stage**, find **Environment Light** and click its **eye icon** to hide it
   *(the Flat Grid brings its own lighting; two light rigs wash the scene out)*
3. At the top of the viewport, open the **eye icon → Show By Type → Physics → Colliders → None**
   *(hides collider wireframes so you can see the robot)*

## Step 2 — Position Carter above the ground

1. Select `Carter` in **Stage**
2. Move it **up on Z** so it sits clear of the grid — it must not intersect the ground plane

   > Interpenetrating colliders at t=0 make the solver eject the robot violently on Play.
   > A small gap is correct; the robot should *drop* a short distance and settle.

## Step 3 — Confirm physics is live

1. Press **Play** (left toolbar)
2. Carter should fall and land on the grid

If it falls forever, there's no ground collider. If it doesn't move at all, either the base is
fixed or there's no `PhysicsScene`.

> **This is the step that actually bit us.** Carter sat frozen in mid-air with no errors,
> because `root_joint` (a `PhysicsFixedJoint` whose `body0` is the non-rigid-body
> `/World/carter`) anchors the chassis to the **world**. That's the `Base Type = Source`
> consequence from Step 0.1. Fix: uncheck **Joint Enabled** on `root_joint`, or re-import with
> `Base Type = Mobile`. Full measurements in
> [`carter-worklog.md`](./carter-worklog.md) section 3.

## Step 4 — Inspect the joints

Select each joint under Carter and read its properties.

| Joint | Axis | Body 0 | Body 1 | Role |
|---|---|---|---|---|
| `left_wheel` | Y | `chassis_link` | `left_wheel_link` | driven |
| `right_wheel` | Y | `chassis_link` | `right_wheel_link` | driven |
| `rear_pivot` | Z | `chassis_link` | `rear_pivot_link` | passive (caster swivel) |
| `rear_axle` | — | `rear_pivot_link` | `rear_wheel_link` | passive (caster roll) |

The two drive wheels rotate about **Y**; the caster swivels about **Z**. The passive joints have
no damping and target type `None` — they're free to follow, which is what makes the caster work.

## Step 5 — Drive it open-loop

1. In **Stage**, select **both** `left_wheel` and `right_wheel`
2. Set **Target Velocity = 20** on both
3. **Play** → Carter drives forward
4. Set `left_wheel` Target Velocity to **0** → Carter turns, caster swivelling to follow

This is differential steering demonstrated by hand, before automating it.

## Step 6 — Fix the articulation root

The lesson flags this for 4.2. **Check it on 6.0.1 too** — if the root is on `chassis_link`
rather than the top-level xform, the controller will misbehave.

1. Select `chassis_link` → find **Articulation Root** in Properties → remove it (red **X**)
2. Right-click the top-level `Carter` xform → **Add > Physics > Articulation Root**
3. In its properties, **disable Self Collisions Enabled**

> Self-collision on a wheeled base makes wheels collide with the chassis they're joined to,
> producing jitter or a locked robot.

## Step 7 — Add the differential controller

**`Tools > Robotics > OmniGraph Controllers > Differential Controller`**

The 6.0.1 window's field labels differ from the lesson's, and **two fields are new**:

| Field (exact 6.0.1 label) | Value | Notes |
|---|---|---|
| `graph path` | leave default | where the OmniGraph is created |
| `Robot Prim` | `Carter` (top-level xform) | must be the articulation root from Step 6 |
| `wheel radius` | **0.24** | metres. From the collision geometry of `left_wheel_link` |
| `distance between wheels` | **0.62** | metres. `left_wheel_link` Y position `0.31` × 2 |
| `Left Joint Name` | `left_wheel` | |
| `Right Joint Name` | `right_wheel` | |
| `Left Joint Index` | leave **-1** | **new in 6.0.1** — `-1` means unset, use the name |
| `Right Joint Index` | leave **-1** | **new in 6.0.1** |
| *checkbox* | **use keyboard** — enable | gives WASD control |
| *checkbox* | add to existing graph | leave off for a fresh graph |

Note the lesson calls these "Wheel Radius" and "Wheel Distance"; in 6.0.1 they read
**`wheel radius`** and **`distance between wheels`**. The Joint Index fields don't exist in the
lesson at all — leave both at `-1` so the joints resolve by name.

## Step 8 — Tune the speed limits

Press **Play** and drive with **W A S D**. If it's twitchy:

- **`maxLinearSpeed`** → `0.2` m/s
- **`maxAngularSpeed`** → `0.2` m/s

(4.2 used `0.5`; 4.5 lowered it to `0.2`. Start at `0.2` — **unverified for 6.0.1**, tune to feel.)

**Verify:** select `chassis_link`, watch **Rigid Body** properties, hold **W**, and confirm
velocity plateaus at your limit.

---

## What we learned

**Physics is opt-in and layered.** Geometry, collider, rigid body, joint, drive and articulation
root are separate pieces. Missing any one produces a different failure: no collider → falls
through; no drive → free-spinning; wrong articulation root → controller can't find joints.

**A joint without a drive cannot be actuated.** The `DriveAPI` is what a controller writes
velocity targets into. Carter's URDF creates drives on the wheel joints because we set target
type `Velocity` at import — which is why Step 0.1's target-type settings matter later.

**Passive joints are a design choice.** The caster's `rear_pivot` and `rear_axle` deliberately
have *no* drive. They follow the robot's motion, which is what makes differential steering
produce a turn instead of a skid.

**Differential drive is a coordinate transform.** The controller converts
`(linear, angular)` → `(left wheel ω, right wheel ω)` using only wheel radius and wheel
separation. Wrong radius or separation gives a robot that turns the wrong amount — it will still
*move*, so the error is easy to miss.

**Two different limits can clamp your speed.** The controller's `maxLinearSpeed` clamps the
*command*; the joint drive's max force clamps the *physical* torque. Diagnosing "why won't it go
faster" means knowing which is binding.

**Version drift is the real tax.** Three of this lesson's UI paths moved between 4.2 and 6.0.1,
and the importer's core behaviour changed from in-place import to asset-plus-reference. Reading
the shipped source (`source/extensions/**/tests/test_menu.py` registers exact menu paths) is
faster and more reliable than trusting docs for a version this new.

---

## Gotchas specific to our setup

**Save often.** Isaac Sim has crashed twice on this instance (`restarts=2`), each time with a
minidump and no warning. Anything unsaved is lost. `/isaac-save` commits and pushes.

**Watch which scene you're saving to.** `state.json` drives the target. `/isaac-save <name>`
to be explicit.

**`/isaac-sim/Documents` does not persist on the Brev box.** It's inside the container, which is
recreated every `/isaac-up` when the public IP changes. Use
`/isaac-sim/.local/share/ov/data/...` (bind-mounted) for anything that must survive.

**Scroll-zoom can black or white out the viewport.** Kit scales zoom steps by
`omni:kit:centerOfInterest`; it compounds and flings the camera past the far clip plane. Fix:
select a prim, hover the viewport, press **F**.

**RViz needs a display.** The Brev instance is headless — `ros2 topic echo` works over SSH, RViz
does not. The `instrux` box has Chrome Remote Desktop, so RViz works there.

---

## Sources

- [Preparing the Simulation — NVIDIA](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/02-preparing-the-simulation.html)
- [Importing URDF Assets — NVIDIA](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/01-importing-urdf-assets.html)
- [URDF Importer Extension — Isaac Sim](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/py/source/extensions/isaacsim.asset.importer.urdf/docs/index.html)
- [Commonly Used OmniGraph Shortcuts — Isaac Sim](https://docs.isaacsim.omniverse.nvidia.com/latest/omnigraph/omnigraph_shortcuts.html)
- Isaac Sim `6.0.1-rc.7` source: `isaacsim.gui.menu`, `isaacsim.robot.wheeled_robots.ui`,
  `isaacsim.asset.importer.urdf.ui` (menu registrations + test suites)
