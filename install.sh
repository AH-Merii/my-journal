#!/bin/sh
# Installs my-journal (the mj command):
#   curl -fsSL https://raw.githubusercontent.com/AH-Merii/my-journal/main/install.sh | sh
#
# Compiles src/main.bend with Bend into ~/.local/bin, where the XDG
# Base Directory spec puts user executables. Bend is only needed to compile,
# not to run.
set -eu

REPO="AH-Merii/my-journal"
DEST="$HOME/.local/bin"
# Bend's update check writes ~/.bend, outside the XDG dirs; skip it.
export BEND_NO_TELEMETRY=1

fail() { printf 'mj: %s\n' "$*" >&2; exit 1; }

command -v mise >/dev/null 2>&1 || command -v bend >/dev/null 2>&1 \
  || fail "prerequisites not found. Install one of these, then rerun this script:
  - Bend: https://github.com/bendlang/bend#get-started
  - mise (installs Bend for you): https://mise.jdx.dev/getting-started.html"

command -v clang >/dev/null 2>&1 \
  || fail "clang (14+) is required to compile; install it with your package manager"

# The source and its mise.toml: this checkout's, else downloaded.
dir=$(cd "$(dirname "$0")" && pwd)
if [ ! -f "$dir/src/main.bend" ] || [ ! -f "$dir/mise.toml" ]; then
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  mkdir "$dir/src"
  for f in mise.toml src/main.bend; do
    curl -fsSL -o "$dir/$f" "https://raw.githubusercontent.com/$REPO/main/$f" \
      || fail "could not download $f from github.com/$REPO"
  done
fi

mkdir -p "$DEST"
cd "$dir"
# mise runs the Bend pinned in mise.toml, installing it if missing.
if command -v mise >/dev/null 2>&1; then
  mise exec github:bendlang/bend -- bend src/main.bend -o "$DEST/mj"
else
  bend src/main.bend -o "$DEST/mj"
fi
echo "installed $DEST/mj"

case ":$PATH:" in
  *":$DEST:"*)
    echo "run 'mj -h' to verify" ;;
  *)
    case "${SHELL##*/}" in
      fish) add="fish_add_path $DEST" ;;
      zsh)  add="echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc" ;;
      *)    add="echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.bashrc" ;;
    esac
    echo "$DEST is not on your PATH; add it with:"
    echo "  $add"
    echo "then open a new shell and run 'mj -h' to verify" ;;
esac
