#!/usr/bin/env bash
# isaacctl.sh — one-command daily driver for Isaac Sim on Brev.
# Spins the instance up (start or full create), tunnels the remote-control port,
# resumes your last scene, and saves your work to GitHub. See `isaacctl.sh help`.
set -uo pipefail

# ---------------------------------------------------------------- config
INSTANCE="isaac-sim"
TYPE="g6e.2xlarge"                       # 1x L40S, firewall-configurable
IMAGE="nvcr.io/nvidia/isaac-sim:6.0.1"
REMOTE_HOME="/home/ubuntu"
REMOTE_REPO="$REMOTE_HOME/IsaacSim"
COMPOSE_REL="tools/docker/docker-compose.yml"
PROJECT="isim"
PORT=8226                                # python_server remote-control port

ROOT="$HOME/isaac-sim"
SKILL="$ROOT/skills/isaac-sim-remote/scripts"
HELPERS="$ROOT/scripts"
SCENES="$ROOT/scenes"
CAPTURES="$ROOT/captures"
LOGS="$ROOT/logs"
STATE="$ROOT/state/state.json"
PIDFILE="$ROOT/state/tunnel.pid"
REMOTE_DATA="$REMOTE_HOME/docker/isaac-sim/data"        # host side of the volume
CONTAINER_DATA="/isaac-sim/.local/share/ov/data"        # container side (Isaac Sim sees this)

mkdir -p "$SCENES" "$CAPTURES" "$LOGS" "$(dirname "$STATE")"
[ -f "$STATE" ] || echo '{"last_scene":null,"public_ip":null}' > "$STATE"

