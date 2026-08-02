#!/usr/bin/env bash
# isaac-mem.sh — RAM / VRAM headroom for a running Isaac Sim.
#
# Isaac Sim dies to OOM long before it warns you, and on a small GPU the VRAM
# ceiling arrives first. This reports both, plus what is actually loaded, so you
# can tell which action is about to be the expensive one.
#
#   ./bin/isaac-mem.sh                 one-shot report
#   ./bin/isaac-mem.sh --watch 5       resample every 5s until Ctrl-C
#   ISAAC_HOST=user@host ./bin/isaac-mem.sh
#
set -uo pipefail
HOST="${ISAAC_HOST:-instrux@100.66.183.67}"
PORT="${ISAAC_PORT:-8226}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEND="$ROOT/skills/isaac-sim-remote/scripts/isaacsim_send.py"

WATCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH="${2:-5}"; shift 2 ;;
    --host)  HOST="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

c_r=$'\033[31m'; c_y=$'\033[33m'; c_g=$'\033[32m'; c_c=$'\033[36m'; c_0=$'\033[0m'

remote_report() {
  ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" 'bash -s' <<'REMOTE'
PID=$(pgrep -x kit | head -1)

# ---- system RAM (MiB) ----
read -r _ MEM_T MEM_U MEM_F _ MEM_A < <(free -m | awk '/^Mem:/{print $1,$2,$3,$4,$6,$7}')
SWAP_U=$(free -m | awk '/^Swap:/{print $3}')
SWAP_T=$(free -m | awk '/^Swap:/{print $2}')
echo "RAM_TOTAL=$MEM_T"; echo "RAM_USED=$MEM_U"; echo "RAM_AVAIL=$MEM_A"
echo "SWAP_USED=$SWAP_U"; echo "SWAP_TOTAL=$SWAP_T"

# ---- isaac process ----
if [ -n "$PID" ]; then
  echo "PID=$PID"
  echo "PROC_RSS=$(awk '/VmRSS/{print int($2/1024)}' /proc/$PID/status)"
  echo "PROC_PCT=$(ps -o %mem= -p "$PID" | tr -d ' ')"
  echo "PROC_UP=$(ps -o etimes= -p "$PID" | tr -d ' ')"
  echo "PROC_THREADS=$(awk '/Threads/{print $2}' /proc/$PID/status)"
else
  echo "PID="
fi

# ---- GPU ----
if command -v nvidia-smi >/dev/null 2>&1; then
  IFS=',' read -r GN GT GU GF GUTIL < <(nvidia-smi \
    --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu \
    --format=csv,noheader,nounits | head -1 | tr -d ' ')
  echo "GPU_NAME=$GN"; echo "VRAM_TOTAL=$GT"; echo "VRAM_USED=$GU"
  echo "VRAM_FREE=$GF"; echo "GPU_UTIL=$GUTIL"
  if [ -n "$PID" ]; then
    echo "VRAM_PROC=$(nvidia-smi --query-compute-apps=pid,used_memory \
      --format=csv,noheader,nounits 2>/dev/null | awk -F', *' -v p="$PID" '$1==p{print $2}')"
  fi
fi

# ---- OOM history: has the kernel killed anything before? ----
echo "OOM_KILLS=$(sudo -n dmesg 2>/dev/null | grep -ci 'killed process' || echo '?')"
REMOTE
}

ensure_tunnel() {   # the -L forward drops often; heal it rather than silently skipping
  nc -z -w 3 127.0.0.1 "$PORT" >/dev/null 2>&1 && return 0
  ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 -L "$PORT:127.0.0.1:$PORT" "$HOST" >/dev/null 2>&1
  sleep 2
  nc -z -w 3 127.0.0.1 "$PORT" >/dev/null 2>&1
}

stage_report() {
  [ -f "$SEND" ] || return 0
  ensure_tunnel || return 0
  python3 "$SEND" --timeout 25 <<'PY' 2>/dev/null | sed 's/^/  /'
from pxr import Usd, UsdGeom
import omni.usd, omni.timeline
stage = omni.usd.get_context().get_stage()
if stage:
    prims  = list(stage.Traverse())
    allp   = list(stage.TraverseAll())
    meshes = [p for p in prims if p.IsA(UsdGeom.Mesh)]
    pts = 0
    for m in meshes:
        a = UsdGeom.Mesh(m).GetPointsAttr()
        v = a.Get() if a else None
        if v: pts += len(v)
    payloads = [p for p in allp if p.HasAuthoredPayloads()]
    refs     = [p for p in allp if p.HasAuthoredReferences()]
    unloaded = [p for p in payloads if not p.IsLoaded()]
    print(f"prims={len(prims)} (all={len(allp)})  meshes={len(meshes)}  points={pts:,}")
    print(f"payloads={len(payloads)} (unloaded={len(unloaded)})  references={len(refs)}")
    print(f"playing={omni.timeline.get_timeline_interface().is_playing()}")
PY
}

