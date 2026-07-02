#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_DEV="$ROOT/codex-dev"
INSTALL="$ROOT/install.sh"
failures=0

fail() { printf 'not ok - %s\n' "$*" >&2; failures=$((failures + 1)); }
ok() { printf 'ok - %s\n' "$*"; }
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then ok "$label"; else fail "$label (missing: $needle)"; fi
}
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then ok "$label"; else fail "$label (unexpected: $needle)"; fi
}
assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq -- "$needle" "$file"; then ok "$label"; else fail "$label (missing in $file: $needle)"; fi
}
assert_file_exists() {
  local file="$1" label="$2"
  if [[ -f "$file" ]]; then ok "$label"; else fail "$label (missing $file)"; fi
}
assert_file_not_exists() {
  local file="$1" label="$2"
  if [[ ! -e "$file" ]]; then ok "$label"; else fail "$label (unexpectedly exists $file)"; fi
}
assert_dir_exists() {
  local dir="$1" label="$2"
  if [[ -d "$dir" ]]; then ok "$label"; else fail "$label (missing dir $dir)"; fi
}
assert_dir_not_exists() {
  local dir="$1" label="$2"
  if [[ ! -e "$dir" ]]; then ok "$label"; else fail "$label (unexpectedly exists $dir)"; fi
}

make_env() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export CODEX_DEV_PROJECTS_ROOT="$TMP/projects"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$CODEX_DEV_PROJECTS_ROOT"
  mkdir -p "$CODEX_DEV_PROJECTS_ROOT/app-one/.codex-dev" "$CODEX_DEV_PROJECTS_ROOT/api_two/.codex-dev"
  printf 'PROFILE=python\nMALICIOUS=$(touch %s/pwned)\n' "$TMP" > "$CODEX_DEV_PROJECTS_ROOT/app-one/.codex-dev/project.env"
  printf 'PROFILE=generic\n' > "$CODEX_DEV_PROJECTS_ROOT/api_two/.codex-dev/project.env"
  mkdir -p "$CODEX_DEV_PROJECTS_ROOT/bad name/.codex-dev"
  touch "$CODEX_DEV_PROJECTS_ROOT/bad name/.codex-dev/project.env"
  mkdir -p "$TMP/outside/.codex-dev"
  touch "$TMP/outside/.codex-dev/project.env"
  ln -s "$TMP/outside" "$CODEX_DEV_PROJECTS_ROOT/linkproj"
  mkdir -p "$CODEX_DEV_PROJECTS_ROOT/linkmeta" "$TMP/meta-real"
  touch "$TMP/meta-real/project.env"
  ln -s "$TMP/meta-real" "$CODEX_DEV_PROJECTS_ROOT/linkmeta/.codex-dev"
  mkdir -p "$CODEX_DEV_PROJECTS_ROOT/linkcfg/.codex-dev"
  touch "$TMP/real-project.env"
  ln -s "$TMP/real-project.env" "$CODEX_DEV_PROJECTS_ROOT/linkcfg/.codex-dev/project.env"
  FAKEBIN="$TMP/fakebin"
  mkdir -p "$FAKEBIN"
  cat > "$FAKEBIN/podman" <<'PODMAN'
#!/usr/bin/env bash
echo invoked > "${PODMAN_INVOKED_MARKER:?}"
exit 99
PODMAN
  chmod +x "$FAKEBIN/podman"
  export PODMAN_INVOKED_MARKER="$TMP/podman-invoked"
  export PATH="$FAKEBIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

run_complete() {
  "$CODEX_DEV" __complete "$@"
}

resource_id_for_test() {
  local name="$1" slug hash
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^[._-]+//; s/[._-]+$//')"
  [[ -n "$slug" ]] || slug="project"
  hash="$(printf '%s' "$name" | sha256sum | awk '{print substr($1,1,10)}')"
  printf '%s-%s' "$slug" "$hash"
}

make_uninstall_env() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CODEX_DEV_PROJECTS_ROOT="$TMP/projects"
  export PODMAN_LOG="$TMP/podman-remove.log"
  FAKEBIN="$TMP/fakebin"
  mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/zsh/site-functions" "$XDG_DATA_HOME/codex-dev" "$XDG_CONFIG_HOME/codex-dev/build" "$CODEX_DEV_PROJECTS_ROOT" "$FAKEBIN"
  cp "$CODEX_DEV" "$HOME/.local/bin/codex-dev"
  printf 'completion\n' > "$XDG_DATA_HOME/zsh/site-functions/_codex-dev"
  printf 'snippet\n' > "$XDG_DATA_HOME/codex-dev/zsh-completion.zsh"
  printf 'build-cache\n' > "$XDG_CONFIG_HOME/codex-dev/build/cache.txt"
  for project in app-one api_two; do
    mkdir -p "$CODEX_DEV_PROJECTS_ROOT/$project/.codex-dev"
    printf 'PROFILE=generic\n' > "$CODEX_DEV_PROJECTS_ROOT/$project/.codex-dev/project.env"
    printf 'keep me\n' > "$CODEX_DEV_PROJECTS_ROOT/$project/.codex-dev/sentinel"
  done
  cat > "$FAKEBIN/podman" <<'PODMAN'
