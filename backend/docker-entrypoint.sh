#!/bin/sh
# Lets the container push catalog.json/config.json to the Pages repo mounted at
# /hosting. Needs GITHUB_TOKEN (fine-grained, contents:write on cartridge-games).
set -e
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper '!f() { echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f'
fi
git config --global user.name "${GIT_AUTHOR_NAME:-Cartridge bot}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-cartridge-bot@users.noreply.github.com}"
git config --global --add safe.directory /hosting
exec "$@"
