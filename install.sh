#!/bin/sh
# Installs mj, the my-journal command, from a GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/AH-Merii/my-journal/main/install.sh | sh
# Set MJ_VERSION (e.g. v0.1.0 or 0.1.0) to install that version instead of the
# latest.
#
# The binary goes in ~/.local/bin, where the XDG Base Directory spec puts
# user executables.
set -eu

# CI fails until this matches the repo it runs in, so a rename or fork
# can't publish an installer pointing elsewhere.
REPO="AH-Merii/my-journal"
DEST="$HOME/.local/bin"

fail() { printf 'mj: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# linux or darwin, as named in the release files.
detect_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo darwin ;;
    *) fail "no prebuilt binary for $(uname -s)" ;;
  esac
}

# x64 or arm64, as named in the release files.
detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo x64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) fail "no prebuilt binary for $(uname -m)" ;;
  esac
}

# The release tag to install: MJ_VERSION, with or without its leading v, or
# the latest release's. The latest is looked up once, so the tarball and
# checksums.txt can't come from two releases if one is published in between.
release_tag() {
  if [ -n "${MJ_VERSION:-}" ]; then
    echo "v${MJ_VERSION#v}"
    return
  fi
  # releases/latest redirects to releases/tag/<tag>, or to releases if
  # there are none.
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest") \
    || fail "could not look up the latest release of $REPO"
  case "$latest" in
    */releases/tag/*) echo "${latest##*/}" ;;
    *) fail "$REPO has no releases yet" ;;
  esac
}

# Downloads the binary's tarball and the release checksums into the
# current directory.
download() { # url file
  for f in "$2" checksums.txt; do
    curl -fsSL -o "$f" "$1/$f" || fail "could not download $1/$f"
  done
}

# Checks file against its line in checksums.txt.
verify() { # file
  if have sha256sum; then
    sha="sha256sum"
  elif have shasum; then
    sha="shasum -a 256"
  else
    fail "sha256sum or shasum is required to verify the download"
  fi
  # The line whose file name field is exactly $1.
  line=$(awk -v f="$1" '$2 == f' checksums.txt)
  [ -n "$line" ] || fail "checksums.txt has no line for $1"
  echo "$line" | $sha -c - >/dev/null 2>&1 \
    || fail "$1 does not match its checksum"
}

# Unpacks mj from the tarball into DEST. Moving it from the temporary directory
# may copy it across filesystems, so it lands next to the old mj first and is
# then renamed over it: an interrupted install never leaves half an mj.
unpack() { # file
  tar -xzf "$1" mj
  mkdir -p "$DEST"
  mv mj "$DEST/.mj.new"
  mv "$DEST/.mj.new" "$DEST/mj"
}

# Says how to run mj, or how to put DEST on the PATH first.
path_hint() {
  case ":$PATH:" in
    *":$DEST:"*)
      echo "run 'mj -h' to verify"
      return ;;
  esac
  shell=${SHELL:-}
  case "${shell##*/}" in
    fish) add="fish_add_path $DEST" ;;
    zsh)  add="echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc" ;;
    *)    add="echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.bashrc" ;;
  esac
  echo "$DEST is not on your PATH; add it with:"
  echo "  $add"
  echo "then open a new shell and run 'mj -h' to verify"
}

main() {
  # One substitution per line, so set -e catches each failing.
  os=$(detect_os)
  arch=$(detect_arch)
  file="mj-$os-$arch.tar.gz"
  tag=$(release_tag)
  url="https://github.com/$REPO/releases/download/$tag"

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  cd "$tmp"
  download "$url" "$file"
  verify "$file"
  unpack "$file"
  echo "installed mj $tag in $DEST"
  path_hint
}

# Called last, so a download of this script cut short runs nothing.
main
