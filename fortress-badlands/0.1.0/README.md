# Fortress: The Badlands (working title) — Zompa prototype

Version 0.1.0 (build 1); rules baseline November 23, 2026. **Not a published or Android-tested release.**

A portrait honeycomb hex strategy game for Zompa with the approved 10-unit armies, alternate single actions, simultaneous battle dice, a 30 HP / D8 Fortress, automatic 4–10 HP winner healing, and a D12 Final Siege after both armies are eliminated. Two players start at opposite ends with neutral Badlands in between. No individual territory ownership.

## SDK compatibility

- LÖVE 11.5. The root `zompa.lua` is a byte-for-byte copy of the official Zompa v4 SDK in `JustTrySomthing/zompa/sdk/zompa.lua`, blob `7c094c86be6dab9b63b5bd4970de9fa76f74be79`.
- Manifest uses `onlineProtocol: turns-v1`, `minZompaBuild: 56`, and all three modes: `solo`, `local`, `online`.
- The Zompa host manages online invitations, encrypted turn transport, modes, pause, Back, audio settings, help, and session startup. Game contains no Chatmail or external network implementation.
- Solo and Pass & Play save unfinished games through `zompa.saveSession()` using a versioned action log; online games rebuild from `zompa.readTurns()` and submit validated move tokens with `zompa.submitTurn()`.
- Two initial online turns each include a random nonce to combine a common match seed before any dice rolls. This is prototype synchronization, **not cheat-resistant competitive randomness**; server-independent adversarial fairness requires additional protocol design and host support.
- A side that loses all soldiers automatically passes until its opponent attacks a Fortress; if both armies are lost, the Final Siege resolves immediately.

## Test locally

From the game directory: `love .` (requires LÖVE 11.5). No external art/assets are needed. This is a functional graybox implementation.

From the Zompa Android repo: `python3 sdk/zomp.py build <game-dir> /tmp/Fortress-Badlands-v0.1.0.zomp --require-three-modes`; then `python3 sdk/zomp.py check /tmp/Fortress-Badlands-v0.1.0.zomp --require-three-modes`. The graybox package is not catalog-published.

In this development environment, Lua 5.4 engine tests ran using `tests/run_lua.py`, and UI draw tests ran with mocked LÖVE. A real LÖVE 11.5 or Android runtime was unavailable, so mobile/online device validation remains outstanding.

## Gameplay

Player 1 at bottom; CPU or Player 2 at top. The board is 7 columns x 13 staggered rows of pointy-top hexes. Soldier classes: Warrior (19HP / Move 2 / Attack 1 / D8), Barbarian (25 / 1 / 1 / D6), Archer (15 / 2 / 3 / D10), Wizard (18 / 1 / 2 / D10), Knight (17 / 3 / 1 / D8). Fortress: 30HP / D8. No soldier may jump over other pieces, even Knights. Tap a soldier to see its unit card and green move / red attack highlights. Attackers remain on their original hex. Dice apply simultaneous damage in each combat round until defeat. Damage carries over; winning soldiers recover 4–10 HP. The Fortress never heals. A fortress defeat ends the game. If both armies perish while Fortresses remain, automatic simultaneous D12 trebuchet rolls determine the ending, including simultaneous mutual destruction.

## Remaining work before publishing

1. Run the actual Zompa Python package validator and LÖVE 11.5 game on Android in all 3 modes.
2. Playtest hex tap targets and battle card across phone screen sizes.
3. Validate online invitations, turn delivery, resumable state, the 512-turn SDK limit, and dice fairness in a two-device test.
4. Refine CPU behavior and test game pace with real players; add audio and finished artwork only afterward.
5. Add a Zompa Android scenario JSON with verified screen coordinates, then publish through the official catalog workflow after the checks pass.
