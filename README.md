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
PROVIDER_URL=provider_url
API_TOKEN=your_token
```
Write one `KEY=value` per line, without quotes or spaces around `=`. The template also sets `EDITOR` (`nvim` by default); change it to the editor you want inside the container. Keep this file private: don't commit it to git and don't put it inside a directory you mount in the container.

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

When you quit OpenCode, the container exits. Your conda installation is mounted automatically when one is found; the script asks whether to mount it read-only or read-write.

To get a shell in the same restricted environment instead (for debugging, for example), add `bash`:
```
./run-agent.sh path/to/your_directory bash
```

Keybindings are defined in `opencode/cli.json` (the leader key is `ctrl+a`, e.g. `<leader>s` opens the status view).

### Conda options

- `--conda-ro` — mount conda read-only, no prompt (same as `--conda`)
- `--conda-rw` — mount conda read-write, no prompt
- `--no-conda` — don't mount conda at all
- (none) — ask read-only vs read-write; defaults to read-only.

If no conda installation is found, a warning is printed and conda is skipped. Set `CONDA_BASE=/path/to/conda` to skip auto-detection (an invalid path is an error).

## What the container can see

Apptainer mounts your whole home directory by default. `run-agent.sh` turns that off and mounts only:

- the entries listed in `mounts.conf`
- the project directory you pass, read-write, at the same path as on the host
- your conda installation, when enabled
- `~/agent-home` on the host as the agent's home, at `/mnt/home/<user>` inside the container (OpenCode's login state and caches live there)

Your real home, SSH keys and other projects are not visible unless you list them in `mounts.conf`. The network is open, since OpenCode needs it to reach the model API.

Before starting OpenCode, `run-agent.sh` picks a free TCP port on the current node and writes it to `opencode/service.json` on the host. OpenCode reads that file through the `opencode/` mount, which is why that directory is mounted writable (see below).

## Extra mounts (`mounts.conf`)

`mounts.conf` has one entry per line:

```
host_path[:container_path][:ro|:rw]
```

- Check the template `mounts.conf-template`
- `container_path` defaults to `host_path` (same path inside as outside)
- the mode defaults to read-only; use `:rw` to allow writes
- blank lines and lines starting with `#` are ignored
- a leading `~` expands to your home directory on the host side, and to the container home (`/mnt/home/<user>`) on the container side
- `@HERE` expands to the directory containing `run-agent.sh`

Because entries are read-only by default, only add `:rw` for directories the agent actually needs to modify.

The `opencode/` configuration directory is exposed through `mounts.conf` as well. It is mounted read-write because `run-agent.sh` and OpenCode keep runtime state (`service.json`) there:
```
@HERE/opencode:~/.config/opencode:rw
```
The hand-written configuration is then mounted read-only on top of it:
```
@HERE/opencode/agents:~/.config/opencode/agents:ro
@HERE/opencode/skills:~/.config/opencode/skills:ro
@HERE/opencode/opencode.json:~/.config/opencode/opencode.json:ro
@HERE/opencode/cli.json:~/.config/opencode/cli.json:ro
```
Keep these lines so OpenCode finds its configuration, agents and skills. Order matters: the writable `opencode/` line must come first. If a file needs to be changed inside the container and you hit a read-only filesystem error, remove (or change) the `:ro` line for that path so it inherits the writable mount.

## Working safely

- The agent can edit or delete anything in the mounted directories. Use git, work on a branch, and review the diff on the host before committing. Commit and push from the host, since there are no SSH keys inside the container.
- Mounts default to read-only. Only add `:rw` to entries the agent needs to modify.

## Configuration

The `opencode/` directory next to `run-agent.sh` holds the configuration:

- `opencode.json`: OpenCode settings. You can set default models for the plan and build agents, define providers and subagents, and more. See the OpenCode documentation.
- `cli.json`: command-line interface settings, such as keybindings.
- `service.json`: generated by `run-agent.sh` on every start (the free TCP port it selected; OpenCode may add its password). It is gitignored, so don't edit or commit it.

Edit `opencode.json` and `cli.json` in `opencode/`, not inside the container. `run-agent.sh` mounts `opencode/` at `~/.config/opencode` inside the container. The directory itself is read-write so runtime state (such as `service.json`) is written back to the host, but `opencode.json`, `cli.json` and the `agents/` and `skills/` directories are re-mounted read-only on top of it. Changes made inside the container are therefore not saved back to the host.

## Agents and skills

Alongside those files, `opencode/` has two example directories:

- `agents/`: agent definitions. Each Markdown file describes a named assistant with its own prompt, model and permissions.
- `skills/`: reusable instructions an agent can load when needed. Each skill lives in its own directory with a `SKILL.md` file and can include supporting files.

`run-agent.sh` mounts these directories read-only at `~/.config/opencode/agents` and `~/.config/opencode/skills` inside the container, so OpenCode discovers them automatically. Changes made inside the container are not saved back to the host; edit them in `opencode/` instead.

The `release-notes` agent and its `release-notes` skill are **only an example** of how to create agents and skills. They are **not tested**. Treat them as a starting point for your own agents and skills. See the OpenCode documentation on creating [agents](https://opencode.ai/docs/agents/) and [skills](https://opencode.ai/docs/skills/).

## Troubleshooting

- `Unexpected server error` at startup is a generic message. Start a shell with `./run-agent.sh path/to/your_directory bash` and run `opencode --print-logs` to see the real cause.
- To check that your credentials reached the container, start a shell as above and run `env | grep -E '^(PROVIDER_URL|API_TOKEN)='`.
- If a directory is missing inside the container, check the `mounts:` warnings printed by `run-agent.sh` (missing or relative paths are skipped) and inspect the mounts from a `bash` shell with `mount | grep <path>`.
- If OpenCode can't find its configuration, agents or skills, make sure `mounts.conf` still contains the `@HERE/opencode:~/.config/opencode:rw` line and the read-only lines for `agents/`, `skills/`, `opencode.json` and `cli.json`.
- A `Read-only file system` (`EROFS`) error when OpenCode writes a configuration file means that path is covered by one of the `:ro` lines. Remove that line so the path inherits the writable `opencode/` mount.
