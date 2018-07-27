# Star Ruler 2
Star Ruler 2 is a massive scale 4X/RTS set in space. Explore dozens, hundreds,
or even thousands of systems in a galaxy of your choosing, expand across its
planets, exploit the resources you find, and ultimately exterminate any who
stand in your way. The fate of your empire depends on your ability to master
the economy, field a military, influence galactic politics, and learn what you
can about the universe.

## What is this?
This repository contains the full source code needed to build Star Ruler 2, and
all secondary scripts, data files and assets required to run it.

Blind Mind Studios has been inactive for a few years now, so we decided to
open-source the game as a whole and allow anyone interested in how its engine works
to tinker with it.

## Building the Game
The Star Ruler 2.exe contained in the main folder is just a launcher. To run
the game you will need to build the binary for your platform from source.

### Building on Windows
You will need Visual Studio 2017 to build Star Ruler 2 on windows. Simply open the
visual studio solution in source/msvc/Star Ruler 2/, and build the "Star Ruler 2" project
in either Debug or Non-Steam Release configuration.

Please note that while the built exe ends up in the bin/win64/ directory, it expects to be
started with its working directory set to the main directory (where the
launcher exe is). So when debugging from visual studio, make sure the 'Working
Directory' configuration property is set to ../../..

### Building on Linux
The equivalent launcher on linux is StarRuler2.sh. To build the binary files on linux,
make sure your working directory is set to the main directory (the one with StarRuler2.sh in it),
then run `make -f source/linux/Makefile compile` to compile the binary.

Afterward, run the `StarRuler2.sh` shell script to start the game.

Several dependencies are required to build on linux, including libpng, zlib,
GLEW, GLU, freetype2, libvorbisfile, libvorbis, libogg, libopenal, libbz2,
libXRandR, and libcurl.


## Differences with Commercial Version
* The music is not part of the open source release of Star Ruler 2. The data/music/ directory from the commercial
  release can be copied directly into the data/ directory of an open-source build. The music will be detected and played.
* All code for accessing the SteamWorks API has been removed. The game platform abstraction layer game\_platform.h has 
  been kept intact, so other mod-sharing platforms could potentially be integrated into the game.
* Code for the automatic game patcher that is part of the GOG.com release is part of the repository, but the functionality
  is disabled, since it relies on delta updates and will not work with modified open source versions.
* While the actual source code is probably still compatible with 32-bit platforms, project files and external dependencies for
  32-bit builds are not included in this repository.

## FAQ
### Can I Play Multiplayer with Steam/GOG versions?
Yes. The base open source version is multiplayer-compatible with the commercial versions. If you make multiplayer-incompatible
changes to the open source version, please remember to change the MP\_VERSION identifier in scripts/definitions/version.as,
so things do not break from people with incompatible versions trying to join each other.

### Does this have the Wake of the Heralds DLC Expansion?
Yes. The code has been modified to bypass all DLC checks and unlock it by default. The Wake of the Heralds content
is always available in the open-source version.

### Is there a Community?
Most Star Ruler 2 community activity is centered around the [Steam Forums](https://steamcommunity.com/app/282590/discussions/)
(it is possible to post without owning the game on steam), and the [Discord Server for Rising Stars](https://discord.gg/9YyXgbh),
one of the largest SR2 mod projects.

## Licensing
Star Ruler 2 source code is licensed as MIT, art assets are licensed as CC-BY-NC 2.0.

Some third party code is contained in this repository as dependencies. Licenses for those projects are contained in the appropriate source folders.

See the COPYING file for more information.
