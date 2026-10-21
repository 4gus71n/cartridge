#!/bin/bash
# Copy shared game code (games/_shared/*.gd) into every Godot game's scripts/.
# Godot projects can't import files outside their folder, so each game carries
# a copy. Edit the file in games/_shared, then run this.
set -e
cd "$(dirname "$0")/../games"
for project in */project.godot; do
  game=$(dirname "$project")
  for f in _shared/*.gd; do
    cp "$f" "$game/scripts/$(basename "$f")"
  done
  echo "synced $game"
done
