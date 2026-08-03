# Adding Sensors, and Accessing a Prepared Robot — Isaac Sim 6.0.1

Combined adaptation of two NVIDIA lessons:

- [03 — Adding Sensors](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/03-adding-sensors.html)
- [04 — Accessing a Prepared Robot](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/04-accessing-a-prepared-robot.html)

The published lessons target **Isaac Sim 4.2 / 4.5**. We run **6.0.1**, and one of the
sensor menu paths in lesson 03 **no longer exists at all**.

Every 6.0.1 path below was read out of the Isaac Sim source at
`/mnt/data/isaacsim/IsaacSim/source/extensions` (version `6.0.1-rc.7`) — from extension menu
registrations and their own UI test suites, not from documentation. Anything I could not
verify is marked **unverified**.

Prerequisite: a working Carter from
[`carter-02-preparing-the-simulation.md`](./carter-02-preparing-the-simulation.md), driving
under WASD. Fixes that got us there are in [`carter-worklog.md`](./carter-worklog.md).

---

## Version deltas — read this before you start

| Action | 4.2 | 4.5 | **6.0.1 (ours)** |
|---|---|---|---|
| Add a camera | `Create > Camera` | same | **`Create > Camera`** ✔ |
| Add a lidar | `Create > Isaac > Sensors > PhysX Lidar > Rotating` | same | **GONE — use `Create > Sensors > RTX Lidar > <vendor> > <model>`** ✔ |
| Sensor assets | — | — | **`Create > Sensors > Asset Browser`** ✔ |
| Camera / depth sensors | — | — | **`Create > Isaac > Sensors > Camera and Depth Sensors > …`** ✔ |
| Flat grid | `Create > Isaac > Environments > Flat Grid` | `Create > Environments > Flat Grid` | **`Create > Environments > Flat Grid`** → `/FlatGrid` ✔ |
| Nova Carter | `Create > Isaac > Robots > Wheeled Robots > NVIDIA > Nova Carter` | `Create > Robots > Nova Carter with Sensors` | **`Create > Robots > Nova Carter with Sensors`** → `/Nova_Carter` ✔ |

✔ = verified in 6.0.1 source.

### The PhysX Lidar is no longer in the Create menu

Lesson 03 tells you to use `Create > Isaac > Sensors > PhysX Lidar > Rotating`. In 6.0.1 the
extension that would register that (`isaacsim.sensors.physx.ui`) **registers no menu path at
all**. `Create > Sensors` contains a single entry — `Asset Browser`, which just opens the
Content Browser at `/Isaac/Sensors`.

The replacement is the **RTX Lidar**, registered by `isaacsim.sensors.rtx.ui` at:

```
Create/Sensors/RTX Lidar
```

Its submenu is generated from the installed lidar config files, so it lists real hardware:

```
NVIDIA/  Debug_Rotary, Simple_Example_Solid_State
HESAI/   Hesai_XT32_SD10          ← the same XT-32 on Nova Carter
Ouster/  OS0 / OS1 / OS2 (many channel + rate + resolution variants)
```

> The legacy PhysX lidar still exists as the **command** `RangeSensorCreateLidar` (usable from
> the Script Editor), it simply has no menu entry. Prefer the RTX lidar — it is the supported
> path and it ray-traces against the actual RTX scene.

---

# Part 1 — Adding sensors to your Carter

## Learning objectives

1. **Attach an RGB camera and a lidar so the robot can perceive its environment.**
   *Why it matters:* a robot without sensors can only be driven open-loop. Sensors are what
   turn a physics toy into something you can write perception or navigation against.

2. **Position and configure sensors for accurate capture.**
   *Why it matters:* a sensor is only meaningful relative to the robot's frame. Parent it to
   the wrong prim and it won't move with the robot; place it inside the chassis and every ray
   hits the robot's own geometry.

3. **Validate through visualisation.**
   *Why it matters:* lidar beam colour and a camera viewport are the cheapest correctness test
   available. If the beams never turn red, nothing is being detected and the problem is
   placement or missing colliders — not your downstream code.

4. **Drive the robot and watch the sensors respond.**
   *Why it matters:* static sensor output proves almost nothing. Motion is what reveals wrong
   parenting, wrong axis, and sensors clipping through the floor.

---

## Step 1 — Add the RGB camera

1. **`Create > Camera`**
2. In *Stage*, **drag the new camera onto `chassis_link`** so it becomes a child
   *(for our URDF-imported robot the full path is
   `/World/carter/Geometry/chassis_link`)*
3. Rename it to **`RGB_Sensor`** (select, press `F2`)
4. Select it → *Property* → set:

| Field | Value |
|---|---|
| **Translate** | `0.1`, `0.0`, `0.33` |
| **Rotate** | `90`, `-90`, `0.0` |

> **Turn off snapping first** — the magnet icon in the viewport toolbar. With snapping on,
> your typed values get rounded to the grid increment and the camera lands slightly wrong.

