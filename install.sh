#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(id -u)" == "0" ]]; then
  printf '[codex-dev] ERROR: Do not install as root. Run ./install.sh as your normal Fedora user.\n' >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
install -m 0755 "$SRC_DIR/codex-dev" "$BIN_DIR/codex-dev"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-dev"
mkdir -p "$CONFIG_DIR" "$CONFIG_DIR/build" "$HOME/Projects"

ZSH_COMPLETION_STATUS="skipped"
ZSH_RC_STATUS="skipped"
XDG_DATA_HOME_EFFECTIVE="${XDG_DATA_HOME:-$HOME/.local/share}"
ZSH_SITE_FUNCTIONS="$XDG_DATA_HOME_EFFECTIVE/zsh/site-functions"
CODEX_DEV_DATA_DIR="$XDG_DATA_HOME_EFFECTIVE/codex-dev"
ZSH_COMPLETION_FILE="$ZSH_SITE_FUNCTIONS/_codex-dev"
ZSH_SNIPPET_FILE="$CODEX_DEV_DATA_DIR/zsh-completion.zsh"
ZDOTDIR_EFFECTIVE="${ZDOTDIR:-$HOME}"
ZSHRC="$ZDOTDIR_EFFECTIVE/.zshrc"
MARKER_BEGIN="# BEGIN codex-dev zsh completion"
MARKER_END="# END codex-dev zsh completion"

fatal() {
  printf '[codex-dev] ERROR: %s\n' "$*" >&2
  exit 1
}

validate_zsh_path_literal() {
  local label="$1" path="$2"
  [[ -n "$path" ]] || fatal "$label must not be empty."
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || fatal "$label must not contain newline characters."
}

zsh_single_quote() {
  local s="$1" out="'" ch i
  validate_zsh_path_literal "Zsh path literal" "$s"
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    if [[ "$ch" == "'" ]]; then
      out+="'\\''"
    else
      out+="$ch"
    fi
  done
  out+="'"
  printf '%s' "$out"
}

write_marker_block() {
  local snippet_quoted
  snippet_quoted="$(zsh_single_quote "$ZSH_SNIPPET_FILE")"
  cat <<EOF_MARKER
$MARKER_BEGIN
source $snippet_quoted
$MARKER_END
EOF_MARKER
}

preserve_rc_mode() {
  local src="$1" dst="$2"
  chmod --reference="$src" "$dst" 2>/dev/null || chmod "$(stat -c '%a' "$src" 2>/dev/null || printf '0600')" "$dst" 2>/dev/null || true
}

make_rc_temp() {
  local rc="$1" dir base tmp
  dir="$(dirname "$rc")"
  base="$(basename "$rc")"
  tmp="$(mktemp "$dir/.$base.codex-dev.XXXXXX")" || fatal "Failed to create temporary rc file next to $rc"
  cp -p -- "$rc" "$tmp" 2>/dev/null || preserve_rc_mode "$rc" "$tmp"
  : > "$tmp"
  printf '%s' "$tmp"
}

replace_existing_marker() {
  local rc="$1" tmp in_marker=0 replaced=0
  tmp="$(make_rc_temp "$rc")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$MARKER_BEGIN" ]]; then
      if [[ "$replaced" -eq 0 ]]; then
        write_marker_block >> "$tmp"
        replaced=1
      fi
      in_marker=1
      continue
    fi
    if [[ "$line" == "$MARKER_END" && "$in_marker" -eq 1 ]]; then
      in_marker=0
      continue
    fi
    [[ "$in_marker" -eq 1 ]] && continue
    printf '%s\n' "$line" >> "$tmp"
  done < "$rc"
  preserve_rc_mode "$rc" "$tmp"
  mv "$tmp" "$rc"
}

