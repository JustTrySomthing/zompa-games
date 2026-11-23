# Cats vs Dogs SDK starter

Build 21 shares a single board layout across all three modes. The turn coin, round feedback, and finale sit above the scoreboards. The scoreboards sit immediately above the board. Zompa provides the centered pause panel.

This source demonstrates Single Player, Pass & Play, and Online 2 Player with the shared `turns-v1` Zompa protocol.

- `zompa.json` declares the game's identity, modes, and compatible player build.
- `rules.lua` contains board validation and the computer strategy.
- `main.lua` schedules input and replays online moves. Each move is a column token. Both phones use the package's game rules.
- `view.lua` lays out the board and touch controls in the canvas Zompa provides.
- `how-to-play.txt` supplies Help to the host toolbar.
- `zompa.lua` is the shared SDK module. Copy it from the SDK without editing it.

The legacy save reader exists for earlier Cats vs Dogs releases. New games can save and resume rounds directly with the SDK session helpers.
