# Zompado Games

Zompado installs official games as `.zomp` packages from **Games → Get Games**. [Browse releases](https://github.com/JustTrySomthing/zompado-games/releases).

The [current catalog](catalog-v2.json) lists downloadable `.zomp` packages with exact file sizes and SHA-256 hashes. Each package is a ZIP archive with a root `zompado.json` manifest and game files. Drop Four's archive identifies its LÖVE entry point. Zompado's current Android app plays its built-in Drop Four implementation after verifying the package. That implementation supports offline solo and same-phone pass and play.

The old [catalog.json](catalog.json) and its Drop Four 1.0.0 `.love` release serve older Zompado installs. Plain `.love` files are intended for manual imports once the isolated LÖVE player is available.

To publish a new Drop Four package, update the version and increase the build in [the release request](.github/release-request.json). The workflow packages the [game source](drop-four/1.0.0), publishes the new release, and changes the current feed after the public download is verified. Keep old tags available.
