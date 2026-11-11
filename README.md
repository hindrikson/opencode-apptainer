# OpenCode with Apptainer

Run OpenCode from inside a container that can only see the directories you choose. Apptainer must be installed.

## Setup (once)

1. Skip this if `ubuntu-opencode.sif` already exists next to `run-agent.sh`, otherwise: 
```
apptainer build --fakeroot ubuntu-opencode.sif ubuntu.def
```

2. Make the launcher executable:
```
chmod +x run-agent.sh
```

3. Create a file called `agent.env` next to `run-agent.sh`. Use `agent.env-template` as a template and edit the following variables:
```
FHGENIE_BASE_URL=fhgenie-provider-url
FHGENIE_API_TOKEN=place-your-token-here
```
Write one `KEY=value` per line, without quotes or spaces around `=`. Keep this file private: don't commit it to git and don't put it inside a directory you mount in the container. `run-agent.sh` sets its permissions to owner-only automatically.

4. Create a file called `mounts.conf` next to `run-agent.sh`. Use `mounts.conf-template` as a starting point:
```
cp mounts.conf-template mounts.conf
```
List the host directories you want the agent to reach, one per line (see [Extra mounts](#extra-mounts-mountsconf) below). `mounts.conf` is gitignored; keep it out of git since it describes your local layout.

## Usage

```
./run-agent.sh [--conda-ro | --conda-rw | --no-conda] [path/to/your_directory] [command...]
```

The directory you pass is mounted at its **original host path** inside the container, and OpenCode starts there. Relative paths (including `.`) and absolute paths both work.

The directory is optional: if `mounts.conf` lists at least one usable entry, you can run `./run-agent.sh` and the container starts in the agent home (`/mnt/home/<user>`). If `mounts.conf` is empty or has no usable entries, a project directory is required. The first argument is treated as the project only if it is an existing directory; otherwise it is treated as the start of the command.

When you quit OpenCode, the container exits. Your conda installation is mounted automatically when one is found; the script asks whether to mount it read-only or read-write (read-only if there is no terminal).

To get a shell in the same restricted environment instead (for debugging, for example), add `bash`:
```
./run-agent.sh path/to/your_directory bash
```

When OpenCode launches press **ctrl+p** to have a look at its keybindings.

### Conda options

- `--conda-ro` — mount conda read-only, no prompt (same as `--conda`)
- `--conda-rw` — mount conda read-write, no prompt
- `--no-conda` — don't mount conda at all
- (none) — ask read-only vs read-write; defaults to read-only if there is no terminal

If no conda installation is found, a warning is printed and conda is skipped. Set `CONDA_BASE=/path/to/conda` to skip auto-detection (an invalid path is an error).

## What the container can see

Apptainer mounts your whole home directory by default. `run-agent.sh` turns that off and mounts only:

- the entries listed in `mounts.conf`
- the project directory you pass, read-write, at the same path as on the host
- your conda installation, when enabled
- `~/agent-home` on the host as the agent's home, at `/mnt/home/<user>` inside the container (OpenCode's login state and caches live there)

Your real home, SSH keys and other projects are not visible unless you list them in `mounts.conf`. The network is open, since OpenCode needs it to reach the model API.

## Extra mounts (`mounts.conf`)

`mounts.conf` has one entry per line:

```
host_path[:container_path][:ro|:rw]
```

- `container_path` defaults to `host_path` (same path inside as outside)
- the mode defaults to read-only; use `:rw` to allow writes
- blank lines and lines starting with `#` are ignored
- a leading `~` expands to your home directory on the host side, and to the container home (`/mnt/home/<user>`) on the container side
- `@HERE` expands to the directory containing `run-agent.sh`
- entries whose host path is missing, or whose paths are not absolute, are skipped with a warning

Set `MOUNTS_FILE=/path/to/file` to use a different list. Because entries are read-only by default, only add `:rw` for directories the agent actually needs to modify.

The `opencode/` configuration directory is exposed through `mounts.conf` as well:
```
@HERE/opencode:~/.config/opencode:ro
```
Keep that line so OpenCode finds its configuration, agents and skills.

## Working safely

- The agent can edit or delete anything in the mounted directories. Use git, work on a branch, and review the diff on the host before committing. Commit and push from the host, since there are no SSH keys inside the container.
- Mounts default to read-only. Only add `:rw` to entries the agent needs to modify.

## Configuration

The `opencode/` directory next to `run-agent.sh` has two files:

- `opencode.json`: OpenCode settings. You can set default models for the plan and build agents, define subagents, and more. See the OpenCode documentation.
- `tui.json`: terminal interface settings, such as keybindings.

Edit these files in `opencode/`, not inside the container. `run-agent.sh` mounts `opencode/` read-only at `~/.config/opencode` inside the container (via the `@HERE/opencode:~/.config/opencode:ro` line in `mounts.conf`), so changes made inside the container are not saved back to the host.

## Agents and skills

Alongside those files, `opencode/` has two example directories:

- `agents/`: agent definitions. Each Markdown file describes a named assistant with its own prompt, model and permissions.
- `skills/`: reusable instructions an agent can load when needed. Each skill lives in its own directory with a `SKILL.md` file and can include supporting files.

`run-agent.sh` exposes these directories inside the agent's global config (`~/.config/opencode` inside the container) through the same read-only `opencode/` mount, so OpenCode discovers them automatically. Changes made inside the container are not saved back to the host; edit them in `opencode/` instead.

The `release-notes` agent and its `release-notes` skill are **only an example** of how to create agents and skills. They are **not tested**. Treat them as a starting point for your own agents and skills. See the OpenCode documentation on creating [agents](https://opencode.ai/docs/agents/) and [skills](https://opencode.ai/docs/skills/).

## Troubleshooting

- `Unexpected server error` at startup is a generic message. Start a shell with `./run-agent.sh path/to/your_directory bash` and run `opencode --print-logs` to see the real cause.
- To check that your credentials reached the container, start a shell as above and run `env | grep FHGENIE`.
- If a directory is missing inside the container, check the `mounts:` warnings printed by `run-agent.sh` (missing or relative paths are skipped) and inspect the mounts from a `bash` shell with `mount | grep <path>`.
- If OpenCode can't find its configuration, agents or skills, make sure `mounts.conf` still contains the `@HERE/opencode:~/.config/opencode:ro` line.
