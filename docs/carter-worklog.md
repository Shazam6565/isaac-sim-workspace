# Carter — surgical worklog (Isaac Sim 6.0.1)

Running log of the exact UI actions taken on the Carter robot, in order, with the reasoning
behind each. Format: **what → where in the UI → why → how to verify.**

Companion to [`carter-02-preparing-the-simulation.md`](./carter-02-preparing-the-simulation.md).
That file is the adapted lesson; this file is what actually happened, including the dead ends.

Machine: `instrux@100.66.183.67`, native Isaac Sim `6.0.1-rc.7`.
Everything below verified against the live stage over the remote-control port (8226).

---

## 0. The import dialog — what actually exists in 6.0.1

`File > Import` → select `carter.urdf`. The options panel on the right contains **only**:

| Group | Control | Notes |
|---|---|---|
| Model | **USD Output** | default `Same as Imported Model` |
| Model | **ROS Package List** (Package / Path rows) | this is `ros_package_paths` |
| Colliders | **Collision From Visuals** | checkbox |
| Colliders | **Allow Self-Collision** | checkbox |
| Options | **Robot Type** | dropdown, `Default` |
| Options | **Base Type** | dropdown — `Source` / `Fixed` / `Mobile` |
| Options | **Merge Mesh** | checkbox |
| Options | **Debug Mode** | checkbox |

### There is no "Fix Base Link" checkbox

The 4.2/4.5 lesson says *"Fix Base Link: unchecked"*. That control does not exist in 6.0.1.
It is now the **`Base Type`** dropdown, and it is **tri-state**, not boolean. From
`isaacsim/asset/importer/urdf/impl/config.py`:

```
fix_base: Tri-state base-type toggle.
  True   : adds a fixed joint from the world to the root rigid-body link and
           relocates ArticulationRootAPI to the correct ancestor prim
  False  : removes any existing world-to-root fixed joint so the robot becomes floating-base
  None   : leaves the source asset's base authoring untouched
```

| Dropdown | `fix_base` | Result |
|---|---|---|
| `Source` (default) | `None` | honours the URDF. Carter's URDF is fixed-base → you get a world-anchored `root_joint` |
| `Fixed` | `True` | adds the world joint **and** moves the articulation root |
| **`Mobile`** | `False` | **removes** the world-to-root fixed joint → floating base ← **use this for Carter** |

### Settings that exist in the API but NOT in the UI

These are in `UrdfImporterConfig` but have no widget in the import dialog, so they **cannot** be
set at import time through the GUI — they must be fixed on the stage afterwards:

- `collision_type` — `Convex Hull` / `Convex Decomposition` / `Bounding Sphere` / `Bounding Cube`
- `joint_target_type` — `none` / `position` / `velocity`
- `override_joint_stiffness`, `override_joint_damping`
- `link_density`, `joint_drive_type`, `merge_fixed_joints`

This is why sections 2 and 4 below exist. The lesson implies you configure per-joint target
types during import; in 6.0.1 you cannot.

---

## 1. Removed the duplicate ground

**Where:** *Stage* → select `/Environment/ground` and `/Environment/groundCollider`
(ctrl-click) → right-click → **Delete**

**Why:** `Create > Environments > Flat Grid` adds its own collider at
`/FlatGrid/GroundPlane/CollisionPlane`. Two coplanar collision planes at z=0 means PhysX
resolves contacts against both — wasted work and ambiguous physics-material ownership.

**Kept:** `/Environment/Sky` (DomeLight) and `/Environment/DistantLight`. Deleting all of
`/Environment` removes your lighting. `/FlatGrid` carries its own `SphereLight`, so full
removal is survivable but darker.

**Verify:** exactly one non-Carter collider remains in the stage.

---

## 2. Triangle-mesh colliders → Convex Hull

**Symptom:**

```
PhysX error: attachShape: non-SDF triangle mesh ... not supported for
non-kinematic PxRigidDynamic instances
Physics USD Load: ... falling back to convexHull approximation:
  /World/carter/Geometry/chassis_link/rear_pivot_link/pivot
```

