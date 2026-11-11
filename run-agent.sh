#!/usr/bin/env bash
# Usage: ./run-agent.sh [--conda-ro | --conda-rw | --no-conda] [/path/to/project] [command...]
# Starts OpenCode in the container with the paths listed in mounts.conf, a
# dedicated agent home, your conda installation, and (optionally) a project
# directory mounted at its original host path.
# Pass a command (e.g. `bash`) to run that instead of OpenCode.
#
# Container user and home:
#   - The user name inside the container is your host user name.
#   - The container home is /mnt/home/<user> (backed by ~/agent-home on the host).
#
# Project path:
#   - The project is mounted at the same path inside the container as on the
#     host, and the container starts in that directory.
#   - If mounts.conf has at least one usable entry, the project path is
#     optional. Without one, the container starts in /mnt/home/<user>.
#   - If mounts.conf is empty (or has no usable entries), a project path is
#     required.
#   - The first argument is treated as the project only if it is an existing
#     directory; otherwise it is treated as the start of the command.
#
# Conda (mounted automatically when found):
#   --conda-ro   mount your conda installation + envs read-only, no prompt
#   --conda-rw   mount your conda installation + envs read-write, no prompt
#   --no-conda   don't mount conda at all
#   (none)       ask whether to mount read-only or read-write; defaults to
#                read-only if there is no terminal
#   --conda      alias for --conda-ro
# If no conda installation is found, a warning is printed and conda is skipped.
# Set CONDA_BASE=/path/to/conda to skip auto-detection (an invalid path is an
# error).
#
# Extra mounts: list them in mounts.conf (next to this script), one per line:
#
#     host_path[:container_path][:ro|:rw]
#
#   - container_path defaults to host_path (same path inside as outside)
#   - mode defaults to read-only
#   - blank lines and lines starting with # are ignored
#   - a leading ~ expands to your home dir on the host side, and to
#     /mnt/home/<user> on the container side
#   - @HERE expands to the directory containing this script
# Set MOUNTS_FILE=/path/to/file to use a different list.
set -euo pipefail

usage() {
  echo "usage: run-agent.sh [--conda-ro | --conda-rw | --no-conda] [/path/to/project] [command...]" >&2
}

CONDA_ENABLE=yes
CONDA_PERM=ask   # ask | ro | rw
while [ $# -gt 0 ]; do
  case "$1" in
    --conda|--conda-ro) CONDA_ENABLE=yes; CONDA_PERM=ro; shift ;;
    --conda-rw)         CONDA_ENABLE=yes; CONDA_PERM=rw; shift ;;
    --no-conda)         CONDA_ENABLE=no;  shift ;;
    -h|--help)          usage; exit 0 ;;
    --)                 shift; break ;;
    -*)                 echo "unknown option: $1" >&2; usage; exit 1 ;;
    *)                  break ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_USER="$(id -un)"
CONT_HOME="/mnt/home/$HOST_USER"
AGENT_HOME="$HOME/agent-home"
mkdir -p "$AGENT_HOME"

