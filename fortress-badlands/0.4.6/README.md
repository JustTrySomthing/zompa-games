# Fortress: The Badlands — v0.4.6 (build 13)

Zompa LÖVE 11.5 game, same `fortress-badlands` identity for Get Games updates.

## Changes in 0.4.2

- Larger, legible player inspector using the **actual full character badge**, class name, kingdom, current / maximum HP, MOVE and HIT. The card uses the otherwise empty space above the battlefield when available rather than a tiny ribbon covering the top row.
- The board is kept at the **largest possible aspect-correct size within the host canvas**, with a warm slate background in previously empty space. Square game cells remain square: we do not crop the 7×10 board or stretch sprites. The host toolbar and Android safe areas remain managed by the Zompa SDK.
- Corrected the board-space x coordinates against measured tile centers in the shipped art. Move spaces are bright mint hex outlines with a solid central dot, fully centered on their real cells; attack spaces retain clear red crossed-swords highlights.
- Full-health bars no longer clutter the board. Injured pieces and damaged Fortresses have a thin health bar **lower** underneath the symbol. Every unit's exact current HP is in its inspector card.
- Player and CPU moves now **visibly travel across the actual legal path** before combat opens. The CPU pauses briefly before it decides. Neither animation nor the dialog changes the deterministic combat result or the saved/online move protocol.
- Battle panels use larger fully visible character badges (not clipped by round portrait frames), shaded faceted D8 dice, a slower readable roll → winner → strike → HP-reduction sequence, and high-contrast outcome text identifying who won and who fell. Victories show potion healing, including `Health already full` instead of confusing `+0 HP`.
- The Final Siege retains simultaneous D8 trebuchet hits; its damage and result announcements are easier to follow.
- The rules, class balance, 14-unit armies, 35HP Fortress, shared D8, and all three Zompa game modes remain unchanged.

## Game rules

7×10 square grid with a lighter inset hexagon inside every playable square. There are exactly 58 playable cells after three whole squares are removed from each corner. Player 1 (burgundy) starts at bottom, Player 2 (blue) at top. 14 troops plus one stationary Fortress per side. Four empty central ranks; no territory capture.

| Class | Count per kingdom | HP | Move | Fixed hit |
|---|---:|---:|---:|---:|
| Soldier | 4 | 22 | 2 | 5 |
| Wizard | 2 | 16 | 1 | 8 |
| Assassin | 3 | 14 | 3 | 6 |
| Barbarian | 3 | 19 | 2 | 6 |
| Ogre | 2 | 28 | 1 | 6 |

A player moves **one** troop per turn. Move by selecting a troop, tapping any valid highlighted empty square, then tapping Move Here. Moving onto an enemy's square initiates a D8 battle; confirm with Attack Now. No jumping over pieces. In a battle, both D8 dice roll; the higher roll's unit deals its fixed hit value, equal rolls do zero damage. Repeat until one unit falls. The victorious attacker takes the square; the surviving victor heals by a random 1–8 HP, not exceeding their maximum.

Defeat the enemy Fortress (35 HP, retaliates with D8 for fixed 5 HP, never heals) to win. If both armies perish first, D8 trebuchets attack simultaneously; rolls 4–8 hit for 7 HP, allowing mutual destruction.

## Zompa SDK / verification

Unmodified SDK v4 `zompa.lua` (SHA 7c094c86be6dab9b63b5bd4970de9fa76f74be79); official LÖVE runtime. Modes `solo`, `local`, `online` via the host, online token replay through turns-v1, local session saving, Zompa toolbar controls and safe area. No custom chat/networking code. Existing in-progress matches remain pinned to their build by the host.

Automated tests in `tests/` include square-mask, movement, battle determinism, 24 whole-match simulations, readable touch controls, animation sequencing, CPU move visibility, and resizing across multiple portrait canvases. These do not replace Android device and real online two-device testing.


## Version 0.4.3: alignment and true octahedral dice

