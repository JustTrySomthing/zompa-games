# Fortress: The Badlands — playable prototype v0.2.0

Early-access Zompa game update, build 2. Same stable game ID `fortress-badlands`, delivered through **Games → Get Games**. Player 1 is at the bottom. The game uses a 7-column × 13-row honeycomb board, symmetric ten-unit army, neutral Badlands, and no individual terrain capture.

## Improved usability (v0.2.0)

- Class-colored soldiers have distinctive vector symbols (crossed swords, axe, bow, staff, shield) and visible faction rings. No final artwork is required for clarity.
- Tap a piece to show a prominent, nonblocking character card with name, ownership, HP bar, Move, Capture reach, fixed Hit and shared D8. Opponent pieces can be inspected.
- Green targets indicate empty destinations; red rings are drawn **over** enemy tokens to indicate available captures. Tap the actual enemy to attack. Out-of-range attacks explain why they cannot proceed.
- Battle dialog displays both D8 rolls, the winner of each exchange, fixed damage applied, remaining HP, the victory potion, and a Continue button. A winner taking an enemy's hex is shown on return to the board.
- The first-turn info panel provides concise instructions and a legend showing each class symbol and name abbreviation.

## Current balanced rules

| Class | Per side | HP | Move | Capture | Fixed Hit | Die |
|---|---:|---:|---:|---:|---:|---|
| Warrior | 3 | 19 | 2 | 1 | 5 | D8 |
| Barbarian | 2 | 25 | 1 | 1 | 5 | D8 |
| Archer | 2 | 15 | 2 | 3 | 7 | D8 |
| Wizard | 1 | 18 | 1 | 2 | 7 | D8 |
| Knight | 2 | 15 | 3 | 1 | 5 | D8 |

Each turn a player selects one soldier and moves to an empty reachable hex or captures an enemy within that soldier's capture reach and clear sight. Neither movement nor capture may jump through units. If an attack succeeds, the attacker occupies the defender's hex; if it fails, the defender stays put. Both roll D8 every exchange; higher roll inflicts its fixed Hit and ties deal no damage. Ordinary soldier battles cannot eliminate both simultaneously. A surviving soldier restores random 4–10 HP after defeating another soldier, capped at maximum.

Fortress: **35 HP, D8, fixed 5 defensive damage**, no movement or healing; destruction is the only normal victory. When both armies perish before fortress destruction, simultaneous trebuchet volleys use independent D8 rolls; each rolls at least 4 to hit for **7 damage**, so either, neither, or both may hit. Double-fortress destruction produces the *Mutually Assured Destruction* ending.

## SDK compliance

- Runtime: LÖVE 11.5; exact official `zompa.lua` SDK v4, no edits.
- Manifest: schema 1; `minZompaBuild`: 56; `onlineProtocol`: `turns-v1`; modes `solo`, `local`, `online`; `localSaves`: true.
- SDK `loadSession`/`saveSession`/`clearSession` for local sessions, `readTurns`/`submitTurn` for online matches, and host-owned toolbar and audio. All state changes replay deterministically from action tokens and a shared match seed.
- No Chatmail, network calls, permission handling, or game-specific online backend in the package.

## Tests and limitations

- `python3 tests/run_lua.py tests/smoke.lua tests/ui_smoke.lua tests/ux_smoke.lua tests/autoplay.lua` validates legal movement, capture replacement, fixed-damage rolls, healing, Fortress outcomes, simultaneous Siege, deterministic save/replay, simulated taps/cards and layout at four portrait sizes.
- 160 automated complete matches at v0.2.0 completed with zero turn-limit stalls (129 normal Fortress victories, 27 Final Siege victories, 4 mutually assured destruction). Those are scripted tactical opponents, not human playtests.
- Gameplay and three mode SDK contracts have been checked with Lua mock tests. Real-device visual layout, two-phone online turns, accessibility, and competitive randomness must still be checked on Android. Online seed contributions synchronize deterministic rolls, but are not cryptographically fair against a malicious modified client.

This prototype is early access and will receive further updates through Zompa **Get Games**, not a separate app or download workflow.