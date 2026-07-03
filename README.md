# codex-dev-kit

`codex-dev` v0.2.2-local is a rootless Podman manager for running Codex inside a Fedora container with a fixed host isolation policy.

中文文档：[README_CN.md](README_CN.md)

## Security model

- Codex runs inside the container with `--sandbox danger-full-access --ask-for-approval never`.
- The only host bind mount is one concrete project directory: `~/Projects/<project>` -> `/workspace`.
- It does not mount `~/Projects` as a parent directory.
- It does not mount `$HOME`, `~/.ssh`, `~/.config`, browser data, Docker/Podman sockets, host devices, `/run`, or `/var/run`.
- It does not use `--privileged` or host PID/IPC/network namespaces.
- Project directories are mounted with Podman's SELinux private label option `:Z`.
- Project config is declarative and cannot add mounts or container runtime arguments.
- Image/container/volume names include a short hash of the project name to avoid collisions such as `App` vs `app`.
- Before `build`/`codex`/`shell`, the tool refuses projects containing sockets, FIFOs, device files, nested mount points, or hardlinked files. Hardlink checks can be bypassed with `CODEX_DEV_ALLOW_HARDLINKS=1` only after manual audit.

## Install

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
codex-dev doctor
```

`./install.sh` also installs Zsh tab completion for `codex-dev` in your user data directory and adds a small marker block to `.zshrc` when it can do so safely. Open a new Zsh or run `exec zsh` after installing.

Skip controls:

```bash
CODEX_DEV_SKIP_COMPLETIONS=1 ./install.sh  # do not install completion files or edit .zshrc
CODEX_DEV_SKIP_RC=1 ./install.sh           # install completion files, but do not edit .zshrc
```

Uninstall:

```bash
codex-dev uninstall
```

`uninstall` asks whether to remove codex-dev Podman images and volumes, then prints the exact local files, directories, Zsh rc edits, and selected Podman resources that will be removed. Nothing is deleted until you confirm the final plan. Project directories and `.codex-dev` metadata created by `codex-dev init` are preserved.

## Typical workflow

```bash
codex-dev init my-app python
codex-dev build my-app
codex-dev codex my-app
# or start OMX directly inside /workspace
codex-dev omx my-app
```

Inside the first Codex/OMX session, sign in. Codex state is stored in a per-project Podman named volume, not in your host `~/.codex`.

## Change dependencies

Edit:

```bash
codex-dev edit my-app
```

Example:

```env
PROFILE=python
FEDORA_IMAGE=registry.fedoraproject.org/fedora:latest
READ_ONLY_ROOT=yes
DNF_PACKAGES="nodejs npm cmake ninja-build openssl-devel"
BUILD_SCRIPT=""
```

Then rebuild:

```bash
codex-dev build my-app
codex-dev codex my-app
```

Rebuilds do not create or delete project volumes. Existing volumes such as `codex-dev-home-<resource-id>` and `codex-dev-cache-<resource-id>` are reused by `codex`/`shell` and are not touched by `build`. Therefore changing `project.env` and rebuilding should not produce a “volume already exists” failure. Reset commands now report absent volumes accurately and fail if a volume cannot be removed because a running container is using it.

## `project.env` syntax

`project.env` is not sourced as a shell script. Supported syntax is deliberately narrow:

```env
KEY=VALUE
KEY="VALUE WITH SPACES"
KEY='VALUE WITH SPACES'
# comment
KEY=value # inline comment
```

Supported keys:

- `PROFILE`: one of `generic`, `python`, `node`, `rust`, `go`, `gtk`, `android`, `custom`.
- `FEDORA_IMAGE`: Fedora base image, normally `registry.fedoraproject.org/fedora:latest`.
- `READ_ONLY_ROOT`: `yes` or `no`; runtime default is `yes`.
- `DNF_PACKAGES`: space-separated Fedora package names only. No shell syntax.
- `BUILD_SCRIPT`: optional relative path to a build script under `.codex-dev/`, normally `.codex-dev/build.sh`.

Unsupported lines and unsupported keys are rejected. Bare command lines are rejected.

## Build-time commands

Do not put a bare shell command directly into `project.env`. Use a build script:

```bash
codex-dev edit-build-script my-app
```

Then set this in `project.env`:

```env
BUILD_SCRIPT=".codex-dev/build.sh"
```

The build script is copied into the Podman build context and run inside the rootless image build container. It does not get host mounts, your host home, host sockets, or privileged mode. It can still install tools into the image, so treat it as project-controlled code. Do not put secrets in it.

## Commands

```text
codex-dev setup
codex-dev init <project> [profile]
codex-dev profiles
codex-dev list
codex-dev list -a
codex-dev config <project>
codex-dev edit <project>
codex-dev edit-build-script <project>
codex-dev build <project>
codex-dev shell <project> [--rw-root]
codex-dev omx <project> [--rw-root]
codex-dev codex <project> [--rw-root] [-- <extra codex args...>]
codex-dev exec <project> [--rw-root] -- <prompt>
codex-dev attach <shell|omx|codex|exec> <project> [...]
codex-dev doctor [project]
codex-dev volumes <project>
codex-dev reset-cache <project>
codex-dev reset-home <project>
codex-dev nuke-env <project>
codex-dev uninstall
codex-dev completion zsh [--command <absolute-path>]
```

`codex-dev list` is read-only and shows projects with existing build records plus their container status. `codex-dev list -a` is also read-only and additionally scans direct children of `${CODEX_DEV_PROJECTS_ROOT:-~/Projects}` for initialized projects (`.codex-dev/project.env`).

`codex-dev attach <shell|omx|codex|exec> ...` opens another host terminal attached to the same running project container and runs the matching command there. If the project container is not running, it falls back to the normal command flow in the current terminal. Set `CODEX_DEV_TERMINAL` to choose the terminal launcher explicitly.

## Zsh completion

The first completion release is Zsh-only. Bash/Fish completion is intentionally deferred.

After `./install.sh`, a new Zsh can complete:

- top-level commands: `codex-dev <TAB>`
- command prefixes: `codex-dev sh<TAB>` -> `shell`
- managed project names: `codex-dev shell <TAB>`
- profiles: `codex-dev init demo <TAB>`
- known flags: `codex-dev shell demo <TAB>` -> `--rw-root`
- OMX shortcut: `codex-dev omx demo` runs `omx --madmax --high` inside the project container at `/workspace`

Completion uses `codex-dev __complete` internally. It only reads command-line words and shallow project metadata; it does not call Podman, does not source `.codex-dev/project.env`, does not run build scripts, and does not access the network.

Project completion returns `codex-dev` project names under `${CODEX_DEV_PROJECTS_ROOT:-~/Projects}`, not raw Podman container names. Container names are derived from project names.

Manual installation or troubleshooting:

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
codex-dev completion zsh --command "$HOME/.local/bin/codex-dev" \
  > "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_codex-dev"
```

If your `.zshrc` uses a plugin manager or custom `compinit` flow, source the installed snippet before your existing `compinit`:

```zsh
source "${XDG_DATA_HOME:-$HOME/.local/share}/codex-dev/zsh-completion.zsh"
autoload -Uz compinit
compinit
```

Useful checks:

```zsh
echo $fpath
autoload -Uz compinit && compinit
whence -w _codex-dev
```

## Profiles

- `generic`: base development tools and Codex CLI
- `python`: Python, pip, venv, pipx
- `node`: Node.js/npm
- `rust`: Rust/Cargo
- `go`: Go
- `gtk`: GTK4/libadwaita/meson/ninja
- `android`: Java/Gradle/android-tools starter profile; full Android SDK setup is intentionally left project-specific
- `custom`: base tools only plus your `DNF_PACKAGES`

## Notes

Runtime root filesystem is read-only by default. This keeps system dependency changes explicit and reproducible through `project.env` + `codex-dev build`. Use `--rw-root` for a disposable experimental shell when necessary; it still does not add host mounts.
