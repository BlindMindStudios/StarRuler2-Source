#!/bin/bash
CI_PATH="/c/Users/GGLucas/Documents/sr2_ci"
SRC_PATH="/u/source"
LOG_PATH="/u/log"
DEST_PATH="/u/dest"
DEVENV_DIR="/c/Program Files (x86)/Microsoft Visual Studio 10.0/Common7/IDE"
DBG_DIR="/c/Program Files (x86)/Debugging Tools for Windows (x86)"

BUILD_PATH="$CI_PATH/build"
FLAG_FILE="$SRC_PATH/WIN_COMPILE"
PATH="$DEVENV_DIR:$DBG_DIR:$PATH"

#Check for the existence of the compile marker and compile
#when it's there (ghetto IPC over sshfs woot woot)
while true; do
        if [[ ! -f "$FLAG_FILE" ]]; then
                sleep 30
                continue
        fi

        date
        echo "COMPILING WINDOWS BUILD"

        #Copy over the source to a fresh directory
        mkdir -p "$BUILD_PATH"
        cp -ra "$SRC_PATH/source" "$BUILD_PATH"
        cp -ra "$SRC_PATH/bin" "$BUILD_PATH"

        #Remove conflicting glfw config.h
        rm "$BUILD_PATH/source/glfw/src/config.h"

        #Build the project (32 bit)
        cd "$BUILD_PATH/source/msvc10/Star Ruler 2"
        devenv.com "Star Ruler 2.sln" //Build "Release|Win32" > msvc32_build.log
        echo ---SECONDARY BUILD-- >> msvc32_build.log
        devenv.com "Star Ruler 2.sln" //Build "Release|Win32" >> msvc32_build.log

        #Build the project (64 bit)
        cd "$BUILD_PATH/source/msvc10/Star Ruler 2"
        devenv.com "Star Ruler 2.sln" //Build "Release|x64" > msvc64_build.log
        echo ---SECONDARY BUILD-- >> msvc64_build.log
        devenv.com "Star Ruler 2.sln" //Build "Release|x64" >> msvc64_build.log

        #Copy built files
        cp msvc32_build.log "$LOG_PATH"
        cp msvc64_build.log "$LOG_PATH"

        #Store symbols
        cd "$BUILD_PATH/bin"
        symstore.exe add //s /u/symbols //compress //r //f *.pdb //t SR2

        cd "$BUILD_PATH"
        mkdir -p "$DEST_PATH/bin/win32"
        mkdir -p "$DEST_PATH/bin/win64"
        [[ -f "Star Ruler 2.exe" ]] && cp "Star Ruler 2.exe" "$DEST_PATH"
        cp bin/win32/*.{dll,exe} "$DEST_PATH/bin/win32"
        cp bin/win64/*.{dll,exe} "$DEST_PATH/bin/win64"

        #Remove leftover files
        cd "$SRC_PATH"
        rm -rf "$BUILD_PATH"
        rm "$FLAG_FILE"
done
