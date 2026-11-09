#!/usr/bin/env zsh
# REX-SESH INSTALLER.
# USAGE: ./install.sh [install|uninstall|plist] [--no-notify] [--copy]
# ENV:
#   BIN_DIR         TARGET DIR FOR rex-sesh. DEFAULT ~/.local/bin.
#   REX_CONFIG_DIR  REX CONFIG DIR. DEFAULT ${XDG_CONFIG_HOME:-~/.config}/rex.
#   REX_SESH_KEY    PICKER KEY. DEFAULT ctrl+space>shift+t.
#   REX_SERVER      REX SERVER ADDRESS FOR LAUNCHD. DEFAULT MAC APP SOCKET.

emulate -L zsh
setopt err_return pipefail

REPO="${0:A:h}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
REX_CONFIG_DIR="${REX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rex}"
REX_SESH_KEY="${REX_SESH_KEY:-ctrl+space>shift+t}"
LABEL="local.rex-notify"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/rex-notify.log"
MARK_BEGIN="-- >>> rex-sesh >>>"
MARK_END="-- <<< rex-sesh <<<"

NOTIFY=1
COPY=0
CMD="install"

for arg in "$@"; do
  case "$arg" in
    install|uninstall|plist) CMD="$arg" ;;
    --no-notify) NOTIFY=0 ;;
    --copy)      COPY=1 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      print -u2 "UNKNOWN ARGUMENT: $arg"
      exit 2
      ;;
  esac
done

# OUTPUT HELPERS.
ok()   { print -P "%F{green}OK%f    $*" }
warn() { print -P "%F{yellow}WARN%f  $*" }
fail() { print -P "%F{red}FAIL%f  $*" >&2; exit 1 }

# FIND REX CLI. PATH FIRST, THEN SERVER INSTALL, THEN APP BUNDLE.
find_rex() {
  local candidates=(
    "${commands[rex]}"
    "$REX_BIN_DIR/rex"
    "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
    "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
    "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
  )
  local c
  for c in $candidates; do
    [[ -n "$c" && -x "$c" ]] && { print -r -- "$c"; return 0 }
  done
  return 1
}

