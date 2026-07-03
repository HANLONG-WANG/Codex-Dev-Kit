# codex-dev-kit

`codex-dev` v0.2.2-local 是一个无特权（rootless）Podman 管理工具，用于在 Fedora 容器中运行 Codex，并采用固定的主机隔离策略。

中文版本：[README.md](README.md)（English）

## 安全模型

- Codex 在容器内运行，参数为 `--sandbox danger-full-access --ask-for-approval never`。
- 唯一的主机挂载是单一项目目录：`~/Projects/<project>` -> `/workspace`。
- 不会将 `~/Projects` 作为父目录整体挂载。
- 不会挂载 `$HOME`、`~/.ssh`、`~/.config`、浏览器数据、Docker/Podman 套接字、主机设备、`/run` 或 `/var/run`。
- 不会使用 `--privileged` 或主机 PID/IPC/network 命名空间。
- 项目目录使用 Podman 的 SELinux 私有标签选项 `:Z` 挂载。
- 项目配置是声明式的，不能添加任意挂载或容器运行参数。
- 镜像/容器/卷的名称包含项目名的短哈希，以避免 `App` 与 `app` 等名称冲突。
- 在执行 `build`/`codex`/`shell` 之前，工具会拒绝包含 socket、FIFO、设备文件、嵌套挂载点或硬链接文件的项目。硬链接检查可在人工审计后，通过 `CODEX_DEV_ALLOW_HARDLINKS=1` 绕过。

