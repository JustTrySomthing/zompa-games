# Fortress: The Badlands — v0.5.18 (build 35)

Fortress is a turn-based game for Zompa using LÖVE 11.5. See [How to Play](how-to-play.txt) for the current stats and combat rules.

Choose one move or attack per turn. Most attacks target a neighboring hex. An Archer can fire over pieces within three hexes, and a Fortress can fire within its forward three rings after it has come under attack. All attacks use one D12 and leave the attacker in place.

The v17 save format starts a new local match because the new stats change how previous turns resolve. Existing online matches keep their original build.

## Earlier releases

## Release v0.5.0 — approved 15-piece symmetrical redesign

- Larger balanced board based on the approved mockup; weathered edge-to-edge hex art and both two-tower forts retained.
- 15 troops per side, not 14; 30 total troopers plus two forts, with exactly the approved class distribution.
- Two fourth-rank flanks intentionally empty to make space for early maneuvers.
- Six truly adjacent hex movement directions replace the old square-index eight directions to match the tessellation.
- Dynamic unit indexing (1–30), formation, AI action search, six-sided tap detection, animations, autoplay, and deterministic replay updated together.
- All three Zompa game modes are supported; online save tokens still travel through SDK v4's turns-v1.
- New v6 save format prevents old-match contamination; all original values for damage, dice, healing and classes stay unchanged.

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

## v0.4.7 — approved Fortress UI handoff implementation (November 24, 2026)

This version is based on all four **Approved_Mockups** and four **Original_Screenshots** supplied in the handoff ZIP, not another proposal or mockup. It uses the same Fortress identity and Zompa SDK v4.

- **Board:** replaced the painted square grid / inset-hex texture with close-packed six-sided flagstones, each textured from the source board's blank stone interior; visible square tile outlines are removed. Source center calibration, narrowed corner mask, 58 playable square-logical positions and all 8 movement directions remain unchanged. A true regular hex tessellation on an orthogonal 7×10 lattice would change hit testing and movement topology, so the approved mockup's staggered rows are *not* copied literally. This is the explicit visual/mechanics trade-off.
- **Artwork:** added continuous dark-and-gold hex strokes to all ten original class sprites in both team colors; shared renderer is used on the board, on the inspection card, and in combat. The source token artwork and the fortress remain the same.
- **Battle dialog:** near-full-canvas navy panel, double gold trim, bold team-tinted labels above their respective tokens, responsive HP bars, and correct red/blue D8 models. Round indicator and minimal hits/tie feedback remain.
- **Winner:** slanted team-color banner, geometry *and lettering* rotated together, measured single-line text and readable fallback. Dynamic unit and fortress wording is retained.
- **Victory reward:** exactly `RED ROLLS FOR VICTORY BONUS` or `BLUE ROLLS FOR VICTORY BONUS` and `ROLL`. Until tapped, both last combat dice remain visible; afterward, only the center bonus die tumbles and settles on the actual D8 result. The winner's displayed HP rises to the capped health already committed by deterministic rules. The result banner reads `HEALTH BONUS +N` without appended HP, or `HEALTH FULL` if no actual recovery, then `CONTINUE`.
- **Authority:** solo CPU and online non-winner sides show an automatic presentation roll; solo human, local pass-and-play participant and online winner initiate visually. Rolling does not add a token or network event, and is idempotent.
- **Controls / background:** approved red ATTACK NOW, gray CANCEL, gold trim, unified dark-purple stage, docked stat card above playing cells and no duplicate Zompa navigation.
- **Performance:** static board flagstones are cached in a stencil-enabled canvas where supported; fallback vector painting is available. Everything else is drawn dynamically; no new outside image packs or font dependencies.

### Verification

The official GitHub workflow runs deterministic combat/HP/replay rules, board-mask tests, touch/UX/CPU movement, responsive portrait smoke tests and full automated matches. Approved mockups are visual targets, not executable source artwork. Final actual-device screenshot comparison and two-device online interaction remain necessary after publication.

## Version 0.4.8 — Fortress visibility, seamless stones, combat polish

- Remove the repeating dark vertical seam from the stone image crop: all hexagonal flagstones now use continuous warm stone fills and light, off-center grain accents. No changes to the 58 cell centers, controls, or legal moves.
- Restore the original painted **Red and Blue Fortress** at both ends by clipping each fortress from the approved board art directly to the corresponding six-sided hex, even when the board is rendered procedurally. A crenellated vector fallback works without stencil support. The fortress disappears when reduced to zero HP.
- Draw only one centered gold contour on each character badge and eliminate the extraneous backing hex in the battle panel.
- Damage pop-ups originate just above the wounded unit's **HP bar**, float upward toward the character and fade. The fixed class damage and health calculations stay unchanged.
- Replace the plain diagonal result strip with a layered, beveled gold victory plaque, team-color enamel, copper end cuts, inset highlights and ornamental rivets. The whole plaque, including the text, rotates together.
- Extended UX regression test checks for both visible Fortress crests on the actual artwork path in addition to all previous UI, battle, deterministic healing, save/replay and full-match tests.

**Gameplay/SDK compatibility:** No change to classes, combat RNG, healing range, save version, online turns or the three Zompa modes. Android device screenshot review is still required for final aesthetic comparison.

## Version 0.4.9 — seamless weathered hexes, twin-tower fortresses and single-rim tokens

- The **visual board** now uses a real staggered tessellation of point-up hexes that share each edge. Thin charcoal grout is visible only along tile boundaries; there are no open voids between adjacent cells. Each stone has hand-drawn deterministic variation, shallow patches, small chips, moss coloration and fine cracks. Board artwork uses a cached static canvas for performance.
- The original **7×10 logical grid of 58 playable positions** and its eight-direction movement/attacks remain exactly as before, including all online and saved actions. To achieve true geometric adjacency, the **displayed hex centers are staggered**. The game performs exact six-sided hit-testing against the new visible geometry. This deliberate visual geometry change does not change the game rules.
- Both Fortresses are explicitly drawn in the **center hex** of the top (Blue, row 0 col 3) and bottom (Red, row 9 col 3) rows. A substantial stone fort has **two crenellated towers**, a connecting wall, a gate, masonry texture and a color-coded pennant. It is drawn without depending on the board background PNG, so it cannot disappear when that background changes. The same drawing appears in inspection cards and Fortress battles.
- Original character crops are clipped inward to remove their old off-center painted lip and rendered with **one** clean, centered gold outline. Selection uses a low-key *round* glow instead of a second hex; movement and battle share the same token renderer.
- Red/Blue `ROLLS FOR VICTORY BONUS` now sits immediately above the ROLL button, avoiding the former blank region. Result dice and bonus values stay deterministic.
- Adds a dedicated `hex_geometry_smoke.lua` regression test for exact edge-sharing geometry, touch centers, both visible twin-tower Fortresses, and responsive layout. All original Zompa SDK v4 and multiplayer behavior are retained.

**Note:** visual hex adjacency follows hex geometry, but movement still follows the same original eight directions on row/column indexes. This is intentional to preserve the approved game's rules and online compatibility. Actual-device visual verification is still recommended.

## v0.5.2 movement changes

- Soldier: HIT **4**, MARCH up to **2 hexes in one straight direction** without changing direction; intermediate hex must be empty.
- Ogre: HIT **7**, unchanged MOVE 1.
- Wizard: HIT 8 unchanged; TELEPORT **2 hexes**, can cross occupied hexes but cannot finish on an ally. Enemy endpoint starts a normal D8 fight.
- During any attack-approach animation the target remains visible, including if the rules have already marked it defeated; the attacker travels on top of the target before battle begins. Applies to troops and Fortresses, in solo, local and online presentation.

## v0.5.2 artwork and character cards

- **New separately packaged art**: Ogre's spiked wooden club (both Red and Blue);
  Wizard's crystal-tipped magical staff (Red and Blue); twin-tower stone Fortress
  with gate and banners (Red and Blue). The live board, battle panel and Fortress
  detail card load these individual sprite assets, not a static whole-screen banner.
- **New individual portrait assets**: five character classes, each with Red and Blue
  variants, showing a right-facing head-and-shoulders pose and their class weapon.
  Soldiers carry a pike/spear, not the Assassin's dagger; Ogre uses a spiked club;
  Barbarian an axe; Wizard a magic staff.
- **Live character info card**: restrained navy, muted red/blue and thin gold lines,
  compact gold-edged hex portrait; the entire title is RED/BLUE + class (no P1/P2);
  current/max HP, MOVE and HIT are always read from the current rules state.
  No static card art, die stat, class flavor text or duplicated secondary banner.
  All classes show MOVE as the heading, including Soldiers and Wizards.
