#pragma once
#define GAME_VERSION 1
#define GAME_VERSION_NAME "0.0.1"
#define ENGINE_BUILD 1
#define SERVER_SCRIPT_BUILD 1
#define CLIENT_SCRIPT_BUILD 1
#define MENU_SCRIPT_BUILD 1
#ifdef _MSC_VER
#define ARCH_NAME "W"
#ifdef _M_AMD64
#define ARCH_BITS 64
#else
#define ARCH_BITS 32
#endif
#else
#ifdef __APPLE__
#define ARCH_NAME "A"
#else
#define ARCH_NAME "L"
#endif
#ifdef __amd64__
#define ARCH_BITS 64
#else
#define ARCH_BITS 32
#endif
#endif
#define BUILD_VERSION "DEV"
