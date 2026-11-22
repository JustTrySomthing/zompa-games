# Zompa Games

Zompa installs official games as `.zomp` packages from **Games → Get Games**. [Browse releases](https://github.com/JustTrySomthing/zompa-games/releases).

The [current catalog](catalog-v2.json) lists downloadable `.zomp` packages with exact file sizes and SHA-256 hashes. Each package is a ZIP archive with a root `zompa.json` manifest and game files. Cats vs Dogs includes solo, pass and play, and online matches. Solo and pass-and-play use a first-to-three series. Online games also use a first-to-three series when both players’ Zompa apps support it. The LÖVE player in Zompa runs the downloaded package. The catalog keeps previous package references for shared links and match history.

The old [catalog.json](catalog.json) and its Drop Four 1.0.0 `.love` release serve older Zompa installs. Plain `.love` files are intended for manual imports in Zompa.

To publish a new Cats vs Dogs package, update the version and increase the build in [the release request](.github/release-request.json). The workflow packages the [versioned game source](drop-four), publishes the new release, and changes the current feed after the public download is verified. Keep old tags available.

## Submit a game

[Open a game submission](https://github.com/JustTrySomthing/zompa-games/issues/new?template=game-submission.yml) with the title, version, play modes, a link to the source and the `.zomp` build, and any artwork you want shown in **Get Games**. For a game that is already listed, use the same game ID and include the release notes for the new version.

Optional catalog artwork lives at `catalog-art/<game-id>/<version>/`. [Cats vs Dogs 1.3.4](catalog-art/drop-four/1.3.4) shows how the files fit together.

| File | Requirements |
| --- | --- |
| `cover.webp` | One cover, ideally 16:9 and around 1280 × 720. Keep the main subject near the center so the cover works on narrow and wide cards. |
| `shot-1.webp`, `shot-2.webp`, `shot-3.webp` | Up to three screenshots of the game at its natural aspect ratio. Use at least 480 px on the short side and at most 1600 px on the long side. |
| `preview.json` | List the cover filename if included and the screenshots in display order. Give every screenshot a short description of what it shows, up to 100 characters. |

Export still WebP images at **350 KiB or smaller per image**. Submit full game frames without phone status bars, moderator tools, or personal information. The cover appears on the Get Games card. Screenshots load when someone opens the gallery from the photo icon. Art lives outside the package so it does not increase the download or installation size.

For an artwork update, include a new game version and a higher build number with the revised files under the new version folder. The latest catalog entry picks up that version’s art when the release is published.