#!/usr/bin/env bash
case "${1:-}" in
  info)
    if [[ "${2:-}" == "--format" ]]; then printf '%s\n' "${PODMAN_ROOTLESS_VALUE:-true}"; exit 0; fi
    exit 0
    ;;
  container|image|volume)
    if [[ "${2:-}" == "exists" ]]; then exit 0; fi
    if [[ "$1" == "image" && "${2:-}" == "rm" ]]; then echo "podman $*" >> "${PODMAN_LOG:?}"; exit 0; fi
    if [[ "$1" == "volume" && "${2:-}" == "rm" ]]; then echo "podman $*" >> "${PODMAN_LOG:?}"; exit 0; fi
    ;;
  rm)
    echo "podman $*" >> "${PODMAN_LOG:?}"
    exit 0
    ;;
esac
printf 'unexpected podman call: %s\n' "$*" >&2
exit 1
PODMAN
  chmod +x "$FAKEBIN/podman"
  export PATH="$FAKEBIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

write_codex_dev_marker_rc() {
  local rc="$1"
  mkdir -p "$(dirname "$rc")"
  cat > "$rc" <<'ZSHRC'
before
# BEGIN codex-dev zsh completion
source '/tmp/old/codex-dev/zsh-completion.zsh'
# END codex-dev zsh completion
after
ZSHRC
}

assert_projects_preserved() {
  for project in app-one api_two; do
    assert_file_exists "$CODEX_DEV_PROJECTS_ROOT/$project/.codex-dev/project.env" "$project project.env preserved"
    assert_file_contains "$CODEX_DEV_PROJECTS_ROOT/$project/.codex-dev/sentinel" 'keep me' "$project .codex-dev sentinel preserved"
  done
}

printf '1..unknown\n'

bash -n "$CODEX_DEV" "$INSTALL" && ok 'bash syntax: codex-dev and install.sh' || fail 'bash syntax: codex-dev and install.sh'

make_env
zsh_script="$($CODEX_DEV completion zsh --command "$CODEX_DEV")" || fail 'completion zsh exits 0'
assert_contains "$zsh_script" '#compdef codex-dev' 'zsh script has compdef'
assert_contains "$zsh_script" '_codex-dev' 'zsh script defines completion function'
assert_contains "$zsh_script" '__complete' 'zsh script calls internal complete engine'
assert_contains "$zsh_script" '--current' 'zsh script passes current index'
assert_contains "$zsh_script" "$CODEX_DEV" 'zsh script embeds provided absolute command path'
if "$CODEX_DEV" completion bash >/tmp/codex-dev-bash.out 2>/tmp/codex-dev-bash.err; then
  fail 'completion bash is not advertised as supported'
else
  ok 'completion bash exits non-zero as unsupported'
fi
if "$CODEX_DEV" completion unknown >/tmp/codex-dev-unknown.out 2>/tmp/codex-dev-unknown.err; then
  fail 'completion unknown exits non-zero'
else
  ok 'completion unknown exits non-zero'
fi

out="$(run_complete --current 2 -- codex-dev '')"
for c in setup init profiles list config edit edit-build-script build shell codex enter exec doctor volumes reset-cache reset-home nuke-env uninstall completion; do
  assert_contains "$out" "$c" "top-level completion includes $c"
done

out="$(run_complete --current 2 -- codex-dev sh)"
assert_contains "$out" 'shell' 'prefix completion includes shell'
assert_not_contains "$out" 'setup' 'prefix completion filters nonmatching commands'

for cmd in shell build config edit volumes reset-cache reset-home nuke-env; do
  out="$(run_complete --current 3 -- codex-dev "$cmd" '')"
  assert_contains "$out" 'app-one' "$cmd project completion includes app-one"
  assert_contains "$out" 'api_two' "$cmd project completion includes api_two"
  assert_not_contains "$out" 'bad name' "$cmd project completion excludes invalid names"
  assert_not_contains "$out" 'linkproj' "$cmd project completion excludes symlinked project dir"
  assert_not_contains "$out" 'linkmeta' "$cmd project completion excludes symlinked .codex-dev"
  assert_not_contains "$out" 'linkcfg' "$cmd project completion excludes symlinked project.env"
done

out="$(run_complete --current 4 -- codex-dev init new-project '')"
for p in generic python node rust go gtk android custom; do
  assert_contains "$out" "$p" "profile completion includes $p"
done

out="$(run_complete --current 4 -- codex-dev shell app-one '')"
assert_contains "$out" '--rw-root' 'shell post-project suggests --rw-root'
assert_not_contains "$out" 'api_two' 'shell post-project does not suggest project names'

out="$(run_complete --current 4 -- codex-dev codex app-one '')"
assert_contains "$out" '--rw-root' 'codex post-project suggests --rw-root'
assert_contains "$out" '--' 'codex post-project suggests --'
out="$(run_complete --current 4 -- codex-dev enter app-one '')"
assert_contains "$out" '--rw-root' 'enter post-project suggests --rw-root'
assert_contains "$out" '--' 'enter post-project suggests --'
out="$(run_complete --current 5 -- codex-dev exec app-one -- '')"
if [[ -z "$out" ]]; then ok 'exec free-text position has no forced suggestions'; else fail "exec free-text position expected no output, got: $out"; fi

