# Fortress: The Badlands — Zompa gameplay prototype

Version **0.2.3**, build **5**. Same stable ID `fortress-badlands`; updates through **Zompa → Games → Get Games**.

A portrait 7×13 honeycomb battlefield. Two 10-unit kingdoms compete to destroy the opposing 35 HP Fortress.

| Unit | Health | Move (hexes) | Hit damage |
|---|---:|---:|---:|
| Warrior | 19 | 2 | 5 |
| Barbarian | 25 | 1 | 5 |
| Archer | 15 | 2 | 7 |
| Wizard | 18 | 1 | 7 |
| Knight | 15 | 3 | 5 |

## Gameplay
**Move = reach.** Select your own soldier. Tap a highlighted green empty hex to preview moving, or a crossed-swords red enemy destination to preview attacking. A visible route arrow traces a valid path into the enemy hex. Tap **MOVE TO HEX** or **ATTACK THIS HEX** to confirm. No automatic battle from mere adjacency. No separate Capture stat or class-specific die (all use D8). The card shows class, Health, Move, and Hit damage.

Movement is 1 to the unit's maximum hexes and can turn around clear spaces but cannot pass through any occupied hex. No Knight jumping. A winning attacker replaces the defeated enemy on the destination hex; if defender wins, attacker dies and defender retains its hex. The combatants roll a shared D8. Higher result inflicts the winner's fixed Hit damage; ties inflict no damage. Damage persists, and troop victors heal a random 4–10 HP up to maximum.

Fortresses have 35 HP, defend with D8 and Hit 5, and do not heal. A Fortress can be assaulted only when its hex is a reachable destination. If both armies die before either Fortress falls, simultaneous D8 trebuchets hit on 4–8 for 7 HP and miss on 1–3; both walls can collapse together, causing Mutually Assured Destruction.

## SDK and compatibility
LÖVE 11.5 with unmodified Zompa v4 SDK. `solo`, `local`, `online` modes and `onlineProtocol: turns-v1`, `minZompaBuild: 56`. Local rounds store versioned `v2|` action histories using `saveSession`; old saves use incompatible reach rules and start fresh. Zompa host provides encrypted move transport for online matches and locks the exact game build.

## Tests
`python3 tests/run_lua.py tests/smoke.lua tests/ui_smoke.lua tests/ux_smoke.lua tests/landing_smoke.lua tests/autoplay.lua`

Checks include deterministic battle outcomes, movement blockers, full matches, touch preview/cancel/confirm, and mocked portrait UI sizes. Real Android and two-device playtesting remain necessary.