- Source-art pixel calibration changed to x=97, y=107 (same transformation for tapping, move markers, units and fortresses). The former y=94 placed overlays roughly 13 artwork pixels above the painted hex centers.
- Every character crop uses its actual badge center (x=77,y=82), instead of the midpoint of the 144×144 tile crop. On inspection cards and during battles, the surrounding stone square is hidden with an accurate hexagonal stencil; full pieces stay within their own frames.
- Each D8 now renders as a rotating octahedron made from 8 triangular faces, projected in perspective with front/back shading, visible edges, a ground shadow, and the resolved result printed on the landing face.
- The animation consumes no gameplay random numbers, so online deterministic replay and battle balance remain unchanged.
- Existing graphics, class balance, starting formation and Zompa SDK interfaces are otherwise unchanged. Tests check actual artwork-center alignment and badge masking in addition to the prior combat and UI tests.


## Version 0.4.4 — battle readability and more strategic recovery

- Battle results emphasize the actual factions and combatants (for example, "RED BARBARIAN WINS"), rather than generic attacker/defender statements. The die and HP bars remain visible.
- Replace repeated explanatory text with compact round status and animated red "-5" style floating damage bubbles beside the character being struck.
- The victorious surviving troop's healing is now **D8 = 1 to 8 HP**, never beyond its class maximum. The battle outcome and healing die are determined by the shared game RNG at action resolution; the **Roll D8 to Heal** button reveals that deterministic reward without changing the result. This is visual interaction only and introduces no online network move.
- In single-player, CPU healing is revealed automatically. In pass-and-play and online, participants can watch the same established reward without changing gameplay.
- New save format \`v5\`: pre-v0.4.4 in-progress local matches use an incompatible RNG sequence and must start a fresh game. Older online matches remain pinned to their original exact game build by Zompa.
- Character card text is larger, full width is better used, selected destinations glow in high-contrast gold with a dark underlay. Small art borders are trimmed without stretching the board. Moving character badges and the numbers on the dice faces are centered more precisely.

## Version 0.4.5 — premium presentation and CPU polish

- Selected soldier gets a restrained gold double-ring pulse; the *chosen* landing hex gets a distinct white/gold center to distinguish it from all available destinations.
- Per-cell movement has a slight arrival/settle animation; no rules or online messages are changed.
- The battle's ordinary D8 exchanges are brisker, with small deterministic sword-impact sparks and floating damage. The final blow holds for a moment before the winner/reward confirmation.
- The inspection card now chooses the clearer top or bottom free margin, or the opposite side of the board on small devices. Stats are grouped visually and remain large.
- On match completion a short visual effect shows a squat Fortress collapsing, followed by an unmistakable victory, defeat, or mutual-destruction banner.
- CPU decision scoring now considers enemy strike strength, expected exchanges before defeat, immediate threats and home-Fortress defense; existing gameplay statistics remain unchanged.
- Mobile portrait layouts and touch-control handling remain responsive under the same Zompa SDK. The board artwork is deliberately unchanged.

**Compatibility:** Same rules/save version as v0.4.4; game identity is unchanged. No additional piece abilities or controls were added. Check the polished UI on an Android phone after installation.

## Version 0.4.6 — immersive arcade-style battle polish

- Every battle die is permanently tinted to its kingdom: muted burgundy red for Red, muted royal blue for Blue, including Final Siege and healing rewards. Winning rolls are distinguished by the outcome, not an unrelated die color. The decorative bars above combatant portraits are removed.
- A bold angled winner splash identifies the kingdom and class. After the win, an equally prominent Health Bonus splash and large reward die show the already-determined 1–8 HP result; the player taps **Roll for +1 to +8 HP**, while the CPU starts its roll automatically *after* the battle.
- The board image only trims non-playable painted margins to fill more of its canvas. Gameplay coordinates, the 7×10 grid, and piece aspect ratios remain identical.
- The card is docked in a reserved top band, not allowed to overlap the playing field. Fonts and stat rows fit within its responsive height.
- One continuous stone-charcoal stage replaces the previous multiple horizontal backdrop bands.
- No new combat rules, character stats, or transport protocol; Zompa SDK v4 and saved event format v5 remain unchanged.
- The updated UI tests check responsive layout and that the battle healing reward is still explicit and modal. Visual polish must be reviewed on Android.