[[ ! -e "$PODMAN_INVOKED_MARKER" ]] && ok 'completion did not invoke podman' || fail 'completion invoked podman'
[[ ! -e "$TMP/pwned" ]] && ok 'completion did not source project.env' || fail 'completion sourced project.env'

list_out="$($CODEX_DEV list)"
assert_contains "$list_out" 'app-one' 'list includes app-one'
assert_contains "$list_out" 'api_two' 'list includes api_two'
assert_not_contains "$list_out" 'bad name' 'list excludes invalid names via shared helper'
assert_not_contains "$list_out" 'linkproj' 'list excludes symlinked project dir via shared helper'
assert_not_contains "$list_out" 'linkmeta' 'list excludes symlinked .codex-dev via shared helper'
assert_not_contains "$list_out" 'linkcfg' 'list excludes symlinked project.env via shared helper'

if command -v zsh >/dev/null 2>&1; then
  zfunc="$TMP/zfunc"
  mkdir -p "$zfunc"
  printf '%s\n' "$zsh_script" > "$zfunc/_codex-dev"
  zsh -n "$zfunc/_codex-dev" && ok 'zsh syntax check passes' || fail 'zsh syntax check passes'
  CAPTURE="$TMP/zsh-compadd.out" ZFUNC="$zfunc" zsh -f <<'ZSH' && ok 'zsh wrapper returns project candidates via compadd' || fail 'zsh wrapper returns project candidates via compadd'
fpath=($ZFUNC $fpath)
autoload -Uz compinit
compinit -D -d /tmp/codex-dev-zcompdump-$$
autoload -Uz _codex-dev
compadd() { print -r -- "$@" >> "$CAPTURE" }
words=(codex-dev shell '')
CURRENT=3
_codex-dev
grep -q -- app-one "$CAPTURE"
grep -q -- api_two "$CAPTURE"
ZSH
else
  ok 'zsh integration skipped: zsh not installed'
fi

# Installer tests: absent/no-compinit rc.
make_env
( cd "$ROOT" && "$INSTALL" ) > "$TMP/install.out" 2> "$TMP/install.err"
installed_bin="$HOME/.local/bin/codex-dev"
completion_file="$XDG_DATA_HOME/zsh/site-functions/_codex-dev"
snippet_file="$XDG_DATA_HOME/codex-dev/zsh-completion.zsh"
assert_file_exists "$installed_bin" 'installer copies binary'
assert_file_exists "$completion_file" 'installer writes zsh completion file'
assert_file_contains "$completion_file" "$installed_bin" 'installed completion embeds installed binary path'
assert_file_exists "$snippet_file" 'installer writes zsh snippet'
assert_file_contains "$HOME/.zshrc" 'codex-dev zsh completion' 'installer creates marker in absent .zshrc'
( cd "$ROOT" && "$INSTALL" ) > "$TMP/install2.out" 2> "$TMP/install2.err"
marker_count="$(grep -c 'BEGIN codex-dev zsh completion' "$HOME/.zshrc" || true)"
[[ "$marker_count" == "1" ]] && ok 'installer marker is idempotent' || fail "installer marker duplicated: $marker_count"

# Installer tests: simple compinit gets marker before first recognizable compinit boundary.
make_env
cat > "$HOME/.zshrc" <<'ZSHRC'
# existing header
autoload -Uz compinit
compinit
ZSHRC
chmod 0640 "$HOME/.zshrc"
( cd "$ROOT" && "$INSTALL" ) > "$TMP/simple.out" 2> "$TMP/simple.err"
mode_after="$(stat -c '%a' "$HOME/.zshrc")"
[[ "$mode_after" == "640" ]] && ok 'rc rewrite preserves file mode' || fail "rc rewrite mode changed: $mode_after"
python3 - "$HOME/.zshrc" <<'PY' && ok 'marker inserted before first compinit boundary' || fail 'marker inserted before first compinit boundary'
import sys
text=open(sys.argv[1]).read().splitlines()
marker=next(i for i,l in enumerate(text) if 'BEGIN codex-dev zsh completion' in l)
comp=next(i for i,l in enumerate(text) if 'compinit' in l and 'codex-dev' not in l)
assert marker < comp
PY

