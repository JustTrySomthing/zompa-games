# Fortress: The Badlands — Zompa gameplay prototype

Version **0.2.2**, build **4**. Same stable game ID `fortress-badlands`; updates through **Zompa → Games → Get Games**.

## Gameplay

Portrait 7 × 13 honeycomb hex board. Player 1 starts at the bottom. Each kingdom begins with ten troops (3 Warriors, 2 Barbarians, 2 Archers, 1 Wizard, 2 Knights), separated by neutral Badlands. There is **no territory capture**. The goal is to destroy the enemy Fortress.

| Unit | Health | Move | Capture range | Hit damage | Battle die |
|---|---:|---:|---:|---:|---|
| Warrior | 19 | 2 | 1 | 5 | D8 |
| Barbarian | 25 | 1 | 1 | 5 | D8 |
| Archer | 15 | 2 | 3 | 7 | D8 |
| Wizard | 18 | 1 | 2 | 7 | D8 |
| Knight | 15 | 3 | 1 | 5 | D8 |

One turn = one move **or** attack. No jumping over pieces, including Knights. Attacks need a clear path. An attacker defeating an enemy soldier moves into its hex. Defenders stay on their own hex when victorious.

In battle, both roll D8. The higher roll deals its class's fixed Hit damage; an equal roll deals no damage. Only one side is damaged per exchange. After defeating a soldier, the survivor receives automatic healing of 4–10 HP up to its class maximum.

The Fortress has **35 HP**, retaliates only when attacked, uses D8, deals 5 damage on a winning exchange, and cannot heal. If both armies are eliminated without either Fortress falling, the **Final Siege** begins. Both trebuchets fire simultaneously: D8 rolls 4–8 deal 7 damage, 1–3 miss. Both Fortresses may fall in the same volley, causing **Mutually Assured Destruction**.

## Version 0.2.1–0.2.2 usability improvements

- Tapping an enemy **without selecting your unit** shows its class card only.
- Select your unit, then tap a **green empty destination** or **red enemy target**. The action is only **previewed**; it does not execute until you press **MOVE** or **ATTACK**. A CANCEL button lets you change the target.
- When targeting an enemy, its health, movement, capture range and Hit damage are displayed before committing the attack.
- Battle dialog now shows both combatants on opposite sides, animated rolling D8s, one-at-a-time lunges, a visible `-HP` impact, updated health bars, a clear winner, and a Continue button after the complete sequence.
- The Final Siege also presents volleys more slowly and shows both Fortress health totals and damage.

## Zompa SDK

Uses LÖVE 11.5 and the unmodified Zompa v4 `zompa.lua` SDK. The manifest declares `solo`, `local`, `online`, `localSaves`, and `onlineProtocol: turns-v1` with `minZompaBuild: 56`. Local rounds use `zompa.saveSession` and `zompa.loadSession`; online gameplay uses `readTurns` / `submitTurn`, with the same deterministic rules on both devices. Network transport and invitations belong to the Zompa host.

## Automated checks

Run `python3 tests/run_lua.py tests/smoke.lua tests/ui_smoke.lua tests/ux_smoke.lua tests/autoplay.lua` inside the source directory. These include rules, state replay, input confirmation, battle animation phases, four portrait sizes and complete automated matches. Android screen and online two-device testing remain necessary; this is a graybox gameplay update, not finished artwork.

Version 0.2.2 also uses Lua 5.1/LuaJIT-compatible table unpacking for battle figures.
