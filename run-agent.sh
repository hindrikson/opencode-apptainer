#!/usr/bin/env bash
# Usage: ./run-agent.sh [--conda | --no-conda] /path/to/project [command...]
# Starts OpenCode in the container with only the project (/workspace)
# and a dedicated agent home mounted. Pass a command (e.g. `bash`) to run
# that instead of OpenCode.
#
#   --conda      mount your conda installation + envs (read-only), no prompt
#   --no-conda   don't mount conda, no prompt
#   (neither)    ask interactively; defaults to "no" if there is no terminal
#
# Set CONDA_BASE=/path/to/conda to skip auto-detection.
set -euo pipefail

usage() {
  echo "usage: run-agent.sh [--conda | --no-conda] /path/to/project [command...]" >&2
}

CONDA_MODE=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --conda)    CONDA_MODE=yes; shift ;;
    --no-conda) CONDA_MODE=no;  shift ;;
    -h|--help)  usage; exit 0 ;;
    --)         shift; break ;;
    -*)         echo "unknown option: $1" >&2; usage; exit 1 ;;
    *)          break ;;
  esac
done

[ $# -ge 1 ] || { usage; exit 1; }
PROJECT="$(cd "$1" && pwd)"
shift
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_HOME="$HOME/agent-home"

# OpenCode writes next to its config, so copy it into the agent home
# (refreshed on every launch) instead of mounting it read-only.
mkdir -p "$AGENT_HOME/.config/opencode"
cp -f "$HERE"/opencode/*.json "$AGENT_HOME/.config/opencode/"

# Optional: API keys / proxy settings as KEY=value lines in agent.env
ENV_ARGS=()
if [ -f "$HERE/agent.env" ]; then
  chmod 600 "$HERE/agent.env"
  ENV_ARGS=(--env-file "$HERE/agent.env")
fi

# Optional: conda environments
if [ "$CONDA_MODE" = ask ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    read -r -p "Mount your conda environments (read-only)? [y/N] " reply
    case "$reply" in
      [yY]*) CONDA_MODE=yes ;;
      *)     CONDA_MODE=no ;;
    esac
  else
    CONDA_MODE=no
  fi
fi

BIND_ARGS=()
if [ "$CONDA_MODE" = yes ]; then
  CONDA_BASE="${CONDA_BASE:-}"

  # 1) ask conda itself, 2) fall back to common install locations
  if [ -z "$CONDA_BASE" ] && command -v conda >/dev/null 2>&1; then
    CONDA_BASE="$(conda info --base 2>/dev/null || true)"
  fi
  if [ -z "$CONDA_BASE" ]; then
    for d in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" \
             "$HOME/mambaforge" /opt/conda /opt/miniconda3 /opt/anaconda3; do
      if [ -x "$d/bin/conda" ]; then CONDA_BASE="$d"; break; fi
    done
  fi
  if [ -z "$CONDA_BASE" ] || [ ! -d "$CONDA_BASE" ]; then
    echo "Could not find a conda installation. Set CONDA_BASE=/path/to/conda." >&2
    exit 1
  fi

  # Conda envs contain hard-coded absolute paths (shebangs, rpaths), so mount
  # everything at the SAME path as on the host, read-only.
  BIND_ARGS+=(--bind "$CONDA_BASE:$CONDA_BASE:ro")

  # Also mount any envs dirs that live outside the conda base (e.g. ~/.conda/envs)
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    case "$d/" in "$CONDA_BASE"/*) continue ;; esac
    BIND_ARGS+=(--bind "$d:$d:ro")
  done < <("$CONDA_BASE/bin/conda" config --show envs_dirs 2>/dev/null | sed -n 's/^  - //p')

  # Make the `conda` command available inside the container
  # (APPTAINERENV_* variables survive --cleanenv)
  export APPTAINERENV_PREPEND_PATH="$CONDA_BASE/condabin"
  echo "Mounting conda from $CONDA_BASE (read-only)" >&2
fi

exec apptainer exec \
  --containall --cleanenv --no-mount cwd --writable-tmpfs \
  ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
  --home "$AGENT_HOME:/home/agent" \
  --bind "$PROJECT:/workspace" \
  ${BIND_ARGS[@]+"${BIND_ARGS[@]}"} \
  --pwd /workspace \
  --env TERM="${TERM:-xterm-256color}" \
  "$HERE/ubuntu-opencode.sif" "${@:-opencode}"
