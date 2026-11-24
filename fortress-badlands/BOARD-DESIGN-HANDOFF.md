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

## Piece-count and deployment detail still requiring confirmation
The user explicitly said **14 pieces per kingdom**. It has *not* been explicitly settled whether that **includes the Fortress**, or means **14 mobile units plus the Fortress**. The stepped first three ranks offer `3 + 5 + 7 = 15` playable starting squares per kingdom:
- 14 mobile units + Fortress would fill all 15 squares.
- 14 pieces including Fortress would leave exactly one empty starting square per side.

Do not arbitrarily add extra units or duplicate helmets to fill squares until this distinction is resolved. The class distribution across the five updated names and exact starting squares must be approved after a mechanically exact wireframe preview. The user asked to move the outermost pieces inward, remove two helmet positions in the second rank near the Fortress, and use a three-rank, symmetrical formation; preserve these placement objectives when making the layout.

## Implementation constraints and validation
- Apply the *same cell mask* to rendering, touch hit-testing, movement pathfinding, target validation, CPU decisions, starting formation, animations, and online deterministic replay; absent squares are impassable, unrendered, and untappable.
- Preserve eight-neighbor square-lattice movement, existing D8 higher-roll-wins fixed-damage combat, Chess-like landing captures, health/potions, Fortress defense, and simultaneous trebuchet Final Siege.
- Adapt the old five class identifiers (`warrior`, `barbarian`, `archer`, `wizard`, `knight`) to the approved new roster **only after** assigning balanced stats and preserving save/online compatibility. Existing 0.3.0 source still uses old class identifiers and 10 mobile units.
- Ensure all visuals and controls scale on portrait Android screens, while cells remain exactly square and all legal cells visible.
- Run tests for no missing tiles, exactly 58 playable cells, symmetry, 14-piece count once clarified, identical legal moves across solo/local/online, target blocking at deleted corners, and resume/replay determinism.
- Do not make a release, upload to Get Games, or change the Android APK before the user approves the exact board and characters.

## Next design step
Produce a **strict grid wireframe**, preferably generated by code/actual board renderer rather than a freeform image generator, so the user can approve exact corner removals, full square proportions, Fortress placement, and 14-piece mirrored formation. Then skin that fixed layout using the approved reference style without regenerating the geometry.
