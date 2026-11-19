#!/usr/bin/env bash
repo=/etc/nixos/mandragora
cd "$repo" || exit 1

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)
case "$branch" in
  master | main | DETACHED)
    echo "refusing to run on '$branch'. switch to your work branch first:" >&2
    echo "  git -C $repo checkout work" >&2
    exit 1
    ;;
esac

untracked=$(git ls-files --others --exclude-standard)
if [ -n "$untracked" ]; then
  echo "untracked files are invisible to the flake build. stage the ones you want by path (git add <path>) or move them out:" >&2
  printf '%s\n' "$untracked" | sed 's/^/  /' >&2
  exit 1
fi

echo "==> fetch origin master"
git fetch origin master

echo "==> merge origin/master into $branch"
if ! git -c merge.autoStash=true merge --no-edit FETCH_HEAD; then
  echo "merge conflict. resolve, 'git commit', then re-run mandragora-macos-switch." >&2
  exit 1
fi

echo "==> darwin-rebuild switch"
exec sudo --preserve-env=MANDRAGORA_PERSONAL /run/current-system/sw/bin/darwin-rebuild switch --flake "$repo#mandragora-macos" --impure "$@"