# Optional project: the first argument, if it is an existing directory.
PROJECT=""
if [ $# -ge 1 ] && [ -d "$1" ]; then
  PROJECT="$(cd "$1" && pwd)"
  shift
fi

# Optional: API keys / proxy settings as KEY=value lines in agent.env
ENV_ARGS=()
if [ -f "$HERE/agent.env" ]; then
  chmod 600 "$HERE/agent.env"
  ENV_ARGS=(--env-file "$HERE/agent.env")
fi

# Extra mounts from mounts.conf: host_path[:container_path][:ro|:rw]
# Override the file location with MOUNTS_FILE=/path/to/file.
MOUNT_BIND_ARGS=()
MOUNT_COUNT=0
MOUNTS_FILE="${MOUNTS_FILE:-$HERE/mounts.conf}"
if [ -f "$MOUNTS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    # skip blanks and comments
    case "$line" in ''|'#'*) continue ;; esac

    # @HERE -> directory of this script
    line="${line//@HERE/$HERE}"

    # optional :ro / :rw suffix (default: read-only)
    mode=ro
    case "$line" in
      *:ro) line="${line%:ro}" ;;
      *:rw) line="${line%:rw}"; mode=rw ;;
    esac

    # split into host path and optional container path
    host="${line%%:*}"
    if [ "$host" = "$line" ]; then cont=""; else cont="${line#*:}"; fi

    # expand a leading ~ on the host side (-> $HOME)
    case "$host" in
      "~")   host="$HOME" ;;
      "~/"*) host="$HOME/${host#\~/}" ;;
    esac

    # container path defaults to the host path; a leading ~ means the container home
    [ -n "$cont" ] || cont="$host"
    case "$cont" in
      "~")   cont="$CONT_HOME" ;;
      "~/"*) cont="$CONT_HOME/${cont#\~/}" ;;
    esac

    case "$host" in
      /*) ;;
      *)  echo "mounts: skipping '$host' (host path must be absolute)" >&2; continue ;;
    esac
    case "$cont" in
      /*) ;;
      *)  echo "mounts: skipping '$cont' (container path must be absolute)" >&2; continue ;;
    esac
    if [ ! -e "$host" ]; then
      echo "mounts: skipping '$host' (does not exist)" >&2
      continue
    fi

    # Targets under the container home live inside the agent home (itself a
    # bind mount), so make sure the mount point exists there.
    case "$cont" in
      "$CONT_HOME"/*)
        mp="$AGENT_HOME/${cont#"$CONT_HOME"/}"
        if [ -d "$host" ]; then
          mkdir -p "$mp"
        else
          mkdir -p "$(dirname "$mp")"
          [ -e "$mp" ] || touch "$mp"
        fi
        ;;
    esac

    MOUNT_BIND_ARGS+=(--bind "$host:$cont:$mode")
    MOUNT_COUNT=$((MOUNT_COUNT + 1))
    echo "Mounting $host -> $cont ($mode)" >&2
  done < "$MOUNTS_FILE"
fi

# A project path is only required when mounts.conf provided nothing to work on.
if [ -z "$PROJECT" ] && [ "$MOUNT_COUNT" -eq 0 ]; then
  if [ $# -ge 1 ]; then
    echo "error: '$1' is not a directory. A project path is required because $MOUNTS_FILE has no usable mounts." >&2
  else
    echo "error: a project path is required because $MOUNTS_FILE has no usable mounts." >&2
  fi
  usage
  exit 1
fi

# Conda environments (mounted automatically; only the access mode is asked)
CONDA_BIND_ARGS=()
if [ "$CONDA_ENABLE" = yes ]; then
  CONDA_BASE="${CONDA_BASE:-}"
  CONDA_EXPLICIT=no
  if [ -n "$CONDA_BASE" ]; then CONDA_EXPLICIT=yes; fi

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
    if [ "$CONDA_EXPLICIT" = yes ]; then
      echo "CONDA_BASE='$CONDA_BASE' is not a directory." >&2
      exit 1
    fi
    echo "No conda installation found; skipping conda mount. (Set CONDA_BASE=/path/to/conda to specify one.)" >&2
  else
    # Ask for the access mode unless a flag already decided it.
    if [ "$CONDA_PERM" = ask ]; then
      CONDA_PERM=ro
      if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "Mount conda environments read-only or read-write? [RO/rw] " reply
        reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
        case "$reply" in
          rw|w|write|read-write|readwrite) CONDA_PERM=rw ;;
          *)                               CONDA_PERM=ro ;;
        esac
      fi
    fi

    # Conda envs contain hard-coded absolute paths (shebangs, rpaths), so mount
    # everything at the SAME path as on the host.
    CONDA_BIND_ARGS+=(--bind "$CONDA_BASE:$CONDA_BASE:$CONDA_PERM")

    # Also mount any envs dirs that live outside the conda base (e.g. ~/.conda/envs)
    while IFS= read -r d; do
      [ -d "$d" ] || continue
      case "$d/" in "$CONDA_BASE"/*) continue ;; esac
      CONDA_BIND_ARGS+=(--bind "$d:$d:$CONDA_PERM")
    done < <("$CONDA_BASE/bin/conda" config --show envs_dirs 2>/dev/null | sed -n 's/^  - //p')

    # Make the `conda` command available inside the container
    # (APPTAINERENV_* variables survive --cleanenv)
    export APPTAINERENV_PREPEND_PATH="$CONDA_BASE/condabin"
    echo "Mounting conda from $CONDA_BASE ($CONDA_PERM)" >&2
  fi
fi

# The project is mounted at the same path as on the host and becomes the
# working directory; without one, start in the container home.
PROJECT_ARGS=()
PWD_DIR="$CONT_HOME"
if [ -n "$PROJECT" ]; then
  PROJECT_ARGS=(--bind "$PROJECT:$PROJECT")
  PWD_DIR="$PROJECT"
fi

exec apptainer exec \
  --containall --cleanenv --no-mount cwd --writable-tmpfs \
  ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
  --home "$AGENT_HOME:$CONT_HOME" \
  ${PROJECT_ARGS[@]+"${PROJECT_ARGS[@]}"} \
  ${CONDA_BIND_ARGS[@]+"${CONDA_BIND_ARGS[@]}"} \
  ${MOUNT_BIND_ARGS[@]+"${MOUNT_BIND_ARGS[@]}"} \
  --pwd "$PWD_DIR" \
  --env TERM="${TERM:-xterm-256color}" \
  --env USER="$HOST_USER" \
  --env LOGNAME="$HOST_USER" \
  "$HERE/ubuntu-opencode.sif" "${@:-opencode}"
