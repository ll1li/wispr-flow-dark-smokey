#!/usr/bin/env bash
set -euo pipefail

# Installs the wispr-flow-dark-smokey command, applies the theme right away and
# registers a LaunchAgent that re-applies it after Wispr Flow updates.
#
#   curl -fsSL .../install-macos.sh | bash
#   curl -fsSL .../install-macos.sh | bash -s -- --no-auto     # command + theme only
#   ./install-macos.sh --from-clone                             # from a local checkout
#
# Flags: --from-clone  --no-apply  --no-auto

RAW_BASE="https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main"
SCRIPT_NAME="wispr-flow-dark-smokey"
TARGET_DIR="/usr/local/bin"
TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"
FROM_CLONE=0
APPLY=1
AUTO=1

for arg in "$@"; do
  case "$arg" in
    --from-clone) FROM_CLONE=1 ;;
    --no-apply)   APPLY=0 ;;
    --no-auto)    AUTO=0 ;;
    *) echo "Unknown flag: $arg (use --from-clone, --no-apply, --no-auto)"; exit 1 ;;
  esac
done

install_file() {
  local src="$1"
  local dest="$2"

  if [[ -w "$(dirname "$dest")" ]]; then
    install -m 0755 "$src" "$dest"
  else
    sudo install -m 0755 "$src" "$dest"
  fi
}

download_to_target() {
  if [[ -w "$TARGET_DIR" ]]; then
    curl -fsSL "$RAW_BASE/$SCRIPT_NAME" -o "$TARGET_PATH"
    chmod 0755 "$TARGET_PATH"
  else
    curl -fsSL "$RAW_BASE/$SCRIPT_NAME" | sudo tee "$TARGET_PATH" >/dev/null
    sudo chmod 0755 "$TARGET_PATH"
  fi
}

if [[ "$FROM_CLONE" == "1" ]]; then
  SRC="$PWD/$SCRIPT_NAME"
  [[ -f "$SRC" ]] || { echo "Error: $SRC not found. Run from inside the repo clone."; exit 1; }
  install_file "$SRC" "$TARGET_PATH"
else
  download_to_target
fi

echo
echo "Installed to: $TARGET_PATH"

# Apply now, so the theme is on without a second command. A missing Wispr Flow
# or Node.js is reported, not fatal: the command is installed either way.
if [[ "$APPLY" == "1" ]]; then
  echo
  "$TARGET_PATH" --ensure || true     # applies only when missing; a re-run never restarts a themed app
  if ! "$TARGET_PATH" --check; then
    echo "Theme not applied yet (see above). Run '$SCRIPT_NAME' once that is fixed."
  fi
fi

if [[ "$AUTO" == "1" ]]; then
  echo
  "$TARGET_PATH" --enable-auto
fi

echo
echo "Commands:"
echo "  $SCRIPT_NAME --check        # is the theme on?"
echo "  $SCRIPT_NAME --restore      # back to the original look"
echo "  $SCRIPT_NAME --uninstall    # restore, remove the LaunchAgent and the command"
