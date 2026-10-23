#!/bin/bash
# Publishes a run's screenshots to the `screenshots` branch under <branch>/ (the Screenshots
# workflow's last step): publish_shots.sh <branch> <sha> <dir>.
#
# The branch holds every branch's pictures, gigabytes of them. Checking it out to add a few took
# a quarter of an hour of a macOS runner, so this fetches its trees only, no pictures (a partial
# clone), and writes the new commit straight from an index of its own: the pictures already there
# stay as they are, this run's are added or replace theirs.
set -euo pipefail
branch=$1 sha=$2 dir=$3
export GIT_INDEX_FILE="${RUNNER_TEMP:-/tmp}/screenshots.index"

for attempt in 1 2 3 4 5; do
  rm -f "$GIT_INDEX_FILE"
  if git fetch -q --depth 1 --filter=blob:none origin screenshots 2>/dev/null; then
    parent=(-p FETCH_HEAD)
    git read-tree FETCH_HEAD
  else
    parent=()   # the branch's first run
    git read-tree --empty
  fi
  for f in "$dir"/*.png "$dir"/*.mp4 "$dir"/*.mp4.part-*; do
    [ -e "$f" ] || continue
    git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),$branch/$(basename "$f")"
  done
  git update-index --add --cacheinfo "100644,$(echo "$sha" | git hash-object -w --stdin),$branch/COMMIT"
  tree=$(git write-tree --missing-ok)   # the pictures it doesn't have are on the remote
  if [ ${#parent[@]} -gt 0 ] && [ "$tree" = "$(git rev-parse 'FETCH_HEAD^{tree}')" ]; then exit 0; fi
  commit=$(git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit-tree "$tree" "${parent[@]}" -m "Screenshots of $branch at ${sha::7}")
  # Other branches publish at the same time, each to its own folder: on a clash, start again from theirs.
  git push -q --no-thin origin "${commit:?}:refs/heads/screenshots" && exit 0
  sleep $((attempt * 3))
done
exit 1
