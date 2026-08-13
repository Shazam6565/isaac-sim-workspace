#!/usr/bin/env bash
# Run palletjack SDG inside the Isaac Sim 6.0.1 container.
# Runs ON the Brev instance (not locally). See README.md.
#
# Volume layout mirrors tools/docker/docker-compose.yml so the Nucleus asset
# cache is shared with the main Isaac Sim stack rather than re-downloaded.
set -euo pipefail

IMAGE="${ISAAC_SIM_IMAGE:-nvcr.io/nvidia/isaac-sim:6.0.1}"
ISAAC_SIM_DATA="${ISAAC_SIM_DATA:-$HOME/docker/isaac-sim}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/palletjack-sdg}"
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/data}"

# Defaults are a SMOKE TEST. Override for a real run -- see README.
NUM_FRAMES="${NUM_FRAMES:-20}"
DISTRACTORS="${DISTRACTORS:-warehouse}"
WIDTH="${WIDTH:-960}"
HEIGHT="${HEIGHT:-544}"

SUBDIR="distractors_${DISTRACTORS}"
mkdir -p "$OUT_DIR/$SUBDIR"
# container runs as uid 1234; it must be able to write the output dir
sudo chown -R 1234:1234 "$OUT_DIR"

echo "image      : $IMAGE"
echo "frames     : $NUM_FRAMES  (${WIDTH}x${HEIGHT})"
echo "distractors: $DISTRACTORS"
echo "output     : $OUT_DIR/$SUBDIR"
echo

docker run --rm \
  --runtime=nvidia \
  --network=host \
  --user 1234:1234 \
  -e ACCEPT_EULA=Y \
  -e PRIVACY_CONSENT=Y \
  -e NVIDIA_VISIBLE_DEVICES="${GPU_DEVICE:-all}" \
  -e OMNI_KIT_ACCEPT_EULA=YES \
  -e PYTHONUNBUFFERED=1 \
  -v "$ISAAC_SIM_DATA/cache/main:/isaac-sim/.cache:rw" \
  -v "$ISAAC_SIM_DATA/cache/computecache:/isaac-sim/.nv/ComputeCache:rw" \
  -v "$ISAAC_SIM_DATA/logs:/isaac-sim/.nvidia-omniverse/logs:rw" \
  -v "$ISAAC_SIM_DATA/config:/isaac-sim/.nvidia-omniverse/config:rw" \
  -v "$ISAAC_SIM_DATA/data:/isaac-sim/.local/share/ov/data:rw" \
  -v "$ISAAC_SIM_DATA/pkg:/isaac-sim/.local/share/ov/pkg:rw" \
  -v "$HOME/.cache/ov/hub:/var/cache/hub:rw" \
  -v "$PROJECT_DIR:/workspace:ro" \
  -v "$OUT_DIR:/output:rw" \
  --entrypoint /isaac-sim/python.sh \
  "$IMAGE" \
  /workspace/palletjack_sdg.py \
    --headless \
    --height "$HEIGHT" \
    --width "$WIDTH" \
    --num_frames "$NUM_FRAMES" \
    --distractors "$DISTRACTORS" \
    --data_dir "/output/$SUBDIR"

echo
echo "=== OUTPUT ==="
find "$OUT_DIR/$SUBDIR" -maxdepth 2 -type d | head
echo "images: $(find "$OUT_DIR/$SUBDIR" -name '*.png' 2>/dev/null | wc -l)"
echo "labels: $(find "$OUT_DIR/$SUBDIR" -name '*.txt' 2>/dev/null | wc -l)"
