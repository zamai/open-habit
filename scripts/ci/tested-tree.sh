#!/bin/bash
# Release gate: remembers which source trees passed scripts/ci/test.sh.
#   tested-tree.sh tree            print the working tree's hash (tracked and staged files)
#   tested-tree.sh record <tree>   stamp that tree as passing
#   tested-tree.sh check <commit>  fail unless <commit> is on origin/main and its tree was stamped
# A pass is keyed by tree content, so testing before committing still counts for the commit.
# Stamps live in the shared git dir, so every worktree sees them.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMPS="$(git rev-parse --git-common-dir)/tested-trees"

working_tree() {
  local index
  index=$(mktemp)
  cp "$(git rev-parse --git-path index)" "$index"
  GIT_INDEX_FILE="$index" git add -u
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

case "${1:-}" in
  tree)
    working_tree
    ;;
  record)
    tree="${2:?usage: tested-tree.sh record <tree>}"
    mkdir -p "$STAMPS"
    date -u +%FT%TZ > "$STAMPS/$tree"
    echo "Recorded test pass for tree ${tree:0:12}"
    ;;
  check)
    commit=$(git rev-parse --verify "${2:?usage: tested-tree.sh check <commit>}^{commit}")
    git fetch -q origin main
    if ! git merge-base --is-ancestor "$commit" origin/main; then
      echo "Release gate: ${commit:0:12} is not on origin/main. Land it on main and push first." >&2
      exit 1
    fi
    tree=$(git rev-parse "$commit^{tree}")
    if [[ ! -f "$STAMPS/$tree" ]]; then
      echo "Release gate: no passing scripts/ci/test.sh run for ${commit:0:12}. Run it on this exact content first." >&2
      exit 1
    fi
    echo "Release gate: ${commit:0:12} is on origin/main and passed tests at $(cat "$STAMPS/$tree")"
    ;;
  *)
    echo "usage: tested-tree.sh tree | record <tree> | check <commit>" >&2
    exit 2
    ;;
esac