# ---------------------------------------------------------------- ui helpers
log(){ printf '\033[36m[isaacctl]\033[0m %s\n' "$*" >&2; }
err(){ printf '\033[31m[isaacctl:ERROR]\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- state (json)
state_get(){ STATE="$STATE" python3 -c "import json,os;print(json.load(open(os.environ['STATE'])).get('$1') or '')" 2>/dev/null; }
state_set(){ STATE="$STATE" K="$1" V="$2" python3 -c "import json,os;p=os.environ['STATE'];d=json.load(open(p));d[os.environ['K']]=os.environ['V'] or None;json.dump(d,open(p,'w'),indent=2)"; }

# ---------------------------------------------------------------- brev helpers
remote(){ brev exec "$INSTANCE" "$*" 2>/dev/null; }          # run a command on the instance
inst_line(){ brev ls 2>/dev/null | grep -E "(^|[[:space:]])$INSTANCE([[:space:]])" || true; }
inst_status(){ inst_line | awk '{print $2}'; }               # RUNNING/STOPPED/... or empty
is_running(){ inst_line | grep -q RUNNING; }
is_stopped(){ inst_line | grep -q -iE 'STOPPED|PAUSED|OFF'; }
shell_ready(){ local l; l=$(inst_line); echo "$l" | grep -qw READY && ! echo "$l" | grep -q "NOT READY"; }

wait_ready(){
  log "waiting for instance to be RUNNING + shell READY ..."
  for _ in $(seq 1 40); do              # ~20 min max
    if is_running && shell_ready; then log "instance ready"; return 0; fi
    sleep 30
  done
  err "timed out waiting for instance readiness"; return 1
}

remote_ip(){ remote "curl -s ifconfig.me" | grep -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}'; }  # brev exec appends a stray instance-name line to stdout; keep only the IP

# ---------------------------------------------------------------- tunnel
tunnel_up(){ python3 -c "import socket;s=socket.socket();s.settimeout(2);s.connect(('127.0.0.1',$PORT))" 2>/dev/null; }
close_tunnel(){
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
  pkill -f "port-forward $INSTANCE" 2>/dev/null
  rm -f "$PIDFILE"
  return 0
}
open_tunnel(){
  close_tunnel
  log "opening SSH tunnel  localhost:$PORT -> $INSTANCE:$PORT ..."
  nohup brev port-forward "$INSTANCE" -p "$PORT:$PORT" >"$LOGS/tunnel.log" 2>&1 &
  echo $! >"$PIDFILE"
  for _ in $(seq 1 30); do tunnel_up && { log "tunnel is up"; return 0; }; sleep 2; done
  err "tunnel failed to open (see $LOGS/tunnel.log)"; return 1
}
ensure_tunnel(){ tunnel_up || open_tunnel; }

# ---------------------------------------------------------------- send code into Isaac Sim
send_file(){ python3 "$SKILL/isaacsim_send.py" --file "$1" "${@:2}"; }
send_skill(){ python3 "$SKILL/isaacsim_send.py" --file "$SKILL/$1" "${@:2}"; }

# ---------------------------------------------------------------- container lifecycle
wait_isaacsim(){                          # $1 = max 30s-ticks
  local max="${1:-20}" out
  log "waiting for Isaac Sim (port $PORT + healthy) ..."
  for _ in $(seq 1 "$max"); do
    out=$(remote "nc -z -w2 127.0.0.1 $PORT && echo PORT_OK; docker ps | grep isaac-sim-1 | grep -q '(healthy)' && echo HEALTHY")
    if echo "$out" | grep -q PORT_OK && echo "$out" | grep -q HEALTHY; then
      log "Isaac Sim is ready"; return 0
    fi
    sleep 30
  done
  err "timed out waiting for Isaac Sim"; return 1
}

compose_up(){                             # (re)launch container with current public IP
  local ip; ip=$(remote_ip)
  [ -n "$ip" ] && state_set public_ip "$ip"
  log "launching Isaac Sim container (ISAACSIM_HOST=$ip) ..."
  remote "cd $REMOTE_REPO && nohup env ISAACSIM_HOST=$ip ISAAC_SIM_IMAGE=$IMAGE docker compose -p $PROJECT -f $COMPOSE_REL up --build -d >$REMOTE_HOME/compose.log 2>&1 & sleep 2; echo launched" >/dev/null
}

create_instance(){                        # full cold setup (~20-40 min)
  log "creating $INSTANCE ($TYPE) — full setup, this takes a while ..."
  brev create "$INSTANCE" --type "$TYPE" --flex-ports --timeout 900 >&2 || { err "create failed"; return 1; }
  wait_ready || return 1
  log "cloning Isaac Sim repo (if needed) ..."
  remote "test -d $REMOTE_REPO || git clone --depth 1 https://github.com/isaac-sim/IsaacSim.git $REMOTE_REPO" >/dev/null
  log "patching compose to enable python_server ..."
  brev copy "$HELPERS/patch_compose.py" "$INSTANCE:$REMOTE_HOME/patch_compose.py" >/dev/null 2>&1
  remote "python3 $REMOTE_HOME/patch_compose.py"
  log "preparing cache dirs ..."
  # container runs as uid 1234 and needs ownership of ~/docker to write caches/data; the ubuntu
  # ssh user (uid 1000) also needs write access to ~/docker/isaac-sim/data so `resume` can push
  # scenes in — chown alone (owner+group 1234, no perms for others) locks ubuntu out of it.
  remote "mkdir -p ~/docker/isaac-sim/cache/main ~/docker/isaac-sim/cache/computecache ~/docker/isaac-sim/config ~/docker/isaac-sim/data ~/docker/isaac-sim/logs ~/docker/isaac-sim/pkg ~/.cache/ov/hub && sudo chown -R 1234:1234 ~/docker && sudo chmod -R o+rwX ~/docker/isaac-sim/data" >/dev/null
  compose_up
  wait_isaacsim 50                        # up to ~25 min for the 15GB image pull
}

ensure_instance(){
  local st; st=$(inst_status)
  if [ -z "$st" ]; then
    create_instance || return 1
  elif is_stopped; then
    log "instance is stopped — starting ..."
    brev start "$INSTANCE" >&2
    wait_ready || return 1
    ensure_container_started
  else
    log "instance already running"
    wait_ready || return 1
    ensure_container_started
  fi
}

# On a warm instance the image/repo/compose-patch already persist on disk;
# just re-up with the fresh public IP (it changes on every start).
ensure_container_started(){
  # self-heal: re-apply the compose patch if a fresh disk somehow lacks it
  brev copy "$HELPERS/patch_compose.py" "$INSTANCE:$REMOTE_HOME/patch_compose.py" >/dev/null 2>&1
  remote "test -d $REMOTE_REPO && python3 $REMOTE_HOME/patch_compose.py" >/dev/null 2>&1
  compose_up
  wait_isaacsim 20
}

# ---------------------------------------------------------------- git
in_git(){ git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }
has_remote(){ git -C "$ROOT" remote get-url origin >/dev/null 2>&1; }
git_pull(){ in_git && has_remote || return 0; log "pulling latest work from GitHub ..."; git -C "$ROOT" pull --ff-only -q || err "git pull failed (continuing)"; }
git_commit(){
  in_git || return 0
  git -C "$ROOT" add -A
  git -C "$ROOT" commit -q -m "$1" 2>/dev/null || { log "nothing new to commit"; return 0; }
  if has_remote; then git -C "$ROOT" push -q && log "pushed to GitHub" || err "git push failed"; fi
}

# ---------------------------------------------------------------- commands
cmd_save(){
  ensure_tunnel || return 1
  local name="${1:-latest}"
  log "saving scene '$name' (stopping sim for a clean snapshot) ..."
  send_file "$HELPERS/save_scene.py" --arg "usd_path=$CONTAINER_DATA/$name.usda" --timeout 120 || { err "save failed in Isaac Sim"; return 1; }
  remote "sudo chmod 644 $REMOTE_DATA/$name.usda" >/dev/null
  brev copy "$INSTANCE:$REMOTE_DATA/$name.usda" "$SCENES/$name.usda" >/dev/null 2>&1 || { err "copy back failed"; return 1; }
  state_set last_scene "$name"
  git_commit "save: $name ($(date '+%Y-%m-%d %H:%M'))"
  log "saved -> $SCENES/$name.usda"
}

cmd_resume(){
  ensure_tunnel || return 1
  local name="${1:-$(state_get last_scene)}"
  [ -z "$name" ] && name="latest"        # fall back to the rolling 'latest' snapshot
  [ -f "$SCENES/$name.usda" ] || { log "no saved scene '$name' to resume — starting fresh"; return 0; }
  if [ -f "$SCENES/$name.usda" ]; then
    log "pushing scene '$name' to instance ..."
    brev copy "$SCENES/$name.usda" "$INSTANCE:$REMOTE_DATA/$name.usda" >/dev/null 2>&1
  fi
  send_skill set_asset_root.py --arg asset_root=staging --timeout 60 >/dev/null 2>&1
  log "opening scene '$name' ..."
  send_skill open_stage.py --arg "usd_path=$CONTAINER_DATA/$name.usda" --timeout 120
}

cmd_up(){
  git_pull
  ensure_instance || { err "could not bring instance up"; return 1; }
  open_tunnel || return 1
  log "health check:"
  send_skill health_check.py --timeout 60 >&2 || true
  local last; last=$(state_get last_scene); [ -z "$last" ] && last="latest"
  if [ -f "$SCENES/$last.usda" ]; then cmd_resume "$last"; else log "no saved scene yet — fresh stage"; fi
  local ip; ip=$(state_get public_ip)
  cat >&2 <<EOF

  ✅ Isaac Sim is UP
     Viewer   : http://${ip}:8210   (open ports 8210/49100/47998 to your IP in the Brev console)
     Control  : localhost:$PORT via SSH tunnel — drive with /isaac-send or the isaac-sim-remote skill
     Scene    : ${last:-<none>}
EOF
}

cmd_down(){
  if is_running && ensure_tunnel; then
    log "auto-saving before stop ..."; cmd_save latest || err "auto-save failed (stopping anyway)"
  fi
  close_tunnel
  log "stopping instance (halts \$2.69/hr compute; disk kept) ..."
  brev stop "$INSTANCE" >&2 || true
  log "stopped. Run /isaac-up next time to resume."
}

cmd_teardown(){
  if is_running && ensure_tunnel; then
    log "auto-saving before delete ..."; cmd_save latest || err "auto-save failed"
  fi
  close_tunnel
  log "DELETING instance (your work is safe in GitHub) ..."
  brev delete "$INSTANCE" >&2 || true   # brev delete does not prompt; no piping needed
  state_set public_ip ""
  log "deleted. /isaac-up will rebuild from scratch and pull your scene from GitHub."
}

cmd_status(){
  echo "== Instance =="; inst_line || true; [ -z "$(inst_line)" ] && echo "(no instance)"
  echo "== Tunnel   =="; tunnel_up && echo "localhost:$PORT OPEN" || echo "closed"
  if tunnel_up; then echo "== Health   =="; send_skill health_check.py --timeout 60 || true; fi
  local ip; ip=$(state_get public_ip); [ -n "$ip" ] && echo "Viewer: http://$ip:8210"
  local last; last=$(state_get last_scene); echo "Last scene: ${last:-<none>}"
}

cmd_shot(){
  ensure_tunnel || return 1
  local name="${1:-capture-$(date +%Y%m%d-%H%M%S)}"
  send_file "$HELPERS/capture_viewport.py" --arg "output_path=$CONTAINER_DATA/$name.png" --timeout 120 || { err "capture failed"; return 1; }
  remote "sudo chmod 644 $REMOTE_DATA/$name.png" >/dev/null
  brev copy "$INSTANCE:$REMOTE_DATA/$name.png" "$CAPTURES/$name.png" >/dev/null 2>&1 || { err "copy back failed"; return 1; }
  echo "$CAPTURES/$name.png"
}

cmd_send(){ ensure_tunnel || return 1; python3 "$SKILL/isaacsim_send.py" "$@"; }

usage(){ cat <<EOF
isaacctl — Isaac Sim on Brev, daily driver

  up               Start (or create) the instance, tunnel in, resume last scene
  save [name]      Save current scene (default 'latest') -> copy back -> git commit+push
  resume [name]    Reopen a saved scene (default: last saved)
  status           Instance + tunnel + Isaac Sim health, viewer link
  shot [name]      Capture a viewport screenshot -> captures/
  send ...         Pass args straight to isaacsim_send.py (e.g. send 'print(1)')
  down             Auto-save, then brev stop (fast resume next time)
  teardown         Auto-save, then brev delete (\$0 when off; full rebuild next time)
  tunnel           (Re)open the control tunnel only
EOF
}

case "${1:-help}" in
  up)       shift; cmd_up "$@";;
  save)     shift; cmd_save "$@";;
  resume)   shift; cmd_resume "$@";;
  status)   shift; cmd_status "$@";;
  shot)     shift; cmd_shot "$@";;
  send)     shift; cmd_send "$@";;
  down)     shift; cmd_down "$@";;
  teardown) shift; cmd_teardown "$@";;
  tunnel)   shift; open_tunnel;;
  *)        usage;;
esac