# CHECK REQUIRED AND OPTIONAL TOOLS.
check_deps() {
  local missing=() tool
  find_rex >/dev/null || missing+=(rex)
  for tool in fzf jq zoxide fd; do
    (( $+commands[$tool] )) || missing+=($tool)
  done
  if (( NOTIFY )) && ! (( $+commands[terminal-notifier] )); then
    missing+=(terminal-notifier)
  fi
  if (( ${#missing} )); then
    fail "MISSING TOOLS: ${missing[*]}. INSTALL WITH: brew install ${${missing:#rex}[*]}"
  fi
  for tool in eza sesh; do
    (( $+commands[$tool] )) || warn "OPTIONAL TOOL NOT FOUND: $tool"
  done
  ok "TOOLS FOUND"
}

# LINK OR COPY SRC TO DST. MOVE OLD FILE TO .bak.<TIME>.
place() {
  local src="$1" dst="$2"
  mkdir -p "${dst:h}"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    ok "ALREADY LINKED: $dst"
    return 0
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    warn "OLD FILE MOVED: $bak"
  fi
  if (( COPY )); then
    cp "$src" "$dst"
    ok "COPIED: $dst"
  else
    ln -s "$src" "$dst"
    ok "LINKED: $dst -> $src"
  fi
}

# REMOVE DST IF IT IS A LINK INTO THIS REPO.
unplace() {
  local dst="$1"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$REPO"/* ]]; then
    rm "$dst"
    ok "REMOVED: $dst"
  elif [[ -e "$dst" ]]; then
    warn "NOT A LINK TO THIS REPO. LEFT IN PLACE: $dst"
  fi
}

# ADD REQUIRE BLOCK TO INIT.LUA. SKIP IF BLOCK EXISTS.
add_init_block() {
  local init="$REX_CONFIG_DIR/init.lua"
  mkdir -p "$REX_CONFIG_DIR"
  touch "$init"
  if grep -qF -e "$MARK_BEGIN" "$init"; then
    ok "INIT.LUA BLOCK EXISTS"
  else
    # ADD NEWLINE IF LAST LINE HAS NONE.
    if [[ -s "$init" && -n "$(tail -c1 "$init")" ]]; then
      print "" >> "$init"
    fi
    {
      print -r -- "$MARK_BEGIN"
      print -r -- "require(\"rex-sesh\").setup{"
      print -r -- "  bin = \"$BIN_DIR/rex-sesh\","
      print -r -- "  key = \"$REX_SESH_KEY\","
      print -r -- "}"
      print -r -- "$MARK_END"
    } >> "$init"
    ok "INIT.LUA BLOCK ADDED. KEY: $REX_SESH_KEY"
  fi
  # WARN ON OLD INLINE ACTION OUTSIDE BLOCK.
  if sed "/$MARK_BEGIN/,/$MARK_END/d" "$init" | grep -qE 'name[[:space:]]*=[[:space:]]*"sesh_picker"'; then
    warn "INIT.LUA HAS AN INLINE sesh_picker ACTION. REMOVE IT. THE MODULE DEFINES IT NOW."
  fi
}

# REMOVE REQUIRE BLOCK FROM INIT.LUA.
remove_init_block() {
  local init="$REX_CONFIG_DIR/init.lua"
  [[ -f "$init" ]] || return 0
  if grep -qF -e "$MARK_BEGIN" "$init"; then
    sed -i '' "/$MARK_BEGIN/,/$MARK_END/d" "$init"
    ok "INIT.LUA BLOCK REMOVED"
  fi
}

# ESCAPE VALUE FOR SED REPLACEMENT.
sed_escape() {
  print -r -- "$1" | sed -e 's/[&|\\]/\\&/g'
}

# PRINT PLIST FROM TEMPLATE.
render_plist() {
  local rex notifier server
  rex=$(find_rex) || fail "REX CLI NOT FOUND"
  notifier="${commands[terminal-notifier]:-/opt/homebrew/bin/terminal-notifier}"
  server="${REX_SERVER:-unix://${HOME// /%20}/Library/Application%20Support/rex/server.sock}"
  sed \
    -e "s|@REX@|$(sed_escape "$rex")|g" \
    -e "s|@NOTIFY_LUA@|$(sed_escape "$REX_CONFIG_DIR/rex-notify.lua")|g" \
    -e "s|@REX_SERVER@|$(sed_escape "$server")|g" \
    -e "s|@NOTIFIER@|$(sed_escape "$notifier")|g" \
    -e "s|@LOG@|$(sed_escape "$LOG")|g" \
    "$REPO/launchd/$LABEL.plist.in"
}

# WRITE PLIST AND LOAD LAUNCHD AGENT.
install_notify() {
  [[ "$(uname)" == Darwin ]] || { warn "NOT MACOS. NOTIFY SKIPPED."; return 0 }
  mkdir -p "${PLIST:h}" "${LOG:h}"
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  render_plist > "$PLIST"
  plutil -lint "$PLIST" >/dev/null || fail "BAD PLIST: $PLIST"
  launchctl bootstrap "gui/$UID" "$PLIST"
  ok "LAUNCHD AGENT LOADED: $LABEL. LOG: $LOG"
}

# UNLOAD LAUNCHD AGENT AND REMOVE PLIST.
uninstall_notify() {
  [[ "$(uname)" == Darwin ]] || return 0
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  if [[ -f "$PLIST" ]]; then
    rm "$PLIST"
    ok "LAUNCHD AGENT REMOVED: $LABEL"
  fi
}

# CHECK INIT.LUA, THEN RELOAD REX CONFIG. IGNORE RELOAD FAIL IF SERVER IS DOWN.
reload_rex() {
  local rex out
  rex=$(find_rex) || return 0
  local init="$REX_CONFIG_DIR/init.lua"
  if [[ -f "$init" ]] && ! out=$("$rex" config check "$init" 2>&1); then
    print -r -- "$out" | grep -E '^(error|warning)' >&2
    fail "INIT.LUA HAS ERRORS. FIX THEM, THEN RUN: rex config reload"
  fi
  if "$rex" --autostart=false config reload >/dev/null 2>&1; then
    ok "REX CONFIG RELOADED"
  else
    warn "REX CONFIG NOT RELOADED. RUN: rex config reload"
  fi
}

do_install() {
  check_deps
  place "$REPO/bin/rex-sesh" "$BIN_DIR/rex-sesh"
  place "$REPO/rex/rex-sesh.lua" "$REX_CONFIG_DIR/rex-sesh.lua"
  add_init_block
  if (( NOTIFY )); then
    place "$REPO/rex/rex-notify.lua" "$REX_CONFIG_DIR/rex-notify.lua"
    install_notify
  fi
  reload_rex
  [[ ":$PATH:" == *":$BIN_DIR:"* ]] || warn "$BIN_DIR IS NOT ON PATH. REX USES THE FULL PATH, SO THE PICKER STILL WORKS."
}

do_uninstall() {
  if (( NOTIFY )); then
    uninstall_notify
  fi
  remove_init_block
  unplace "$REX_CONFIG_DIR/rex-notify.lua"
  unplace "$REX_CONFIG_DIR/rex-sesh.lua"
  unplace "$BIN_DIR/rex-sesh"
  reload_rex
}

case "$CMD" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  plist)     render_plist ;;
esac