**Why parent to `chassis_link` and not `carter`:** `chassis_link` is the rigid body PhysX
actually simulates. Children of it inherit its simulated transform every frame. `carter` is a
plain Xform above the articulation — a sensor there will not follow the robot's physics motion.

**Why that rotation:** a USD camera looks down its local **−Z** with **+Y** up. `(90, −90, 0)`
swings that to look **forward along the robot's +X** with **+Z** as world up. Get this wrong
and you get a sideways or upside-down image — a very common first mistake.

## Step 2 — Look through it

1. Viewport toolbar → **camera dropdown** (reads `Perspective`) → **`Cameras > RGB_Sensor`**
2. Press **Play**, drive with **W A S D**
3. Confirm the view moves with the robot — that proves the parenting is correct
4. Switch the dropdown back to **`Perspective`**

> Click once **inside the viewport** before pressing keys, or WASD goes to whichever panel has
> focus. This cost us a lot of time in lesson 02.

## Step 3 — Add the lidar (RTX, not PhysX)

1. **`Create > Sensors > RTX Lidar > NVIDIA > Debug_Rotary`**
   *(a plain 360° rotating lidar — closest to what the lesson intends. For something
   representative of real hardware use `HESAI > Hesai_XT32_SD10`, the same unit Nova Carter
   carries.)*
2. In *Stage*, **drag it onto `chassis_link`**
3. Select it → *Property* → **Translate** = `-0.05`, `0.0`, `0.42`

That height puts it above the chassis so the beams clear the robot's own body. A lidar buried
inside its own hull returns nothing but self-hits.

## Step 4 — See the beams

Select the lidar → *Property* → **Raw USD Properties** → enable **Draw Lines**
(and **Draw Points** if offered).

- **grey beam** = ray reached max range without hitting anything
- **red beam** = ray hit a collider

**A ray only registers against a collider, never against visual geometry alone.** That is why
Step 5 exists.

## Step 5 — Add obstacles

1. **`Create > Mesh > Cube`** (also Sphere, Cylinder, Cone)
2. Place several at varied distances and angles around the robot
3. Select them all (ctrl-click in *Stage*)
4. Right-click → **`Add > Physics > Rigid Body`**, then again → **`Add > Physics > Colliders`**

> The lesson says `Add > Physics > Rigid Body with Colliders Preset`. The verified 6.0.1
> right-click `Add > Physics` menu contains exactly: **Attachment, Colliders, Joint, Particle
> System, Physics Material, Rigid Body, Rigid Body Material** — no combined preset entry.
> Applying **Rigid Body** and **Colliders** separately is equivalent. There is also an
> **Apply Preset** submenu built dynamically at runtime which may contain the combined
> option — **unverified**.

**If you want obstacles that don't get shoved aside**, apply only **Colliders** and skip Rigid
Body. A collider without a rigid body is static — the lidar still sees it, but the robot can't
knock it over.

## Step 6 — Drive and observe

1. **Play**, click the viewport, drive with **W A S D**
2. Watch beams flick grey → red as obstacles come into range
3. Switch the camera dropdown to **`RGB_Sensor`** and drive again — now you're seeing what the
   robot sees
4. Return to **`Perspective`**

**If no beam ever turns red:** the obstacles have no `CollisionAPI`, or the lidar sits below
the floor plane, or its range is shorter than the distance to anything.

---

# Part 2 — Nova Carter, the prepared robot

## Learning objectives

1. **Import a production robot and compare it to one you built by hand.**
   *Why it matters:* you've now felt every manual step — colliders, drives, articulation root,
   sensor parenting. Nova Carter shows what "done properly" looks like, and the contrast is the
   actual lesson.

2. **Examine its structure and sensor suite.**
   *Why it matters:* it's a reference implementation. When your own robot misbehaves, opening a
   working one and diffing the setup is the fastest debugging tool you have.

3. **Recognise what you no longer have to do.**
   *Why it matters:* for most work you should start from a prepared asset. Hand-building is for
   learning and for robots that don't exist yet.

## Step 7 — Fresh stage

1. **`File > New`**
2. **`Create > Environments > Flat Grid`** → creates `/FlatGrid`
3. In *Stage*, click the **eye icon** next to the default environment light to hide it
   *(Flat Grid brings its own `SphereLight`; two rigs wash the scene out)*

> **Save your Carter scene first.** `File > New` discards the current stage, and an
> unsaved in-memory stage (`anon:…`) is gone for good. We lost one this way.

## Step 8 — Add Nova Carter

**`Create > Robots > Nova Carter with Sensors`**

Verified in 6.0.1: creates the prim **`/Nova_Carter`**, referencing
`/Isaac/Robots/NVIDIA/NovaCarter/nova_carter.usd`.

> First load pulls a large asset from the Omniverse content server and **can take several
> minutes**. It is not frozen. Watch RAM/VRAM while it loads — see the warning below.

