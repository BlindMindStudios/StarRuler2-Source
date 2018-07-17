#pragma once
#include "render/driver.h"
#include "render/camera.h"
#include "resource/library.h"
#include "scripts/manager.h"
#include "os/driver.h"
#include "mods/mod_manager.h"
#include "profile/keybinds.h"
#include "profile/settings.h"
#include "resource/locale.h"

class Universe;
class NetworkManager;
class PhysicsWorld;
class GamePlatform;

namespace audio {
	class ISoundDevice;
	extern bool disableSFX;
};

struct references {
	os::OSDriver* driver;

	resource::Library library;

	NetworkManager* network;

	GamePlatform* cloud;

	render::RenderDriver* render;
	scene::Node* scene;

	audio::ISoundDevice* sound;

	Universe* universe;

	PhysicsWorld* physics, *nodePhysics;

	resource::Locale locale;

	mods::Manager mods;

	profile::Keybinds keybinds;
	struct {
		profile::Settings mod;
		profile::Settings engine;
	} settings;

	struct {
		scripts::Manager* server;
		scripts::Manager* client;
		scripts::Manager* menu;
		scripts::Manager* cache_server;
		scripts::Manager* cache_shadow;
	} scripts;

	struct {
		asIScriptEngine* server;
		asIScriptEngine* client;
		asIScriptEngine* menu;
	} engines;

	references();
};

extern references devices;
