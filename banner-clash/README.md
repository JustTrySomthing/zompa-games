# Banner Clash

Download [Banner Clash 0.2.0](packages/Banner-Clash-0.2.0.zomp) and import the package into Zompa for Solo or two-player Pass & Play. Online is planned. The portrait reference in design/ guides the interface and can evolve with playtesting.

The 0.2.0 directory contains the complete LÖVE 11.5 source and illustrated deck. From that directory, run the rules and UI checks with a Lua interpreter.

    lua ../checks/matches.lua
    lua ../checks/pass-and-play.lua

To build the package from the same directory, zip the files at the archive root.

    zip -9 ../packages/Banner-Clash-0.2.0.zomp *.lua *.json cards.png

The design folder includes the Edition 6 rules and pre-build restore point. The restore point contains the earlier simulation scripts. Use the versioned Lua source for the playable implementation. Physical Android rendering, input, and human match duration still require device playtesting.
