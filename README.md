# OpenCode with Apptainer

Run OpenCode from inside a container that can only see the directory you choose. Apptainer must be installed.

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

## Usage

```
./run-agent.sh path/to/your_directory
```

Relative paths (including `.`) and absolute paths both work. Your directory appears as `/workspace` inside the container, and OpenCode starts there. When you quit OpenCode, the container exits.

To get a shell in the same restricted environment instead (for debugging, for example), add `bash`:
```
./run-agent.sh path/to/your_directory bash
```

## What the container can see

Apptainer mounts your whole home directory by default. `run-agent.sh` turns that off and mounts only:

- the directory you pass in, read-write, at `/workspace`
- `~/agent-home` on the host as the agent's home (OpenCode's login state and caches live there)

Your real home, SSH keys and other projects are not visible. The network is open, since OpenCode needs it to reach the model API.

## Working safely

- The agent can edit or delete anything in the mounted directory. Use git, work on a branch, and review the diff on the host before committing. Commit and push from the host, since there are no SSH keys inside the container.

## Configuration

The `opencode/` directory next to `run-agent.sh` has two files:

- `opencode.json`: OpenCode settings. You can set default models for the plan and build agents, define subagents, and more. See the OpenCode documentation.
- `tui.json`: terminal interface settings, such as keybindings.

Edit these files in `opencode/`, not inside the container. `run-agent.sh` copies them into `~/agent-home/.config/opencode` on every launch, so changes made inside the container are overwritten next time.

## Troubleshooting

- `Unexpected server error` at startup is a generic message. Start a shell with `./run-agent.sh path/to/your_directory bash` and run `opencode --print-logs` to see the real cause.
- To check that your credentials reached the container, start a shell as above and run `env | grep FHGENIE`.
