#pragma once
#include "main/tick.h"
#include "os/driver.h"
#include "scripts/manager.h"

void onOverlayToggle(bool state);

void registerInput();
void inputTick();

void bindInputScripts(GameState state ,scripts::Manager* manager);
void clearInputScripts(GameState state);
void clearPressedKeys();
