# Zompado Games

Zompado installs official games as `.zomp` packages from **Games → Get Games**. [Browse releases](https://github.com/JustTrySomthing/zompado-games/releases).

The [current catalog](catalog-v2.json) lists downloadable `.zomp` packages with exact file sizes and SHA-256 hashes. Each package is a ZIP archive with a root `zompado.json` manifest and game files. Drop Four 1.3.0 opens as Cats vs Dogs and includes solo, pass and play, and online matches. Solo and pass-and-play rounds use a first-to-three series. Online matches use the existing Chatmail turn-based flow. The LÖVE player in Zompado runs the downloaded package. The catalog keeps previous package references for shared links and match history.

The old [catalog.json](catalog.json) and its Drop Four 1.0.0 `.love` release serve older Zompado installs. Plain `.love` files are intended for manual imports in Zompado.

To publish a new Drop Four package, update the version and increase the build in [the release request](.github/release-request.json). The workflow packages the [versioned game source](drop-four), publishes the new release, and changes the current feed after the public download is verified. Keep old tags available.