**Where:** *Stage* → select the prim → *Property* → **Physics → Collider** →
**Approximation** dropdown → **Convex Hull**

**Which prims — five, not one.** PhysX names only the first failure:

```
/World/carter/Geometry/chassis_link/chassis
/World/carter/Geometry/chassis_link/left_wheel_link/side_wheel
/World/carter/Geometry/chassis_link/right_wheel_link/side_wheel
/World/carter/Geometry/chassis_link/rear_pivot_link/pivot
/World/carter/Geometry/chassis_link/rear_pivot_link/rear_wheel_link/caster_wheel
```

Ctrl-click all five and set Approximation once.

**Why:** the converter (`URDF USD Converter v0.1.3`) authors
`PhysxTriangleMeshCollisionAPI` with `physics:approximation = "none"`. Triangle meshes are
open surfaces with no interior, so PhysX cannot compute penetration depth — they are legal for
**static** bodies only. Convex hulls have a well-defined inside.

**Why the dropdown seems missing:** it only appears for prims carrying
`PhysicsMeshCollisionAPI`. Analytic shapes (`Plane`, `Cube`, `Cylinder`, `Sphere`, `Capsule`)
have no approximation — PhysX uses them exactly. Selecting `groundCollider` (a `Plane`) shows a
Collider section with **no** Approximation field. That is correct, not a bug.

**Note:** these collider prims are `Xform`s, not `Mesh`es — the converter puts the collision
APIs on the Xform that references the geometry. Don't hunt for a Mesh child.

**Verify:** the PhysX errors stop on Play.

---

## 3. The robot was welded to the world

**Symptom:** no errors, but pressing Play does nothing. Measured over 180 frames:

```
frame 30 → 180   pos = (0, 0, 0.8346)   quat = (1,0,0,0)
net drop 0.0000 m    net drift 0.0000 m
```

**Cause:**

```
root_joint  PhysicsFixedJoint  body0=/World/carter  body1=.../chassis_link
```

`/World/carter` is a plain Xform with **no `RigidBodyAPI`**. In USD physics a joint anchored to
a non-rigid-body is anchored to **the world**. So this fixed joint bolted the chassis to world
space. Gravity applied; nothing could move.

This is the `Base Type = Source` consequence from section 0.

**Fix (in-stage, reversible):** *Stage* → `carter` → `Physics` → **`root_joint`** →
*Property* → **Physics** → uncheck **Joint Enabled**

**Fix (permanent):** delete `root_joint`, or re-import with **Base Type = Mobile**

**Verify:** Play. Measured after the fix:

```
t=0        z = 0.8346
frame 40   z = 0.2408   ← landed
frame 240  z = 0.2408   ← stable
net drop 0.5938 m    XY drift 0.002 m
```

Settled chassis height `0.2408` ≈ wheel radius `0.24` — resting on its wheels. Correct.

---

## 4. Joint drives have no gains *(pending)*

**Symptom to expect:** setting `Target Velocity = 20` produces no motion at all.

**Measured:**

```
left_wheel   stiffness=None  damping=None  maxForce=None  targetVel=None
right_wheel  stiffness=None  damping=None  maxForce=None  targetVel=None
rear_pivot   stiffness=None  damping=None  maxForce=None  targetVel=None
rear_axle    stiffness=None  damping=None  maxForce=None  targetVel=None
```

`DriveAPI` is applied but every parameter is **unauthored** → defaults to stiffness 0,
damping 0 → **zero torque**, whatever the target velocity.

**Where:** *Stage* → `left_wheel` → *Property* → **Angular Drive**

| Field | Value | Why |
|---|---|---|
| **Stiffness** | `0` | non-zero makes it a *position* servo fighting the velocity command |
| **Damping** | `10000` | this **is** the velocity gain: torque ∝ damping × (target − actual) |
| **Max Force** | `1e6` | torque ceiling; a default of 0 means nothing moves |
| **Target Velocity** | `0` initially | set in section 5 |

Apply to **`left_wheel` and `right_wheel` only**. Leave `rear_pivot` and `rear_axle`
untouched — the caster must stay passive or the robot skids instead of turning.

