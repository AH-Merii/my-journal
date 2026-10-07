#!/usr/bin/env bash
# Prints the next release version, from the commits since the last v* tag:
#   bump=<major|minor|patch|none>
#   version=<x.y.z>
# in the form $GITHUB_OUTPUT takes. Each commit is listed on stderr with the
# bump it asks for.
#
# Conventional Commits decide the bump, and the largest one wins:
#   feat!: / fix!: / BREAKING CHANGE:          major
#   feat:                                      minor
#   fix: / perf:                               patch
#   build: chore: ci: docs: refactor: revert:
#   style: test:                               none
# A commit that isn't conventional asks for minor: a change nobody described
# is safer treated as a feature than as a fix. Merge commits are skipped.
set -euo pipefail

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)
if [ -n "$last" ]; then
  base=${last#v}
  range="$last..HEAD"
else
  base=0.0.0
  range=HEAD
fi

rank() {
  case "$1" in
    none) echo 0 ;;
    patch) echo 1 ;;
    minor) echo 2 ;;
    major) echo 3 ;;
  esac
}

# The bump one commit asks for, from its subject and body.
classify() {
  local subject=$1 body=$2
  local type='^([a-z]+)(\([^)]*\))?(!?): '
  if [[ $body =~ (^|$'\n')BREAKING[\ -]CHANGE: ]]; then
    echo major
  elif [[ $subject =~ $type ]]; then
    if [ "${BASH_REMATCH[3]}" = "!" ]; then
      echo major
      return
    fi
    case "${BASH_REMATCH[1]}" in
      feat) echo minor ;;
      fix | perf) echo patch ;;
      build | chore | ci | docs | refactor | revert | style | test) echo none ;;
      *) echo minor ;;
    esac
  else
    echo minor
  fi
}

bump=none
while IFS= read -r sha; do
  subject=$(git log -1 --format=%s "$sha")
  body=$(git log -1 --format=%b "$sha")
  b=$(classify "$subject" "$body")
  printf '%-5s %s %s\n' "$b" "${sha:0:7}" "$subject" >&2
  if [ "$(rank "$b")" -gt "$(rank "$bump")" ]; then
    bump=$b
  fi
done < <(git log --no-merges --format=%H "$range")

IFS=. read -r major minor patch <<<"$base"
case "$bump" in
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  none) version=$base ;;
esac

echo "${last:-no release yet} -> $bump -> $version" >&2
echo "bump=$bump"
echo "version=$version"
