# Cartridge

A TikTok-style vertical feed where every reel is a playable web game
(Kotlin Multiplatform + Compose app, FastAPI backend, games built in Godot and
hosted on GitHub Pages).

- **Start here (agents and humans):** [`AGENTS.md`](AGENTS.md): current state, repo map, next steps.
- Product and engineering decisions: [`roadmap.md`](roadmap.md)
- Game ideas and their status: [`games/BACKLOG.md`](games/BACKLOG.md)
- How to build a game: [`games/AGENTS.md`](games/AGENTS.md)

Quick run (Android emulator):

```bash
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8123   # API
./gradlew :composeApp:installDebug                                        # app
tools/open_game.sh Minefield                                               # open a game
```