**Units:** USD angular drives are **degrees/second**. `20` = 20 °/s ≈ 0.084 m/s with a 0.24 m
wheel. Deliberately slow.

---

## 5. Open-loop drive test *(pending)*

1. *Stage* → select `left_wheel` **and** `right_wheel` (ctrl-click)
2. *Property* → **Angular Drive** → **Target Velocity** = `20` (applies to both)
3. **Play** → drives forward
4. Select **only** `left_wheel` → Target Velocity = `0` → turns, caster swivels to follow

Differential steering by hand, before automating it.

**If nothing moves:** damping is still 0, or Max Force is 0. Those are the only two silent ways
a drive does nothing.

---

## 6. Articulation root in the wrong place *(pending)*

**Measured:** root is on `/World/carter/Geometry/chassis_link`. It must be on the top-level
`carter` xform.

1. *Stage* → `chassis_link` → *Property* → **Articulation Root** section → click the
   **red ✕ at the right edge of the section header** (the remove-component button)
2. *Stage* → right-click **`carter`** → **Add → Physics → Articulation Root**
3. Select `carter` → *Property* → **Articulation Root** → uncheck **Self Collisions Enabled**

**Why:** the articulation root declares where the kinematic tree begins. The Differential
Controller resolves joints relative to the prim you hand it — point it at `carter` while the
root sits on `chassis_link` and it will not find `left_wheel` / `right_wheel`.

**Why disable self-collision:** wheels are jointed to the chassis and overlap it. Self-collision
tests them against each other every frame → jitter or a locked robot.

**Verify:** exactly one prim in the stage carries `ArticulationRootAPI`, and it is `carter`.

---

## 7. Differential controller *(pending)*

**Menu:** `Tools > Robotics > OmniGraph Controllers > Differential Controller`

| Field (exact 6.0.1 label) | Value |
|---|---|
| `graph path` | leave default |
| `Robot Prim` | `/World/carter` (click **Add Target**) |
| `wheel radius` | `0.24` |
| `distance between wheels` | `0.62` |
| `Left Joint Name` | `left_wheel` |
| `Right Joint Name` | `right_wheel` |
| `Left Joint Index` | `-1` (unset) |
| `Right Joint Index` | `-1` (unset) |
| ☑ use keyboard | enable |
| ☐ add to existing graph | off |

**Why those numbers:** wheel radius and separation *are* the entire differential-drive
transform. Wrong values still produce motion — just the wrong turn rate, which is easy to miss.
Radius from `left_wheel_link`'s cylinder collider; separation = `left_wheel_link` Y offset
(0.31) × 2.

**Why `-1`:** the Joint Index fields are new in 6.0.1 and absent from the lesson. `-1` means
"unset, resolve by name". Supplying both a name and an index is ambiguous.

**Order matters:** section 6 must be done **before** section 7, or the controller binds to the
wrong root.

---

## Corrections made along the way

Recorded because the wrong version of each was believed for a while:

- **"Only `pivot` is affected"** — wrong. Five colliders were triangle-mesh; PhysX reports
  only the first failure it encounters.
- **"Fix Base Link: unchecked"** — that control does not exist in 6.0.1. It is the
  **`Base Type`** dropdown, tri-state, and the fix is **`Mobile`**.
- **"Set per-joint target types at import"** — not possible in the 6.0.1 import UI.
  `joint_target_type` exists in the API but has no widget.
- **Collision errors were assumed to be the reason the robot misbehaved** — they were not.
  The collider fix worked; the robot was frozen by a world-anchored `root_joint`.

---

## Method that worked

Read the shipped source rather than the docs. Isaac Sim 6.0.1 is new enough that published
documentation lags, but every extension registers its menu paths in code and asserts them in
its own tests:

```
source/extensions/isaacsim.gui.menu/**/tests/test_menu.py           exact menu paths
source/extensions/isaacsim.robot.wheeled_robots.ui/**/menu_graphs.py  exact field labels
source/extensions/isaacsim.asset.importer.urdf/**/impl/config.py      option semantics
```

And measure rather than eyeball — stepping physics for N frames and printing the chassis pose
turned "it's not behaving right" into "net drop 0.0000 m", which named the bug immediately.
