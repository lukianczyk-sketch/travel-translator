#!/usr/bin/env bash
# Commits the tail of build.log to buildlogs/<platform>.log so it can be read
# through the GitHub API. "[skip ci]" keeps this commit from re-triggering builds.
set -e
PLATFORM="$1"
mkdir -p buildlogs
SRC="${LOG_SRC:-build.log}"
if [ -f "$SRC" ]; then
  tail -c 120000 "$SRC" > "buildlogs/${PLATFORM}.log"
else
  echo "no build.log captured" > "buildlogs/${PLATFORM}.log"
fi
git config user.name "build-bot"
git config user.email "build-bot@users.noreply.github.com"
for attempt in 1 2 3 4 5; do
  git fetch -q origin main
  git reset -q --mixed origin/main || true
  git add -f "buildlogs/${PLATFORM}.log"
  git commit -qm "build log: ${PLATFORM} [skip ci]" || true
  if git push -q origin HEAD:main; then
    echo "log published"
    exit 0
  fi
  sleep $((attempt * 5))
done
echo "could not publish log"
