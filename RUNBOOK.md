# Runbook — getting Isaac Sim up and seeing it in the browser

Written 2026-07-28, from an actual working run. Everything marked **verified** was observed
directly in that session; anything else is called out as suspected.

---

## TL;DR — the daily path

```
/isaac-up          # creates or starts the instance, resumes scenes/latest.usda
                   # ... work ...
/isaac-down        # auto-saves, commits, pushes, stops the instance
```

`/isaac-up` prints the viewer URL when it finishes. **Use `/isaac-down`, not `/isaac-teardown`**
— see [Down vs teardown](#down-vs-teardown-this-matters).

---

## First run, or any run after the instance was deleted

### 1. Start it

```
/isaac-up
```

Takes **20–40 min** on a cold build (the Isaac Sim container image is ~15 GB). Expected sequence:

```
pulling latest work from GitHub ...
creating isaac-sim (g6e.2xlarge) — full setup, this takes a while ...
waiting for instance to be RUNNING + shell READY ...
instance ready
cloning Isaac Sim repo (if needed) ...
patching compose to enable python_server ...
preparing cache dirs ...
launching Isaac Sim container (ISAACSIM_HOST=3.144.23.174) ...   <-- must NOT be empty
waiting for Isaac Sim (port 8226 + healthy) ...
Isaac Sim is ready
opening SSH tunnel  localhost:8226 -> isaac-sim:8226 ...
tunnel is up
health check:  ->  Health: OK
pushing scene 'latest' to instance ...
opening scene 'latest' ...

  ✅ Isaac Sim is UP
     Viewer   : http://3.144.23.174:8210
     Control  : localhost:8226 via SSH tunnel
     Scene    : latest
```

> **Watch the `ISAACSIM_HOST=` line.** If it is empty, something is already wrong.
> Don't wait out the 15 GB pull — see [ISAACSIM_HOST came back empty](#isaacsim_host-came-back-empty).

### 2. Expose the viewer ports — manual, in the Brev web console

**The Brev CLI cannot do this.** `--flex-ports` only *filters* for instance types whose rules can
be changed (`brev search` legend: `P = Flex Ports`); it opens nothing. There is no CLI verb for it.

In the Brev console, open instance `isaac-sim` → Ports / Networking → expose:

| Port | Protocol | Purpose |
|------|----------|---------|
| 8210 | TCP | WebRTC viewer page — this is the one you open in a browser |
| 49100 | TCP | signalling |
| 47998 | UDP | media |

If only 8210 is open the page loads but the stream never connects.

### 3. Open the viewer

```
http://<ip-from-the-banner>:8210
```

Verify from your machine first if it doesn't load:

```bash
nc -z -G 6 -w 6 <ip> 8210 && echo OPEN || echo CLOSED
```

---

## Do I have to expose ports every time? No.

**Verified:** firewall rules attach to the instance, so they survive a stop/start. After a full
stop/start cycle the instance record still showed `exposedPorts = ["8210","49100","47998"]`.

| What you did last | Ports next time |
|---|---|
| `/isaac-down` (stop) | **persist** — no console visit |
| `/isaac-teardown` or delete in the UI | **gone** — redo step 2 |

The **public IP changes on every start**, so the URL is new each session even when the ports stay
open. `/isaac-up` prints the current one.

---

## Down vs teardown (this matters)

| | `/isaac-down` (stop) | `/isaac-teardown` (delete) |
|---|---|---|
| Compute | $0 | $0 |
| Disk | ~$0.40/day (120 GiB @ $0.10/GB/mo) | $0 |
| Next `/isaac-up` | ~2–4 min | **20–40 min** full rebuild |
| Port rules | kept | **destroyed** |
| 15 GB image | kept | re-pulled |

Teardown saves ~40 cents a day and costs you a rebuild plus a console visit. **Prefer `down`.**

Your scenes are safe either way — `scenes/latest.usda` is committed to git and lives on your Mac.

---

## Costs

- `g6e.2xlarge`, 1× L40S, us-east-2 — **$2.69/hr** while RUNNING
- Disk 120 GiB — **$0.10/GB/month** (~$12/mo, ~$0.40/day), charged while stopped
- A cold rebuild is ~30 min of runtime ≈ **$1.35**

---

## Troubleshooting

### "opening scene 'latest' ..." then `Error: Timeout after 120.0s`

**Not a failure.** That is the *client* giving up waiting for a reply. Isaac Sim keeps loading the
USD server-side and usually finishes shortly after. Confirm before doing anything:

```bash
python3 skills/isaac-sim-remote/scripts/stage_info.py   # via isaacsim_send.py
```

A healthy `latest` looks like:

```
World (Xform)
├─ DomeLight, physicsScene, Ground
└─ SimpleRobot (Xform)
   ├─ FallingCube (Cube)
   └─ Cylinder, Cylinder_01, Cylinder_02, Cylinder_03  (each with a RevoluteJoint)
```

If you check *during* the load you may see `ValueError: No stage found` — the old stage is torn
down and the new one is not swapped in yet. Wait and re-check; that is not an error either.

### `ISAACSIM_HOST=` came back empty

```
[isaacctl] launching Isaac Sim container (ISAACSIM_HOST=) ...
```

`compose_up` gets the IP by running `curl -s ifconfig.me` **on the instance, over SSH**. Empty means
either SSH just died, or that one curl genuinely failed. Either way the container is now starting
with an empty `ISAACSIM_HOST`, so its WebRTC will advertise no host and the stream will never
negotiate — even once you know the IP. It has to be re-upped.

**Do not sit through the image pull to find out.** Check which case you're in:

```bash
brev exec isaac-sim "echo ok"
```

**If that prints `ok` — it was a transient curl failure.** Just re-run:

```
/isaac-up
```

The instance already exists and is running, so `up` takes the warm path: it recomputes the IP and
re-ups the container with the correct `ISAACSIM_HOST` (compose recreates the container when an env
var changes). Takes ~2–4 min. Any image layers already pulled are reused — the background pull
kicked off by the first attempt keeps going, so nothing is wasted.

**If it hangs or errors — SSH is dead.** Go to [SSH gateway dies](#ssh-gateway-dies) below.

Manual equivalent, if you'd rather not re-run the whole command:

```bash
IP=$(brev exec isaac-sim "curl -s ifconfig.me" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1)
echo "$IP"     # sanity-check it before using it
brev exec isaac-sim "cd ~/IsaacSim && ISAACSIM_HOST=$IP ISAAC_SIM_IMAGE=nvcr.io/nvidia/isaac-sim:6.0.1 \
  docker compose -p isim -f tools/docker/docker-compose.yml up -d"
```

### SSH gateway dies

Symptom — the gateway accepts TCP but hangs up before the SSH handshake:

```
kex_exchange_identification: Connection closed by remote host
```

`brev ls` will still cheerfully report `RUNNING / COMPLETED / READY` and `healthStatus: HEALTHY`,
because that is the cloud provider's view, not the agent's. Confirm with:

```bash
brev exec isaac-sim "echo ok"
```

`isaacctl.sh` now detects this itself: on any empty probe it calls `ssh_alive()`, and after three
consecutive strikes it aborts with `lost SSH to isaac-sim` instead of burning the full 25-minute
timeout and blaming Isaac Sim.

Recovery, in order:

```bash
brev refresh                                       # 1. refresh SSH config
brev stop isaac-sim && brev start isaac-sim        # 2. preserves the whole disk
                                                   # 3. if still dead: delete + rebuild
```

**Never `brev reset`.** It only preserves `/home/brev/workspace/`, and this setup keeps everything
in `/home/ubuntu/IsaacSim` plus the Docker image cache — reset would discard the 15 GB pull.

### Suspected: exposing ports on a *running* instance can kill SSH

**Not proven**, but it fits every observation from 2026-07-27: SSH worked normally for ~40 minutes,
then died at almost exactly the moment ports were exposed via the web console, and stayed dead
across a full stop/start (consistent with a persistent rule change, not a transient outage).

Until it's understood, sequence it this way:

1. Let `/isaac-up` finish completely and note the viewer URL from the banner.
2. **Then** expose the ports.

That way the container is already running with the correct `ISAACSIM_HOST` and the control tunnel
is already open, so even if SSH drops, the viewer keeps working.

If you hit it again, `brev feedback` is the way to report it. Useful details: instance id, region,
workspace group (`devplane-brev-1`), the `kex_exchange_identification` line, and that `brev ls`
still showed READY.

---

## Quick reference

```bash
bin/isaacctl.sh up | down | teardown | status | save [name] | resume [name] | shot [name] | send
```

| Check | Command |
|---|---|
| Is SSH alive? | `brev exec isaac-sim "echo ok"` |
| Is the viewer port open? | `nc -z -G 6 -w 6 <ip> 8210` |
| What's on the stage? | `stage_info.py` via `isaacsim_send.py` |
| Instance state | `brev ls` |
| Full status | `/isaac-status` |