# Installer tests: complex plugin-manager rc is left untouched with manual guidance.
make_env
cat > "$HOME/.zshrc" <<'ZSHRC'
if [[ -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  source "$HOME/.oh-my-zsh/oh-my-zsh.sh"
fi
ZSHRC
before="$(cat "$HOME/.zshrc")"
( cd "$ROOT" && "$INSTALL" ) > "$TMP/complex.out" 2> "$TMP/complex.err"
after="$(cat "$HOME/.zshrc")"
[[ "$before" == "$after" ]] && ok 'complex plugin-manager .zshrc not modified automatically' || fail 'complex plugin-manager .zshrc modified unexpectedly'
assert_contains "$(cat "$TMP/complex.out" "$TMP/complex.err")" 'source-before-compinit' 'complex .zshrc prints manual source-before-compinit guidance'

# Non-empty unrecognized startup files are ambiguous and should not be auto-modified.
make_env
cat > "$HOME/.zshrc" <<'ZSHRC'
source "$HOME/.zsh/custom-startup.zsh"
ZSHRC
before="$(cat "$HOME/.zshrc")"
( cd "$ROOT" && "$INSTALL" ) > "$TMP/ambiguous.out" 2> "$TMP/ambiguous.err"
after="$(cat "$HOME/.zshrc")"
[[ "$before" == "$after" ]] && ok 'ambiguous nonempty .zshrc not modified automatically' || fail 'ambiguous nonempty .zshrc modified unexpectedly'
assert_contains "$(cat "$TMP/ambiguous.out" "$TMP/ambiguous.err")" 'source-before-compinit' 'ambiguous .zshrc prints manual source-before-compinit guidance'

# Conditional inline compinit is ambiguous and should not be auto-modified.
make_env
cat > "$HOME/.zshrc" <<'ZSHRC'
if [[ -n "$ENABLE_COMPLETION" ]]; then compinit; fi
ZSHRC
before="$(cat "$HOME/.zshrc")"
( cd "$ROOT" && "$INSTALL" ) > "$TMP/conditional.out" 2> "$TMP/conditional.err"
after="$(cat "$HOME/.zshrc")"
[[ "$before" == "$after" ]] && ok 'conditional compinit .zshrc not modified automatically' || fail 'conditional compinit .zshrc modified unexpectedly'
assert_contains "$(cat "$TMP/conditional.out" "$TMP/conditional.err")" 'source-before-compinit' 'conditional compinit .zshrc prints manual guidance'

# Symlinked .zshrc is not replaced or modified automatically.
make_env
mkdir -p "$TMP/dotfiles"
printf 'autoload -Uz compinit\ncompinit\n' > "$TMP/dotfiles/zshrc"
ln -s "$TMP/dotfiles/zshrc" "$HOME/.zshrc"
link_before="$(readlink "$HOME/.zshrc")"
target_before="$(cat "$TMP/dotfiles/zshrc")"
( cd "$ROOT" && "$INSTALL" ) > "$TMP/symlink.out" 2> "$TMP/symlink.err"
[[ -L "$HOME/.zshrc" && "$(readlink "$HOME/.zshrc")" == "$link_before" ]] && ok 'symlinked .zshrc remains a symlink' || fail 'symlinked .zshrc was replaced'
[[ "$(cat "$TMP/dotfiles/zshrc")" == "$target_before" ]] && ok 'symlinked .zshrc target not modified' || fail 'symlinked .zshrc target modified'
assert_contains "$(cat "$TMP/symlink.out" "$TMP/symlink.err")" 'source-before-compinit' 'symlinked .zshrc prints manual source-before-compinit guidance'

# Zsh path literals are single-quoted so quote/semicolon path characters do not inject startup code.
make_env
quoted_home="$TMP/home with quote'and;semi"
mkdir -p "$quoted_home"
( cd "$ROOT" && HOME="$quoted_home" XDG_DATA_HOME="$quoted_home/.local/share" CODEX_DEV_PROJECTS_ROOT="$TMP/projects" "$INSTALL" ) > "$TMP/quoted.out" 2> "$TMP/quoted.err"
quoted_rc="$quoted_home/.zshrc"
quoted_snippet="$quoted_home/.local/share/codex-dev/zsh-completion.zsh"
assert_file_contains "$quoted_rc" "'\''" 'quoted .zshrc source path escapes single quote'
assert_file_contains "$quoted_snippet" "'\''" 'quoted snippet site-functions path escapes single quote'
[[ ! -e "$TMP/injected" ]] && ok 'quoted path install did not create injected file' || fail 'quoted path install created injected file'

manual_home="$TMP/home with \"dbl\" and \$(touch injected) and'quote"
mkdir -p "$manual_home"
printf 'source "$HOME/.zsh/custom-startup.zsh"\n' > "$manual_home/.zshrc"
( cd "$ROOT" && HOME="$manual_home" XDG_DATA_HOME="$manual_home/.local/share" CODEX_DEV_PROJECTS_ROOT="$TMP/projects" "$INSTALL" ) > "$TMP/manual-quote.out" 2> "$TMP/manual-quote.err"
manual_output="$(cat "$TMP/manual-quote.out" "$TMP/manual-quote.err")"
assert_contains "$manual_output" "source '" 'manual guidance uses single-quoted source path'
assert_contains "$manual_output" "'\''" 'manual guidance escapes single quote'
assert_contains "$manual_output" '"dbl"' 'manual guidance preserves literal double quotes'
assert_contains "$manual_output" '$(touch injected)' 'manual guidance keeps command substitution literal inside quoted path'
[[ ! -e "$ROOT/injected" && ! -e "$TMP/injected" ]] && ok 'manual guidance path did not execute command substitution' || fail 'manual guidance path executed command substitution'

# Installer skip controls.
make_env
( cd "$ROOT" && CODEX_DEV_SKIP_COMPLETIONS=1 "$INSTALL" ) >/tmp/codex-dev-skip-comp.out 2>/tmp/codex-dev-skip-comp.err
if [[ ! -e "$XDG_DATA_HOME/zsh/site-functions/_codex-dev" && ! -e "$HOME/.zshrc" ]]; then ok 'CODEX_DEV_SKIP_COMPLETIONS skips completion and rc'; else fail 'CODEX_DEV_SKIP_COMPLETIONS skipped incompletely'; fi
make_env
( cd "$ROOT" && CODEX_DEV_SKIP_RC=1 "$INSTALL" ) >/tmp/codex-dev-skip-rc.out 2>/tmp/codex-dev-skip-rc.err
if [[ -f "$XDG_DATA_HOME/zsh/site-functions/_codex-dev" && ! -e "$HOME/.zshrc" ]]; then ok 'CODEX_DEV_SKIP_RC installs files without rc changes'; else fail 'CODEX_DEV_SKIP_RC behavior'; fi

# Existing user-facing commands still work.
profiles_out="$($CODEX_DEV profiles)"
assert_contains "$profiles_out" 'python' 'profiles still lists python'
help_out="$($CODEX_DEV --help)"
assert_contains "$help_out" 'codex-dev shell <project>' 'help still works'
assert_contains "$help_out" 'codex-dev uninstall' 'help includes uninstall'

# Uninstall abort path: final confirmation refuses all changes after plan output.
make_uninstall_env
write_codex_dev_marker_rc "$HOME/.zshrc"
chmod 0640 "$HOME/.zshrc"
abort_out="$(printf 'y\ny\nn\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$abort_out" 'codex-dev uninstall plan' 'uninstall abort prints plan'
assert_contains "$abort_out" 'Project directories and project .codex-dev metadata will be preserved.' 'uninstall plan states project metadata preservation'
assert_file_exists "$HOME/.local/bin/codex-dev" 'abort keeps installed binary'
assert_file_exists "$XDG_DATA_HOME/zsh/site-functions/_codex-dev" 'abort keeps zsh completion'
assert_file_exists "$XDG_DATA_HOME/codex-dev/zsh-completion.zsh" 'abort keeps zsh snippet'
assert_file_exists "$XDG_CONFIG_HOME/codex-dev/build/cache.txt" 'abort keeps config build cache'
assert_file_contains "$HOME/.zshrc" 'BEGIN codex-dev zsh completion' 'abort keeps zsh marker'
assert_projects_preserved
if [[ ! -e "$PODMAN_LOG" ]]; then ok 'abort performs no podman removals'; else fail "abort unexpectedly removed podman resources: $(cat "$PODMAN_LOG")"; fi

# Confirmed uninstall with image and volume removal.
make_uninstall_env
write_codex_dev_marker_rc "$HOME/.zshrc"
chmod 0640 "$HOME/.zshrc"
confirm_out="$(printf 'y\ny\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$confirm_out" 'Podman images:  remove' 'confirmed uninstall records image removal choice'
assert_contains "$confirm_out" 'Podman volumes: remove' 'confirmed uninstall records volume removal choice'
assert_file_not_exists "$HOME/.local/bin/codex-dev" 'confirmed uninstall removes installed binary'
assert_file_not_exists "$XDG_DATA_HOME/zsh/site-functions/_codex-dev" 'confirmed uninstall removes zsh completion'
assert_dir_not_exists "$XDG_DATA_HOME/codex-dev" 'confirmed uninstall removes codex-dev data dir'
assert_dir_not_exists "$XDG_CONFIG_HOME/codex-dev" 'confirmed uninstall removes codex-dev config dir'
assert_dir_exists "$HOME/.local/bin" 'confirmed uninstall preserves ~/.local/bin parent'
assert_dir_exists "$XDG_DATA_HOME" 'confirmed uninstall preserves XDG data parent'
assert_dir_exists "$XDG_DATA_HOME/zsh" 'confirmed uninstall preserves XDG zsh parent'
assert_dir_exists "$XDG_DATA_HOME/zsh/site-functions" 'confirmed uninstall preserves site-functions parent'
assert_dir_exists "$XDG_CONFIG_HOME" 'confirmed uninstall preserves XDG config parent'
assert_dir_exists "$CODEX_DEV_PROJECTS_ROOT" 'confirmed uninstall preserves projects root'
assert_file_contains "$HOME/.zshrc" 'before' 'confirmed uninstall preserves zshrc content before marker'
assert_file_contains "$HOME/.zshrc" 'after' 'confirmed uninstall preserves zshrc content after marker'
assert_not_contains "$(cat "$HOME/.zshrc")" 'BEGIN codex-dev zsh completion' 'confirmed uninstall removes zsh marker'
mode_after="$(stat -c '%a' "$HOME/.zshrc")"
[[ "$mode_after" == "640" ]] && ok 'confirmed uninstall preserves zshrc mode' || fail "confirmed uninstall changed zshrc mode: $mode_after"
assert_projects_preserved
for project in app-one api_two; do
  rid="$(resource_id_for_test "$project")"
  log_text="$(cat "$PODMAN_LOG")"
  assert_contains "$log_text" "podman rm -f codex-dev-$rid" "$project container removed"
  assert_contains "$log_text" "podman image rm -f localhost/codex-dev/$rid:latest" "$project image removed"
  for kind in home cache npm cargo gradle go; do
    assert_contains "$log_text" "podman volume rm codex-dev-$kind-$rid" "$project $kind volume removed"
  done
done

# Confirmed uninstall can keep images and volumes while still removing containers/local files.
make_uninstall_env
write_codex_dev_marker_rc "$HOME/.zshrc"
keep_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$keep_out" 'Podman images:  keep' 'keep branch records image keep choice'
assert_contains "$keep_out" 'Podman volumes: keep' 'keep branch records volume keep choice'
assert_file_not_exists "$HOME/.local/bin/codex-dev" 'keep branch still removes installed binary'
log_text="$(cat "$PODMAN_LOG")"
assert_contains "$log_text" 'podman rm -f codex-dev-app-one-' 'keep branch removes containers'
assert_not_contains "$log_text" 'podman image rm' 'keep branch does not remove images'
assert_not_contains "$log_text" 'podman volume rm' 'keep branch does not remove volumes'
assert_projects_preserved

# Rootful Podman is rejected before uninstall deletes local files or resources.
make_uninstall_env
write_codex_dev_marker_rc "$HOME/.zshrc"
export PODMAN_ROOTLESS_VALUE=false
if printf 'y\ny\ny\n' | "$CODEX_DEV" uninstall >/tmp/codex-dev-rootful-uninstall.out 2>/tmp/codex-dev-rootful-uninstall.err; then
  fail 'rootful podman uninstall should fail'
else
  ok 'rootful podman uninstall fails closed'
fi
unset PODMAN_ROOTLESS_VALUE
assert_file_exists "$HOME/.local/bin/codex-dev" 'rootful podman keeps installed binary'
assert_file_exists "$XDG_DATA_HOME/zsh/site-functions/_codex-dev" 'rootful podman keeps zsh completion'
assert_file_exists "$XDG_DATA_HOME/codex-dev/zsh-completion.zsh" 'rootful podman keeps zsh snippet'
assert_file_exists "$XDG_CONFIG_HOME/codex-dev/build/cache.txt" 'rootful podman keeps build cache'
assert_file_contains "$HOME/.zshrc" 'BEGIN codex-dev zsh completion' 'rootful podman keeps zsh marker'
if [[ ! -e "$PODMAN_LOG" ]]; then ok 'rootful podman performs no podman removals'; else fail "rootful podman unexpectedly removed resources: $(cat "$PODMAN_LOG")"; fi
assert_projects_preserved

# Extra user files under codex-dev namespaces keep their parent dirs from being pruned.
make_uninstall_env
write_codex_dev_marker_rc "$HOME/.zshrc"
printf 'user config\n' > "$XDG_CONFIG_HOME/codex-dev/user-extra.conf"
printf 'user data\n' > "$XDG_DATA_HOME/codex-dev/user-extra.txt"
printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall >/tmp/codex-dev-extra-files-uninstall.out 2>/tmp/codex-dev-extra-files-uninstall.err
assert_file_not_exists "$XDG_CONFIG_HOME/codex-dev/build/cache.txt" 'extra-file uninstall removes generated build cache file'
assert_file_not_exists "$XDG_DATA_HOME/codex-dev/zsh-completion.zsh" 'extra-file uninstall removes zsh snippet leaf'
assert_file_contains "$XDG_CONFIG_HOME/codex-dev/user-extra.conf" 'user config' 'extra config file preserved'
assert_file_contains "$XDG_DATA_HOME/codex-dev/user-extra.txt" 'user data' 'extra data file preserved'
assert_dir_exists "$XDG_CONFIG_HOME/codex-dev" 'extra config file keeps config dir'
assert_dir_exists "$XDG_DATA_HOME/codex-dev" 'extra data file keeps data dir'
assert_projects_preserved

# Broad custom CODEX_DEV_CONFIG_DIR does not allow automatic build/ recursive deletion.
make_uninstall_env
broad_config="$TMP/broad-config"
mkdir -p "$broad_config/build"
printf 'broad build data\n' > "$broad_config/build/user.txt"
broad_out="$(printf 'n\nn\ny\n' | CODEX_DEV_CONFIG_DIR="$broad_config" "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$broad_out" 'Not automatically removing build directory under broad config path' 'broad config build cleanup is manual'
assert_file_contains "$broad_config/build/user.txt" 'broad build data' 'broad config build data preserved'
assert_dir_exists "$broad_config/build" 'broad config build dir preserved'
assert_projects_preserved

# ZDOTDIR-aware rc cleanup targets ${ZDOTDIR}/.zshrc, not $HOME/.zshrc.
make_uninstall_env
export ZDOTDIR="$TMP/zdot"
mkdir -p "$ZDOTDIR"
printf 'home rc sentinel\n' > "$HOME/.zshrc"
write_codex_dev_marker_rc "$ZDOTDIR/.zshrc"
printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall >/tmp/codex-dev-zdot-uninstall.out 2>/tmp/codex-dev-zdot-uninstall.err
assert_file_contains "$HOME/.zshrc" 'home rc sentinel' 'ZDOTDIR uninstall leaves HOME .zshrc untouched'
assert_file_contains "$ZDOTDIR/.zshrc" 'before' 'ZDOTDIR uninstall preserves rc content before marker'
assert_not_contains "$(cat "$ZDOTDIR/.zshrc")" 'BEGIN codex-dev zsh completion' 'ZDOTDIR uninstall removes marker from ZDOTDIR rc'
unset ZDOTDIR
assert_projects_preserved

# Rc paths containing ':' are handled as paths, not delimiter-encoded strings.
make_uninstall_env
colon_zdot="$TMP/zdot:with:colon"
export ZDOTDIR="$colon_zdot"
mkdir -p "$ZDOTDIR"
write_codex_dev_marker_rc "$ZDOTDIR/.zshrc"
printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall >/tmp/codex-dev-colon-zdot-uninstall.out 2>/tmp/codex-dev-colon-zdot-uninstall.err
assert_file_contains "$ZDOTDIR/.zshrc" 'before' 'colon ZDOTDIR uninstall preserves rc content before marker'
assert_not_contains "$(cat "$ZDOTDIR/.zshrc")" 'BEGIN codex-dev zsh completion' 'colon ZDOTDIR uninstall removes marker from intended rc'
unset ZDOTDIR
assert_projects_preserved

# Symlinked rc is not replaced and its target is not modified.
make_uninstall_env
mkdir -p "$TMP/dotfiles"
write_codex_dev_marker_rc "$TMP/dotfiles/zshrc"
ln -s "$TMP/dotfiles/zshrc" "$HOME/.zshrc"
link_before="$(readlink "$HOME/.zshrc")"
target_before="$(cat "$TMP/dotfiles/zshrc")"
printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall >/tmp/codex-dev-symlink-uninstall.out 2>/tmp/codex-dev-symlink-uninstall.err
[[ -L "$HOME/.zshrc" && "$(readlink "$HOME/.zshrc")" == "$link_before" ]] && ok 'uninstall keeps symlinked zshrc as symlink' || fail 'uninstall replaced symlinked zshrc'
[[ "$(cat "$TMP/dotfiles/zshrc")" == "$target_before" ]] && ok 'uninstall does not modify symlinked zshrc target' || fail 'uninstall modified symlinked zshrc target'
assert_projects_preserved

# Trailing slash on symlinked config dir must not delete the symlink target contents.
make_uninstall_env
rm -rf "$XDG_CONFIG_HOME/codex-dev"
mkdir -p "$TMP/config-real"
printf 'target data\n' > "$TMP/config-real/keep.txt"
ln -s "$TMP/config-real" "$XDG_CONFIG_HOME/codex-dev"
CODEX_DEV_CONFIG_DIR="$XDG_CONFIG_HOME/codex-dev/" printf 'n\nn\ny\n' | CODEX_DEV_CONFIG_DIR="$XDG_CONFIG_HOME/codex-dev/" "$CODEX_DEV" uninstall >/tmp/codex-dev-config-symlink-uninstall.out 2>/tmp/codex-dev-config-symlink-uninstall.err
assert_file_contains "$TMP/config-real/keep.txt" 'target data' 'trailing-slash symlink config target contents preserved'
[[ -L "$XDG_CONFIG_HOME/codex-dev" ]] && ok 'trailing-slash symlink config remains symlink' || fail 'trailing-slash symlink config was removed or replaced'
assert_projects_preserved

# Symlinked XDG_CONFIG_HOME ancestor must not redirect generated directory cleanup.
make_uninstall_env
config_real="$TMP/config-home-real"
config_link="$TMP/config-home-link"
rm -rf "$config_real" "$config_link"
mkdir -p "$config_real/codex-dev/build"
printf 'real build data\n' > "$config_real/codex-dev/build/keep.txt"
ln -s "$config_real" "$config_link"
config_ancestor_out="$(printf 'n\nn\ny\n' | XDG_CONFIG_HOME="$config_link" "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$config_ancestor_out" 'Not automatically removing config build directory through symlinked parent' 'symlinked XDG_CONFIG_HOME build cleanup is manual'
assert_file_contains "$config_real/codex-dev/build/keep.txt" 'real build data' 'symlinked XDG_CONFIG_HOME build target preserved'
assert_dir_exists "$config_real/codex-dev/build" 'symlinked XDG_CONFIG_HOME build dir preserved'
assert_projects_preserved

# Symlinked data parents must not redirect file leaf deletion into their targets.
make_uninstall_env
rm -rf "$XDG_DATA_HOME/codex-dev"
mkdir -p "$TMP/data-real"
printf 'target snippet\n' > "$TMP/data-real/zsh-completion.zsh"
ln -s "$TMP/data-real" "$XDG_DATA_HOME/codex-dev"
data_symlink_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$data_symlink_out" 'Not automatically removing zsh snippet through symlinked parent' 'symlinked data dir snippet is reported for manual cleanup'
assert_file_contains "$TMP/data-real/zsh-completion.zsh" 'target snippet' 'symlinked data dir target snippet preserved'
[[ -L "$XDG_DATA_HOME/codex-dev" ]] && ok 'symlinked data dir remains symlink' || fail 'symlinked data dir was removed or replaced'
assert_projects_preserved

make_uninstall_env
rm -rf "$XDG_DATA_HOME/zsh/site-functions"
mkdir -p "$TMP/site-functions-real"
printf 'target completion\n' > "$TMP/site-functions-real/_codex-dev"
ln -s "$TMP/site-functions-real" "$XDG_DATA_HOME/zsh/site-functions"
site_symlink_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$site_symlink_out" 'Not automatically removing zsh completion through symlinked parent' 'symlinked site-functions completion is reported for manual cleanup'
assert_file_contains "$TMP/site-functions-real/_codex-dev" 'target completion' 'symlinked site-functions target completion preserved'
[[ -L "$XDG_DATA_HOME/zsh/site-functions" ]] && ok 'symlinked site-functions remains symlink' || fail 'symlinked site-functions was removed or replaced'
assert_projects_preserved

# Symlinked XDG_DATA_HOME ancestor must not redirect completion/snippet deletion.
make_uninstall_env
data_home_real="$TMP/data-home-real"
data_home_link="$TMP/data-home-link"
rm -rf "$data_home_real" "$data_home_link"
mkdir -p "$data_home_real/zsh/site-functions" "$data_home_real/codex-dev"
printf 'real completion\n' > "$data_home_real/zsh/site-functions/_codex-dev"
printf 'real snippet\n' > "$data_home_real/codex-dev/zsh-completion.zsh"
ln -s "$data_home_real" "$data_home_link"
data_ancestor_out="$(printf 'n\nn\ny\n' | XDG_DATA_HOME="$data_home_link" "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$data_ancestor_out" 'Not automatically removing zsh completion through symlinked parent' 'symlinked XDG_DATA_HOME completion cleanup is manual'
assert_contains "$data_ancestor_out" 'Not automatically removing zsh snippet through symlinked parent' 'symlinked XDG_DATA_HOME snippet cleanup is manual'
assert_file_contains "$data_home_real/zsh/site-functions/_codex-dev" 'real completion' 'symlinked XDG_DATA_HOME completion target preserved'
assert_file_contains "$data_home_real/codex-dev/zsh-completion.zsh" 'real snippet' 'symlinked XDG_DATA_HOME snippet target preserved'
assert_projects_preserved

# Symlinked ZDOTDIR ancestor must not redirect rc rewrite.
make_uninstall_env
zdot_real="$TMP/zdot-real"
zdot_link="$TMP/zdot-link"
mkdir -p "$zdot_real"
write_codex_dev_marker_rc "$zdot_real/.zshrc"
ln -s "$zdot_real" "$zdot_link"
zdot_target_before="$(cat "$zdot_real/.zshrc")"
zdot_ancestor_out="$(printf 'n\nn\ny\n' | ZDOTDIR="$zdot_link" "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$zdot_ancestor_out" 'Not automatically editing zsh rc through symlinked parent' 'symlinked ZDOTDIR rc cleanup is manual'
[[ "$(cat "$zdot_real/.zshrc")" == "$zdot_target_before" ]] && ok 'symlinked ZDOTDIR rc target preserved' || fail 'symlinked ZDOTDIR rc target was modified'
assert_projects_preserved

# Malformed rc markers are never rewritten automatically.
make_uninstall_env
cat > "$HOME/.zshrc" <<'ZSHRC'
before
# BEGIN codex-dev zsh completion
source /tmp/malformed
after-user-config
ZSHRC
before_malformed="$(cat "$HOME/.zshrc")"
malformed_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$malformed_out" 'Malformed zsh rc marker block will not be modified automatically' 'malformed begin-only marker is reported for manual cleanup'
[[ "$(cat "$HOME/.zshrc")" == "$before_malformed" ]] && ok 'malformed begin-only marker leaves zshrc untouched' || fail 'malformed begin-only marker changed zshrc'
assert_projects_preserved

make_uninstall_env
cat > "$HOME/.zshrc" <<'ZSHRC'
before
# END codex-dev zsh completion
after-user-config
ZSHRC
before_malformed="$(cat "$HOME/.zshrc")"
malformed_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$malformed_out" 'Malformed zsh rc marker block will not be modified automatically' 'malformed end-only marker is reported for manual cleanup'
[[ "$(cat "$HOME/.zshrc")" == "$before_malformed" ]] && ok 'malformed end-only marker leaves zshrc untouched' || fail 'malformed end-only marker changed zshrc'
assert_projects_preserved

make_uninstall_env
cat > "$HOME/.zshrc" <<'ZSHRC'
before
# BEGIN codex-dev zsh completion
source /tmp/outer
# BEGIN codex-dev zsh completion
source /tmp/inner
# END codex-dev zsh completion
after-user-config
ZSHRC
before_malformed="$(cat "$HOME/.zshrc")"
malformed_out="$(printf 'n\nn\ny\n' | "$CODEX_DEV" uninstall 2>&1)"
assert_contains "$malformed_out" 'Malformed zsh rc marker block will not be modified automatically' 'nested marker is reported for manual cleanup'
[[ "$(cat "$HOME/.zshrc")" == "$before_malformed" ]] && ok 'nested marker leaves zshrc untouched' || fail 'nested marker changed zshrc'
assert_projects_preserved

if [[ "$failures" -eq 0 ]]; then
  printf 'All zsh completion tests passed.\n'
  exit 0
fi
printf '%d zsh completion test(s) failed.\n' "$failures" >&2
exit 1