## 安装

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
codex-dev doctor
```

`./install.sh` 还会在你的用户数据目录下为 `codex-dev` 安装 Zsh 补全，并在可安全写入时向 `.zshrc` 写入一段小的标记内容。安装后请打开一个新的 Zsh 会话，或执行 `exec zsh`。

跳过安装步骤：

```bash
CODEX_DEV_SKIP_COMPLETIONS=1 ./install.sh  # 不安装补全文件，也不修改 .zshrc
CODEX_DEV_SKIP_RC=1 ./install.sh           # 安装补全文件，但不修改 .zshrc
```

卸载：

```bash
codex-dev uninstall
```

`uninstall` 会询问是否删除 codex-dev 的 Podman 镜像和卷，然后列出将删除的本地文件、目录、Zsh rc 修改项以及选中的 Podman 资源。除非你确认最终方案，否则不会删除任何内容。由 `codex-dev init` 创建的项目目录与 `.codex-dev` 元数据会被保留。

## 常见流程

```bash
codex-dev init my-app python
codex-dev build my-app
codex-dev codex my-app
# 或者直接在 /workspace 中启动 OMX
codex-dev omx my-app
```

在首次 Codex/OMX 会话中完成登录。Codex 状态保存在每个项目的 Podman 命名卷中，而不是主机上的 `~/.codex`。

## 修改依赖

编辑：

```bash
codex-dev edit my-app
```

示例：

```env
PROFILE=python
FEDORA_IMAGE=registry.fedoraproject.org/fedora:latest
READ_ONLY_ROOT=yes
DNF_PACKAGES="nodejs npm cmake ninja-build openssl-devel"
BUILD_SCRIPT=""
```

然后重建：

```bash
codex-dev build my-app
codex-dev codex my-app
```

重建不会创建或删除项目卷。`codex-dev-home-<resource-id>` 和 `codex-dev-cache-<resource-id>` 等现有卷会被 `codex`/`shell` 复用，不会被 `build` 影响。因此修改 `project.env` 后重建通常不会出现“卷已存在”错误。重置命令现在会准确报告缺失的卷，并在运行中的容器占用该卷时失败。

## `project.env` 语法

`project.env` 不会被当作 shell 脚本执行。支持的语法刻意保持简洁：

```env
KEY=VALUE
KEY="VALUE WITH SPACES"
KEY='VALUE WITH SPACES'
# comment
KEY=value # 内联注释
```

支持的键：

- `PROFILE`：`generic`、`python`、`node`、`rust`、`go`、`gtk`、`android`、`custom` 之一。
- `FEDORA_IMAGE`：Fedora 基础镜像，通常为 `registry.fedoraproject.org/fedora:latest`。
- `READ_ONLY_ROOT`：`yes` 或 `no`，运行时默认 `yes`。
- `DNF_PACKAGES`：仅可使用空格分隔的 Fedora 软件包名，不支持 shell 语法。
- `BUILD_SCRIPT`：可选的相对路径，位于 `.codex-dev/` 下，通常为 `.codex-dev/build.sh`。

不支持的行与键会被拒绝，裸命令行也会被拒绝。

## 构建时命令

不要把裸 shell 命令直接写入 `project.env`。请改用构建脚本：

```bash
codex-dev edit-build-script my-app
```

然后在 `project.env` 中设置：

```env
BUILD_SCRIPT=".codex-dev/build.sh"
```

构建脚本会被复制到 Podman 构建上下文中，并在 rootless 镜像构建容器内执行。它不会挂载主机文件，不会访问主机主目录、主机 socket，也不会以特权模式运行。它仍然可以在镜像中安装工具，因此应当视为项目受控代码，不要在其中放置密钥或敏感信息。

## 命令

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

`codex-dev list` 是只读操作，会显示已有 build 记录的项目和容器状态。`codex-dev list -a` 也是只读操作，并会额外扫描 `${CODEX_DEV_PROJECTS_ROOT:-~/Projects}` 的直接子目录，通过 `.codex-dev/project.env` 识别已初始化项目。

`codex-dev attach <shell|omx|codex|exec> ...` 会复用当前终端，附着到同一个正在运行的项目容器并执行对应命令。如果项目容器未运行，则退回到当前终端中的普通命令启动流程。

## Zsh 补全

当前首次发布的补全仅支持 Zsh。Bash/Fish 补全暂缓发布。

执行 `./install.sh` 后，新开的 Zsh 可支持补全：

- 顶层命令：`codex-dev <TAB>`
- 命令前缀：`codex-dev sh<TAB>` -> `shell`
- 已管理项目名：`codex-dev shell <TAB>`
- 配置：`codex-dev init demo <TAB>`
- 已知参数：`codex-dev shell demo <TAB>` -> `--rw-root`
- OMX 快捷方式：`codex-dev omx demo` 会在项目容器内 `/workspace` 运行 `omx --madmax --high`

补全逻辑通过 `codex-dev __complete` 实现，仅读取命令行片段和浅层项目信息；不会调用 Podman，不会读取 `.codex-dev/project.env`，不会执行构建脚本，也不会访问网络。

项目补全返回 `${CODEX_DEV_PROJECTS_ROOT:-~/Projects}` 下的 `codex-dev` 项目名，不会返回原始 Podman 容器名。容器名由项目名派生。

手工安装/故障排查：

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
codex-dev completion zsh --command "$HOME/.local/bin/codex-dev" \
  > "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_codex-dev"
```

如果你的 `.zshrc` 使用了插件管理器或自定义 `compinit` 流程，请在现有 `compinit` 之前 source 已安装的片段：

```zsh
source "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_codex-dev"
autoload -Uz compinit
compinit
```

有用的检查命令：

```zsh
echo $fpath
autoload -Uz compinit && compinit
whence -w _codex-dev
```

## 配置模板

- `generic`：基础开发工具和 Codex CLI
- `python`：Python、pip、venv、pipx
- `node`：Node.js/npm
- `rust`：Rust/Cargo
- `go`：Go
- `gtk`：GTK4/libadwaita/meson/ninja
- `android`：Java/Gradle/android-tools 入门配置；完整 Android SDK 仍按项目实际情况补充
- `custom`：基础工具 + 你的 `DNF_PACKAGES`

## 注意事项

默认情况下运行时根文件系统是只读的。这使系统依赖变更保持明确且可复现，通过 `project.env` 与 `codex-dev build` 来管理。必要时可使用 `--rw-root` 进行一次性实验性 shell，但该模式仍不新增主机挂载。