bar() { # value max width
  local v=$1 m=$2 w=${3:-28} f
  [ "$m" -le 0 ] 2>/dev/null && { printf '%*s' "$w" ""; return; }
  f=$(( v * w / m )); [ $f -gt $w ] && f=$w; [ $f -lt 0 ] && f=0
  printf '%s' "$(printf '█%.0s' $(seq 1 $f 2>/dev/null))"
  printf '%s' "$(printf '·%.0s' $(seq 1 $((w-f)) 2>/dev/null))"
}

verdict() { # used total label
  local pct=$(( $1 * 100 / ($2>0?$2:1) ))
  if   [ $pct -ge 90 ]; then printf "%s%3d%% CRITICAL%s" "$c_r" "$pct" "$c_0"
  elif [ $pct -ge 75 ]; then printf "%s%3d%% tight%s"    "$c_y" "$pct" "$c_0"
  else                       printf "%s%3d%% ok%s"       "$c_g" "$pct" "$c_0"; fi
}

one_shot() {
  local raw; raw="$(remote_report)" || { echo "cannot reach $HOST" >&2; return 1; }
  eval "$(echo "$raw" | grep -E '^[A-Z_]+=' )"
  : "${PID:=}" "${VRAM_PROC:=0}" "${GPU_NAME:=n/a}" "${VRAM_TOTAL:=0}" "${VRAM_USED:=0}"

  echo "${c_c}== Isaac Sim memory — $HOST ==${c_0}   $(date '+%H:%M:%S')"
  if [ -z "$PID" ]; then
    echo "  ${c_r}Isaac Sim (kit) is not running${c_0}"
  else
    printf "  process   pid %-8s rss %5s MiB  (%s%% of RAM)  threads %s  up %sm\n" \
      "$PID" "${PROC_RSS:-?}" "${PROC_PCT:-?}" "${PROC_THREADS:-?}" "$(( ${PROC_UP:-0} / 60 ))"
  fi

  printf "  RAM       %5s / %-5s MiB  %s  %s\n" "$RAM_USED" "$RAM_TOTAL" \
    "$(bar "$RAM_USED" "$RAM_TOTAL")" "$(verdict "$RAM_USED" "$RAM_TOTAL")"
  printf "            %5s MiB available%s\n" "$RAM_AVAIL" \
    "$( [ "${SWAP_USED:-0}" -gt 0 ] && echo "   ${c_y}swap in use: ${SWAP_USED}/${SWAP_TOTAL} MiB${c_0}" )"

  printf "  VRAM      %5s / %-5s MiB  %s  %s\n" "$VRAM_USED" "$VRAM_TOTAL" \
    "$(bar "$VRAM_USED" "$VRAM_TOTAL")" "$(verdict "$VRAM_USED" "$VRAM_TOTAL")"
  printf "            %s   isaac %s MiB   gpu util %s%%\n" \
    "$GPU_NAME" "${VRAM_PROC:-?}" "${GPU_UTIL:-?}"

  [ "${OOM_KILLS:-0}" != "0" ] && [ "${OOM_KILLS:-?}" != "?" ] && \
    echo "  ${c_r}kernel OOM kills recorded: $OOM_KILLS${c_0}"

  local s; s="$(stage_report)"
  [ -n "$s" ] && { echo "  stage"; echo "$s"; }

  # headroom guidance
  local vfree=$(( VRAM_TOTAL - VRAM_USED ))
  echo "  ${c_c}headroom${c_0}   ${RAM_AVAIL} MiB RAM, ${vfree} MiB VRAM free"
  if   [ "$vfree" -lt 500 ];  then echo "  ${c_r}→ VRAM nearly full. Do not load assets or add viewports.${c_0}"
  elif [ "$vfree" -lt 1200 ]; then echo "  ${c_y}→ VRAM tight. Avoid a 2nd viewport, RTX path-tracing, or large USD imports.${c_0}"
  fi
  if   [ "${RAM_AVAIL:-0}" -lt 1000 ]; then echo "  ${c_r}→ RAM nearly exhausted; a crash is likely on the next big allocation.${c_0}"
  elif [ "${RAM_AVAIL:-0}" -lt 2500 ]; then echo "  ${c_y}→ RAM tight. Save your scene now.${c_0}"
  fi
}

if [ "$WATCH" != "0" ]; then
  while true; do clear; one_shot; sleep "$WATCH"; done
else
  one_shot
fi
