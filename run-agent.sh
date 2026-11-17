#!/usr/bin/env bash
# Usage: ./run-agent.sh [--conda-ro | --conda-rw | --no-conda] [/path/to/project] [command...]
#
# Runs OpenCode (or the given command) in ubuntu-opencode.sif next to this script.
#   - The container home is your host home path, backed by ~/agent-home.
#   - The project (first argument, only if it is an existing directory) is mounted
#     at the same path as on the host and becomes the working directory. It is
#     optional when mounts.conf has at least one usable entry.
#   - agent.env (next to this script) must set PROVIDER_URL and API_TOKEN.
#   - Conda is mounted at its host path when found: --conda-ro (alias --conda),
#     --conda-rw, or --no-conda. With no flag you are asked (default: read-only,
#     also used when there is no terminal). Set CONDA_BASE=/path to skip detection.
#   - Extra mounts go in mounts.conf, one per line:
#         host_path[:container_path][:ro|:rw]
#     container_path defaults to host_path, mode defaults to ro, '#' starts a
#     comment, a leading ~ means your home, @HERE means this script's directory.
#     Set MOUNTS_FILE=/path/to/file to use a different list.
set -euo pipefail

usage() { sed -n '2,/^set /{/^set /!s/^# \{0,1\}//p}' "$0"; }
die() {
  echo "error: $*" >&2
  exit 1
}

CONDA_PERM=ask # ask | ro | rw | no
while [ $# -gt 0 ]; do
  case $1 in
  --conda | --conda-ro) CONDA_PERM=ro ;;
  --conda-rw) CONDA_PERM=rw ;;
  --no-conda) CONDA_PERM=no ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    usage >&2
    die "unknown option: $1"
    ;;
  *) break ;;
  esac
  shift
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_HOME="$HOME/agent-home"
mkdir -p "$AGENT_HOME"

# Optional project: first argument, if it is an existing directory.
PROJECT=""
if [ $# -ge 1 ] && [ -d "$1" ]; then
  PROJECT="$(cd "$1" && pwd)"
  shift
fi

# Required settings. Values are parsed, never sourced, so nothing gets executed.
ENV_FILE="$HERE/agent.env"
[ -f "$ENV_FILE" ] || die "$ENV_FILE not found. Create it with your PROVIDER_URL and API_TOKEN."
chmod 600 "$ENV_FILE"
for pair in PROVIDER_URL:provider_url API_TOKEN:your_token; do
  var=${pair%%:*} placeholder=${pair#*:}
  value=$(sed -n "s/^[[:space:]]*$var[[:space:]]*=//p" "$ENV_FILE" | tail -n 1 | tr -d "\"'[:space:]")
  case $value in '' | "$placeholder") die "$var in $ENV_FILE is missing, empty, or still '$placeholder'." ;; esac
done

BINDS=()
[ -z "$PROJECT" ] || BINDS+=(--bind "$PROJECT:$PROJECT")

# Extra mounts: host_path[:container_path][:ro|:rw]
MOUNTS_FILE="${MOUNTS_FILE:-$HERE/mounts.conf}"
if [ -f "$MOUNTS_FILE" ]; then
  while read -r line || [ -n "$line" ]; do # plain `read` trims surrounding whitespace
    case $line in '' | '#'*) continue ;; esac
    line=${line//@HERE/$HERE}

    mode=ro
    if [[ $line =~ ^(.*):(ro|rw)$ ]]; then line=${BASH_REMATCH[1]} mode=${BASH_REMATCH[2]}; fi

    host=${line%%:*}
    cont=${line#"$host"}
    cont=${cont#:}
    cont=${cont:-$host}
    host=${host/#\~/$HOME}
    cont=${cont/#\~/$HOME}

    [[ $host == /* && $cont == /* ]] || {
      echo "mounts: skipping '$line' (paths must be absolute)" >&2
      continue
    }
    [ -e "$host" ] || {
      echo "mounts: skipping '$host' (does not exist)" >&2
      continue
    }

    # Targets under the home live inside the agent home (itself a bind mount),
    # so the mount point has to exist there.
    if [[ $cont == "$HOME"/* ]]; then
      mp="$AGENT_HOME/${cont#"$HOME"/}"
      if [ -d "$host" ]; then mkdir -p "$mp"; else
        mkdir -p "${mp%/*}"
        [ -e "$mp" ] || touch "$mp"
      fi
    fi

    BINDS+=(--bind "$host:$cont:$mode")
    echo "Mounting $host -> $cont ($mode)" >&2
  done <"$MOUNTS_FILE"
fi

# A project is only required when there is nothing else to work on.
if [ -z "$PROJECT" ] && [ ${#BINDS[@]} -eq 0 ]; then
  usage >&2
  die "a project path is required because $MOUNTS_FILE has no usable mounts."
fi

# Conda: mounted at the same path as on the host (envs hard-code absolute paths).
if [ "$CONDA_PERM" != no ]; then
  base=${CONDA_BASE:-}
  [ -n "$base" ] || base=$(conda info --base 2>/dev/null || true)
  if [ -z "$base" ]; then
    for d in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" "$HOME/mambaforge" \
      /opt/conda /opt/miniconda3 /opt/anaconda3; do
      if [ -x "$d/bin/conda" ]; then
        base=$d
        break
      fi
    done
  fi

  if [ -d "$base" ]; then
    if [ "$CONDA_PERM" = ask ]; then
      CONDA_PERM=ro
      if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "Mount conda environments read-only or read-write? [RO/rw] " reply
        case ${reply,,} in rw | w | write | read-write | readwrite) CONDA_PERM=rw ;; esac
      fi
    fi
    BINDS+=(--bind "$base:$base:$CONDA_PERM")

    # Also mount envs dirs that live outside the conda base (e.g. ~/.conda/envs).
    while read -r d; do
      [ -d "$d" ] && [[ $d/ != "$base"/* ]] && BINDS+=(--bind "$d:$d:$CONDA_PERM")
    done < <("$base/bin/conda" config --show envs_dirs 2>/dev/null | sed -n 's/^  - //p')

    export APPTAINERENV_PREPEND_PATH="$base/condabin" # survives --cleanenv
    echo "Mounting conda from $base ($CONDA_PERM)" >&2
  elif [ -n "${CONDA_BASE:-}" ]; then
    die "CONDA_BASE='$CONDA_BASE' is not a directory."
  else
    echo "No conda installation found; skipping conda mount. (Set CONDA_BASE=/path/to/conda to specify one.)" >&2
  fi
fi

exec apptainer exec \
  --containall --cleanenv --no-mount cwd --writable-tmpfs \
  --env-file "$ENV_FILE" \
  --home "$AGENT_HOME:$HOME" \
  "${BINDS[@]}" \
  --pwd "${PROJECT:-$HOME}" \
  --env TERM="${TERM:-xterm-256color}" \
  --env USER="$(id -un)" \
  --env LOGNAME="$(id -un)" \
  "$HERE/ubuntu-opencode.sif" "${@:-opencode}"