first_compinit_line() {
  local rc="$1" line trimmed lineno=0
  local semicolon_re='^autoload[[:space:]]+-U[z]?[[:space:]]+compinit[[:space:]]*;[[:space:]]*compinit([[:space:]].*)?$'
  local and_re='^autoload[[:space:]]+-U[z]?[[:space:]]+compinit[[:space:]]*&&[[:space:]]*compinit([[:space:]].*)?$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    trimmed="${line#${line%%[![:space:]]*}}"
    trimmed="${trimmed%${trimmed##*[![:space:]]}}"
    [[ "$trimmed" == \#* || -z "$trimmed" ]] && continue
    if [[ "$trimmed" == "compinit" || "$trimmed" == compinit\ -* ]]; then
      printf '%s\n' "$lineno"
      return 0
    fi
    if [[ "$trimmed" =~ ^autoload[[:space:]]+-U[z]?[[:space:]]+compinit$ ]]; then
      printf '%s\n' "$lineno"
      return 0
    fi
    if [[ "$trimmed" =~ $semicolon_re || "$trimmed" =~ $and_re ]]; then
      printf '%s\n' "$lineno"
      return 0
    fi
  done < "$rc"
  return 1
}

has_complex_zsh_manager() {
  local rc="$1"
  grep -Eiq 'oh-my-zsh|antigen|zinit|zplug|prezto|antidote|sheldon|zgen' "$rc"
}

has_zsh_startup_content() {
  local rc="$1" line trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#${line%%[![:space:]]*}}"
    [[ "$trimmed" == \#* || -z "$trimmed" ]] && continue
    return 0
  done < "$rc"
  return 1
}

insert_marker_before_line() {
  local rc="$1" line_no="$2" tmp lineno=0 inserted=0 line
  tmp="$(make_rc_temp "$rc")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    if [[ "$lineno" -eq "$line_no" && "$inserted" -eq 0 ]]; then
      write_marker_block >> "$tmp"
      inserted=1
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$rc"
  if [[ "$inserted" -eq 0 ]]; then
    write_marker_block >> "$tmp"
  fi
  preserve_rc_mode "$rc" "$tmp"
  mv "$tmp" "$rc"
}

append_marker() {
  local rc="$1"
  {
    [[ -s "$rc" ]] && printf '\n'
    write_marker_block
  } >> "$rc"
}

install_zsh_completion() {
  if [[ "${CODEX_DEV_SKIP_COMPLETIONS:-0}" == "1" ]]; then
    ZSH_COMPLETION_STATUS="skipped by CODEX_DEV_SKIP_COMPLETIONS=1"
    ZSH_RC_STATUS="skipped by CODEX_DEV_SKIP_COMPLETIONS=1"
    return 0
  fi

  mkdir -p "$ZSH_SITE_FUNCTIONS" "$CODEX_DEV_DATA_DIR"
  "$BIN_DIR/codex-dev" completion zsh --command "$BIN_DIR/codex-dev" > "$ZSH_COMPLETION_FILE"
  chmod 0644 "$ZSH_COMPLETION_FILE"
  local site_functions_quoted
  site_functions_quoted="$(zsh_single_quote "$ZSH_SITE_FUNCTIONS")"
  cat > "$ZSH_SNIPPET_FILE" <<EOF_SNIPPET
# codex-dev Zsh completion setup. Source this before compinit when possible.
_codex_dev_site_functions=$site_functions_quoted
if [[ -d "\$_codex_dev_site_functions" ]]; then
  case " \${fpath[*]} " in
    *" \$_codex_dev_site_functions "*) ;;
    *) fpath=("\$_codex_dev_site_functions" \$fpath) ;;
  esac
fi
if ! (( \$+functions[compdef] )); then
  autoload -Uz compinit
  compinit
fi
EOF_SNIPPET
  chmod 0644 "$ZSH_SNIPPET_FILE"
  ZSH_COMPLETION_STATUS="installed: $ZSH_COMPLETION_FILE"

  if [[ "${CODEX_DEV_SKIP_RC:-0}" == "1" ]]; then
    ZSH_RC_STATUS="rc skipped by CODEX_DEV_SKIP_RC=1"
    return 0
  fi

  mkdir -p "$ZDOTDIR_EFFECTIVE"
  if [[ -L "$ZSHRC" ]]; then
    ZSH_RC_STATUS="manual source-before-compinit required for symlinked $ZSHRC"
    return 0
  fi

  if [[ -f "$ZSHRC" ]] && grep -Fq "$MARKER_BEGIN" "$ZSHRC"; then
    replace_existing_marker "$ZSHRC"
    ZSH_RC_STATUS="updated existing marker in $ZSHRC"
    return 0
  fi

  if [[ ! -e "$ZSHRC" ]]; then
    write_marker_block > "$ZSHRC"
    ZSH_RC_STATUS="created marker in $ZSHRC"
    return 0
  fi

  local compinit_line=""
  compinit_line="$(first_compinit_line "$ZSHRC" || true)"
  if [[ -n "$compinit_line" ]]; then
    insert_marker_before_line "$ZSHRC" "$compinit_line"
    ZSH_RC_STATUS="inserted marker before first recognizable compinit in $ZSHRC"
  elif has_complex_zsh_manager "$ZSHRC" || has_zsh_startup_content "$ZSHRC"; then
    ZSH_RC_STATUS="manual source-before-compinit required for $ZSHRC"
  else
    append_marker "$ZSHRC"
    ZSH_RC_STATUS="appended marker to empty $ZSHRC"
  fi
}

install_zsh_completion

cat <<MSG
Installed: $BIN_DIR/codex-dev
Config:    $CONFIG_DIR
Projects:  $HOME/Projects
Zsh completion: $ZSH_COMPLETION_STATUS
Zsh rc:         $ZSH_RC_STATUS

Next steps:
  1. Ensure ~/.local/bin is in PATH:
       export PATH="\$HOME/.local/bin:\$PATH"

  2. Open a new Zsh, or run:
       exec zsh

  3. Check the host/container safety baseline:
       codex-dev doctor

  4. Create a project:
       codex-dev init demo python
       codex-dev build demo
       codex-dev codex demo
MSG

if [[ "$ZSH_RC_STATUS" == manual* ]]; then
  ZSH_SNIPPET_FILE_QUOTED="$(zsh_single_quote "$ZSH_SNIPPET_FILE")"
  cat <<MSG

Manual Zsh completion step:
  Source the installed helper snippet before your existing compinit/plugin-manager completion initialization:
       source $ZSH_SNIPPET_FILE_QUOTED
  Note: the completion function itself was installed under:
       $ZSH_COMPLETION_FILE
  Keyword: source-before-compinit
MSG
fi
