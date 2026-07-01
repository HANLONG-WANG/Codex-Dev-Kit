# codex-dev-kit

`codex-dev` v0.2.1 is a rootless Podman manager for running Codex inside a Fedora container with a fixed host isolation policy.

## Security model

- Codex runs inside the container with `--sandbox danger-full-access --ask-for-approval never`.
- The only host bind mount is one concrete project directory: `~/Projects/<project>` -> `/workspace`.
- It does not mount `~/Projects` as a parent directory.
- It does not mount `$HOME`, `~/.ssh`, `~/.config`, browser data, Docker/Podman sockets, host devices, `/run`, or `/var/run`.
- It does not use `--privileged` or host PID/IPC/network namespaces.
- Project directories are mounted with Podman's SELinux private label option `:Z`.
- Project config is declarative and cannot add mounts or container runtime arguments.
- Image/container/volume names include a short hash of the project name to avoid collisions such as `App` vs `app`.
- Before `build`/`enter`/`shell`, the tool refuses projects containing sockets, FIFOs, device files, nested mount points, or hardlinked files. Hardlink checks can be bypassed with `CODEX_DEV_ALLOW_HARDLINKS=1` only after manual audit.

## Install

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
codex-dev doctor
```

## Typical workflow

```bash
codex-dev init my-app python
codex-dev build my-app
codex-dev enter my-app
```

Inside the first Codex session, sign in. Codex state is stored in a per-project Podman named volume, not in your host `~/.codex`.

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
codex-dev enter my-app
```

Rebuilds do not create or delete project volumes. Existing volumes such as `codex-dev-home-<resource-id>` and `codex-dev-cache-<resource-id>` are reused by `enter`/`shell` and are not touched by `build`. Therefore changing `project.env` and rebuilding should not produce a “volume already exists” failure. Reset commands now report absent volumes accurately and fail if a volume cannot be removed because a running container is using it.

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
codex-dev config <project>
codex-dev edit <project>
codex-dev edit-build-script <project>
codex-dev build <project>
codex-dev shell <project> [--rw-root]
codex-dev codex <project> [--rw-root] [-- <extra codex args...>]
codex-dev enter <project> [--rw-root] [-- <extra codex args...>]
codex-dev exec <project> [--rw-root] -- <prompt>
codex-dev doctor [project]
codex-dev volumes <project>
codex-dev reset-cache <project>
codex-dev reset-home <project>
codex-dev nuke-env <project>
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
