#!/bin/bash
#Figure out where the script is located
if [[ -L "$0" ]]; then
	script_loc="$(readlink "$0")"
else
	script_loc="$0"
fi
cd "$(dirname "$script_loc")"

#Execute the right binary for this architecture
if [ `uname` == "Darwin" ]; then
    chmod +x ./bin/osx64/StarRuler2.bin
    DYLD_LIBRARY_PATH="./bin/osx64/:$DYLD_LIBRARY_PATH" exec ./bin/osx64/StarRuler2.bin $@
elif [ `uname -m` = "x86_64" ]; then
    chmod +x ./bin/lin64/StarRuler2.bin
    LD_LIBRARY_PATH="./bin/lin64/:$LD_LIBRARY_PATH" exec ./bin/lin64/StarRuler2.bin $@
else
    chmod +x ./bin/lin32/StarRuler2.bin
    LD_LIBRARY_PATH="./bin/lin32/:$LD_LIBRARY_PATH" exec ./bin/lin32/StarRuler2.bin $@
fi;
# vim: set ff=unix:
