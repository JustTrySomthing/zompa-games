# Zompa Games

Zompa installs official games as `.zomp` packages from **Games → Get Games**. [Browse releases](https://github.com/JustTrySomthing/zompa-games/releases).

The [current catalog](catalog-v2.json) lists downloadable `.zomp` packages with exact file sizes and SHA-256 hashes. Each package is a ZIP archive with a root `zompa.json` manifest and game files. Cats vs Dogs includes solo, pass and play, and online matches. Solo and pass-and-play use a first-to-three series. Online games also use a first-to-three series when both players’ Zompa apps support it. The LÖVE player in Zompa runs the downloaded package. The catalog keeps previous package references for shared links and match history.

[Fortress Siege: Final Conquest](fortress-badlands/1.4.6) is a portrait strategy game. Lead the Red or Blue army, use each unit’s movement and attack range, and destroy the enemy fortress. Play solo, pass and play, or online.

[Fortress Siege v0.5.72 checkpoint](https://github.com/JustTrySomthing/zompa-games/tree/checkpoint/fortress-siege-pre-1.0.0) preserves the source, gallery, and catalog before 1.0.0. The [playable v0.5.72 package](https://github.com/JustTrySomthing/zompa-games/releases/tag/fortress-siege-final-conquest-v0.5.72) is available on GitHub Releases.

[Fortress Siege v0.5.44 checkpoint](https://github.com/JustTrySomthing/zompa-games/releases/tag/fortress-siege-final-conquest-v0.5.44) preserves the playable package and source before the visual update. To restore this look through Get Games, package the checkpoint source with a new version and a higher build number.

The old [catalog.json](catalog.json) and its Drop Four 1.0.0 `.love` release serve older Zompa installs. Plain `.love` files are intended for manual imports in Zompa.

Cats vs Dogs is the [three-mode SDK reference](drop-four/1.4.16). To publish a new build, update the version and build in [the release request](.github/release-request.json). [The publishing workflow](.github/workflows/publish-game.yml) builds one package, checks it in the Android player in all three modes, publishes the tested bytes, and lists the game after verifying the public download. Keep old tags available.

## Submit a game

[Open a game submission](https://github.com/JustTrySomthing/zompa-games/issues/new?template=game-submission.yml) with the title, version, play modes, a link to the source and the `.zomp` build, and any artwork you want shown in **Get Games**. For a game that is already listed, use the same game ID and include the release notes for the new version.

Optional catalog artwork lives at `catalog-art/<game-id>/<version>/`. [Cats vs Dogs 1.4.1](catalog-art/drop-four/1.4.1) shows how the files fit together.

| File | Requirements |
| --- | --- |
| `cover.webp` | One cover, ideally 16:9 and around 1280 × 720. Keep the main subject near the center so the cover works on narrow and wide cards. |
| `shot-1.webp` through `shot-8.webp` | Up to eight screenshots of the game at its natural aspect ratio. Use at least 480 px on the short side and at most 1600 px on the long side. |
| `preview.json` | List the cover filename if included and the screenshots in display order. Give every screenshot a short description of what it shows, up to 100 characters. |

Export still WebP images at **350 KiB or smaller per image**. Submit full game frames without phone status bars, moderator tools, or personal information. The cover appears on the Get Games card. Screenshots load when someone opens the gallery from the photo icon. Art lives outside the package so it does not increase the download or installation size.

For an artwork update, include a new game version and a higher build number with the revised files under the new version folder. The latest catalog entry picks up that version’s art when the release is published.

### Publish a game to Get Games

Commit the tested package to `<game-id>/packages/<filename>.zomp` on main. The package publisher reads the root `zompa.json`, publishes a GitHub Release, verifies the public download, and adds it to the app catalog. Include the source and tests in the game's directory for recovery. Updating a game requires a new version and a higher build. Previous releases remain available for installed games and shared links.

The [current SDK standard](https://github.com/JustTrySomthing/zompa/blob/main/sdk/README.md) calls for Single Player, Pass & Play, and Online 2 Player. Online play uses hidden encrypted Chatmail messages exchanged by the two Zompa apps. The publisher validates the archive with the SDK and runs its three modes on Android. Next to each package, provide a matching `<filename>.scenario.json` containing a normalized board rectangle and screen taps for solo, local, and online. The Android check uses two emulators at 720 × 1280 and density 240. The Solo scenario takes one human turn and checks a distinct computer reply. Pass & Play takes two turns. Online takes one turn from each phone and verifies the other phone renders it.

Use this JSON structure. Fill the coordinates using screenshots of your own game. Keep effects outside the selected board region or choose a quiet region that visibly changes for the tested moves.

```json
{
  "schema": 1,
  "board": [0.10, 0.25, 0.90, 0.75],
  "solo": {"start": [[0.50, 0.70]], "moves": [[0.40, 0.50]]},
  "local": {"moves": [[0.40, 0.50], [0.60, 0.50]]},
  "online": {"moves": [[0.40, 0.50], [0.60, 0.50]]}
}
```
