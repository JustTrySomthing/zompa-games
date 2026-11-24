# Fortress: The Badlands — exact board-design handoff (unpublished)

**Status:** specification gathered from the user's approved requests and reference image, not yet implemented. Do **not** update Get Games, package, or publish until the user approves a precise preview. Existing game rules and modes remain intact.

## Verified source of truth
- Official Zompa repository: `JustTrySomthing/zompa`, SDK in `sdk/README.md` and `sdk/zompa.lua`.
- Official games repository: `JustTrySomthing/zompa-games`.
- Current Get Games game ID: `fortress-badlands`; published version at review: `0.2.3` (build 5).
- Unpublished development branch `design/fortress-square-grid-v0.3.0` contains a **7×12** square-grid prototype with a light hexagon inset per tile and a 10-soldier roster. This is a starting point, not the final approved geometry or roster.
- Approved art reference is the **user-supplied image `369.png` in this chat**. Preserve its aged stone, moss, bronze/gold trim, muted deep-navy blue and burgundy-red faction pieces, detailed metal/weapon engravings, and characteristic Fortress appearance. It is a **reference image**, not an existing sprite atlas. Do not treat earlier AI-generated alternative images as binding; they repeatedly altered colors, proportions, and placement.

## Exact geometry (critical)
Use a **7-column by 10-row** square matrix, all cells **perfect squares** of one uniform size, with a lighter **inset hexagon** inside each playable square. This is a rectangular, eight-neighbor game lattice; the hexagons are visual decorations, **not a staggered hexagonal movement grid**. The outer boundary follows cell edges and step corners. Never skew, squeeze, shorten, crop through, or redistribute tiles to produce the silhouette.

Delete **three whole cells at each of the four corners**, in a stair-step pattern:
- Top row: remove columns 1–2 and 6–7 (leave columns 3–5).
- Second row: remove columns 1 and 7 (leave columns 2–6).
- Rows 3–8: leave all seven columns intact.
- Ninth row: remove columns 1 and 7 (leave columns 2–6).
- Bottom row: remove columns 1–2 and 6–7 (leave columns 3–5).

`#` means absent (NOT clipped square); `□` means one complete playable square:

```
           C1 C2 C3 C4 C5 C6 C7
R01        #  #  □  □  □  #  #
R02        #  □  □  □  □  □  #
R03        □  □  □  □  □  □  □
R04        □  □  □  □  □  □  □
R05        □  □  □  □  □  □  □
R06        □  □  □  □  □  □  □
R07        □  □  □  □  □  □  □
R08        □  □  □  □  □  □  □
R09        #  □  □  □  □  □  #
R10        #  #  □  □  □  #  #
```

This produces **58 playable squares, exactly 12 absent squares**, and four symmetrical three-step corners. The **middle four rows (R04–R07)** start empty. The top kingdom occupies the three starting ranks R01–R03; the bottom kingdom occupies R08–R10. Player 1 is always at the bottom.

The Fortress should be centered in the narrow rear rank at `(R01,C04)` for blue and `(R10,C04)` for red. Display the same recognizable fortified building from the approved reference, with kingdom-specific flags; **do not turn it into a new ornate fantasy castle or letter icon**. Keep the surrounding two cells playable.

## Approved piece vocabulary and appearance
- Soldier — helmet silhouette.
- Wizard — pointed wizard hat.
- Assassin — dagger (visibly a dagger, not a long sword).
- Barbarian — distinctive battle axe.
- Ogre — memorable ogre face as in approved image, with **spiked club** as its character weapon/large-card motif.
- One hexagonal badge per piece, centered in its square; badge large enough to nearly fill the inset hexagon without overlapping the grid. Same artwork/silhouette for both kingdoms; **navy/steel/gold vs burgundy/steel/gold**, readable at phone size without tiny letter labels.
- Keep existing user-approved unit inspection, move/attack confirmation, and slow, readable dice battle overlay. Remove large permanent banners, scenery, and distracting top/bottom boxes; obey the Zompa host toolbar and Android insets.

## Final starting army — movement, health, hit strength and placement

**Confirmed:** exactly 14 mobile units **plus 1 Fortress** per kingdom. Each has the same five classes and mirrored positions. No piece may jump over an occupied square.

| Class / icon | Units | Move (squares) | Health | Fixed hit damage on winning D8 exchange |
|---|---:|---:|---:|---:|
| Soldier / helmet | **4** | **2** | **22** | **5** |
| Wizard / pointed hat | **2** | **1** | **16** | **8** |
| Assassin / dagger | **3** | **3** | **14** | **6** |
| Barbarian / battle axe | **3** | **2** | **19** | **6** |
| Ogre / spiked club | **2** | **1** | **28** | **6** |
| Fortress / fortified structure | **1** | 0 | 35 | 5 defensive damage |

**Rationale:** Soldier is tough and reliable, Barbarian sacrifices durability for stronger hits at the same speed, Assassin sacrifices health for maximum speed, Wizard is fragile and slow but hits hardest, Ogre is very durable but slow. All character and Fortress defense rolls use the same D8. The Fortress and Final Siege rules otherwise stay unchanged. Numbers are the new balancing baseline for the redesigned roster, not yet a validated whole-match balance.

Exact symmetric arrangement, blue at the top and red at the bottom; `.` denotes an empty middle-field cell and `#` denotes a genuinely absent cell:

```
       C1 C2 C3 C4 C5 C6 C7
R01    #  #  S  F  S  #  #
R02    #  O  W  B  W  O  #
R03    A  S  B  A  B  S  A
R04    .  .  .  .  .  .  .
R05    .  .  .  .  .  .  .
R06    .  .  .  .  .  .  .
R07    .  .  .  .  .  .  .
R08    A  S  B  A  B  S  A
R09    #  O  W  B  W  O  #
R10    #  #  S  F  S  #  #
```

S=Soldier, F=Fortress, O=Ogre, W=Wizard, B=Barbarian, A=Assassin. Each kingdom occupies 3 + 5 + 7 cells, totaling **14 troops + Fortress**. The 7×10 board has 58 playable full squares and 12 absent squares; no trimming or distortion.

The exact board mask and 14-piece placement are now decided for the wireframe. The user must approve the wireframe before artwork is applied. Existing published version stays unchanged.

## Implementation constraints and validation
- Apply the *same cell mask* to rendering, touch hit-testing, movement pathfinding, target validation, CPU decisions, starting formation, animations, and online deterministic replay; absent squares are impassable, unrendered, and untappable.
- Preserve eight-neighbor square-lattice movement, existing D8 higher-roll-wins fixed-damage combat, Chess-like landing captures, health/potions, Fortress defense, and simultaneous trebuchet Final Siege.
- Adapt the old five class identifiers (`warrior`, `barbarian`, `archer`, `wizard`, `knight`) to the approved new roster **only after** assigning balanced stats and preserving save/online compatibility. Existing 0.3.0 source still uses old class identifiers and 10 mobile units.
- Ensure all visuals and controls scale on portrait Android screens, while cells remain exactly square and all legal cells visible.
- Run tests for no missing tiles, exactly 58 playable cells, symmetry, 14-piece count once clarified, identical legal moves across solo/local/online, target blocking at deleted corners, and resume/replay determinism.
- Do not make a release, upload to Get Games, or change the Android APK before the user approves the exact board and characters.

## Next design step
Produce a **strict grid wireframe**, preferably generated by code/actual board renderer rather than a freeform image generator, so the user can approve exact corner removals, full square proportions, Fortress placement, and 14-piece mirrored formation. Then skin that fixed layout using the approved reference style without regenerating the geometry.
