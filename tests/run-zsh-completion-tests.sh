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
for c in setup init profiles list config edit edit-build-script build shell codex enter exec doctor volumes reset-cache reset-home nuke-env completion; do
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

if [[ "$failures" -eq 0 ]]; then
  printf 'All zsh completion tests passed.\n'
  exit 0
fi
printf '%d zsh completion test(s) failed.\n' "$failures" >&2
exit 1