The same menu also offers **Ant**, **Boston Dynamics Spot (Quadruped)**, **Franka Emika Panda
Arm**, **Humanoid**, **Quadcopter**, and an **Asset Browser** for everything else.

## Step 9 — Explore what you got for free

Expand `/Nova_Carter` → `chassis_link` in *Stage*.

| Category | What's included |
|---|---|
| Cameras | 4 × Hawk **stereo** cameras — front, left, right, back |
| Lidar (2D) | front and rear facing |
| Lidar (3D) | **XT-32** mounted on top |
| IMU | inertial measurement |
| Drive | 2 actuated front wheels |
| Passive | 2 rear caster wheels |
| Already set | materials, masses, colliders, joint drives, articulation root, ROS 1 / ROS 2 hooks |

## Step 10 — Compare against what you built

Open your Carter scene alongside it and walk the same hierarchy.

| | Your URDF Carter | Nova Carter |
|---|---|---|
| Colliders | triangle meshes → **manual** Convex Hull fix on 5 prims | correct out of the box |
| Base | `root_joint` welded it to the world → **manual** delete | floating base |
| Joint drives | `DriveAPI` applied, **all gains unauthored** → manual stiffness/damping/maxForce | tuned |
| Articulation root | present, and easy to destroy → we did | correct |
| Sensors | none — you add and aim each one | full suite, pre-aimed |
| Time to drivable | a long debugging session | one menu click |

**That table is the lesson.** Every row is something that silently produced "the robot doesn't
move" with no error message.

---

## What we learned

**Sensors must be parented to the simulated rigid body.** `chassis_link`, not `carter`. A
sensor under a non-simulated Xform stays put while the robot drives away.

**Camera orientation is a coordinate-frame problem, not a preference.** USD cameras look down
local −Z with +Y up. In a Z-up stage, aiming one forward means a real rotation — `(90, −90, 0)`
here. This is the same trap as lesson 02, where "-90 on Y" from a Y-up tutorial produced a
90°-rolled image.

**Lidar only sees colliders.** Visual geometry is invisible to physics queries. Grey beams with
obvious obstacles present almost always means missing `CollisionAPI`.

**Rigid Body and Collider are separate.** Collider alone = static obstacle the sensor sees and
the robot can't push. Both = dynamic object. Choose deliberately.

**RTX lidar replaced PhysX lidar.** The RTX sensor ray-traces the actual rendered scene, which
is why it's tied to lidar config files describing real hardware. The legacy PhysX lidar was a
simpler geometric query — still callable, but no longer surfaced.

**Prepared assets are the normal starting point.** Building Carter by hand taught the concepts;
nobody ships that way. Start from a prepared robot, and hand-build only when nothing suitable
exists.

---

## Gotchas for our hardware

**VRAM is the real limit — check before loading Nova Carter.** The `instrux` box has an
**RTX 3050 with 6 GB**, and Isaac Sim already holds ~1.8 GB of it idle. Nova Carter adds four
stereo cameras, two 2D lidars and a 32-beam 3D lidar — every active sensor costs VRAM, and each
extra viewport costs more.

```bash
./bin/isaac-mem.sh --watch 5      # run this in a terminal BEFORE the import
```

It warns below 1200 MiB free VRAM and again below 500 MiB. Typical starting point:

```
RAM   8204 / 15823 MiB    VRAM  2154 / 6144 MiB    ~3990 MiB VRAM free
```

If VRAM runs out mid-import, Isaac Sim dies without a useful message. If it gets tight: use
fewer viewports, don't enable every sensor at once, and avoid RTX path-tracing mode.

**Save often.** Isaac Sim has crashed on us repeatedly with a minidump and no warning. An
unsaved stage is `anon:…` and unrecoverable.

**Viewport focus for WASD.** `ReadKeyboardState` only sees keys when the viewport has focus.
Click the viewport image first.

**Frame with `F`, don't scroll-zoom.** Kit scales zoom steps by `omni:kit:centerOfInterest`;
it compounds and flings the camera past the far clip plane, blacking or whiting out the view.
Select a prim, hover the viewport, press **F**.

---

## Sources

- [03 — Adding Sensors](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/03-adding-sensors.html)
- [04 — Accessing a Prepared Robot](https://docs.nvidia.com/learning/physical-ai/getting-started-with-isaac-sim/latest/ingesting-robot-assets-and-simulating-your-robot-in-isaac-sim/04-accessing-a-prepared-robot.html)
- Isaac Sim `6.0.1-rc.7` source — `isaacsim.gui.menu/create_menu.py` (Robots, Environments,
  Sensors submenus), `isaacsim.sensors.rtx.ui` (`Create/Sensors/RTX Lidar`),
  `isaacsim.sensors.camera.ui`, `isaacsim.sensors.physx.ui` (no menu registration),
  `omni.physx.ui` (`Add > Physics` entries), and the extensions' own `tests/test_menu.py`
