# Table Circle Games

The official game catalog for [Table Circle on Android](https://github.com/JustTrySomthing/table-circle). In Table Circle, choose **Games → Get Games** to install or update a game independently of the app.

| Game | Package | Modes |
|---|---|---|
| Drop Four | [Drop Four 1.0.0](https://github.com/JustTrySomthing/table-circle-games/releases/tag/drop-four-v1.0.0) | Offline solo and same-phone pass and play in Table Circle. The standalone LÖVE cartridge supports offline solo. |

The versioned `.love` package can also be opened directly in LÖVE 11.5. Table Circle 0.2 plays its built-in, known Drop Four implementation after the package is downloaded and verified. General downloaded Lua execution is reserved for the isolated player.

To add an official release, publish an immutable package under a new tag, then update [catalog.json](catalog.json) with its version, increasing build number, exact download URL, byte count, and SHA-256. Retain old tagged versions. Source for the starter game is in [drop-four/1.0.0](drop-four/1.0.0).
