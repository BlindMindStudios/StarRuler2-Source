#include "main/references.h"
#include "main/logging.h"
#include "main/initialization.h"
#include "resource/library.h"
#include "ISound.h"
#include "ISoundSource.h"
#include "ISoundDevice.h"
#include "SLoadError.h"
#include "files.h"
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <queue>

namespace resource {

struct QueuedSound {
	int priority;
	Sound* snd;
	std::string filename;
	float volume;

	bool operator<(const QueuedSound& other) const {
		return priority < other.priority;
	}
};
std::priority_queue<QueuedSound> queuedSounds;

audio::ISound* Sound::play2D(bool loop, bool pause, bool priority) const {
	if(!loaded)
		return nullptr;

	if(source) {
		auto* ptr = devices.sound->play2D(source, loop, true, priority);
		if(ptr) {
			ptr->grab();
			if(!pause)
				ptr->resume();
		}
		return ptr;
	}
	else if(!streamSource.empty()) {
		try {
			auto* source = devices.sound->loadStreamingSound(streamSource);
			if(source) {
				source->setDefaultVolume(volume);
				audio::ISound* sound = devices.sound->play2D(source, loop, true, priority);
				if(sound) {
					sound->grab();
					if(!pause)
						sound->resume();
				}
				source->drop();
				return sound;
			}
			else {
				return nullptr;
			}
		}
		catch(audio::SLoadError) {
			return nullptr;
		}
	}

	return nullptr;
}

audio::ISound* Sound::play3D(const vec3d& pos, bool loop, bool pause, bool priority) const {
	if(!loaded)
		return nullptr;

	if(source) {
		auto* ptr = devices.sound->play3D(source, snd_vec(pos), loop, true, priority);
		if(ptr) {
			ptr->grab();
			if(!pause)
				ptr->resume();
		}
		return ptr;
	}
	else if(!streamSource.empty()) {
		try {
			auto* source = devices.sound->loadStreamingSound(streamSource);
			if(source) {
				source->setDefaultVolume(volume);
				audio::ISound* sound = devices.sound->play3D(source, snd_vec(pos), loop, true, priority);
				if(sound) {
					sound->grab();
					if(!pause)
						sound->resume();
				}
				source->drop();
				return sound;
			}
			else {
				return nullptr;
			}
		}
		catch(audio::SLoadError) {
			return nullptr;
		}
	}

	return nullptr;
}

bool Library::hasQueuedSounds() {
	return !queuedSounds.empty();
}

bool Library::processSounds(int maxPriority, int amount) {
	bool processedAny = false;
	int i = 0;
	while(!queuedSounds.empty()) {
		auto elem = queuedSounds.top();
		if(elem.priority < maxPriority)
			break;
		queuedSounds.pop();

		processedAny = true;

		audio::ISoundSource* source = 0;

		try {
			source = devices.sound->loadSound(elem.filename.c_str());
			if(source) {
				source->setDefaultVolume(elem.volume);
				elem.snd->source = source;
				elem.snd->loaded = true;
			}
		}
		catch(const audio::SLoadError& err) {
			error("Could not load sound '%s': %s", elem.filename.c_str(), err.what());
			source = 0;
		}

		++i;

		if(i >= amount)
			break;
	}

	return processedAny;
}

void Library::loadSounds(const std::string& filename) {
	std::string sound_name, sound_file;
	float volume = 1.f;
	int priority = -61;
	bool streamed = false;

	DataHandler datahandler;

	auto makeSound = [&]() {
		if(sound_name.empty() || sound_file.empty())
			return;

		Sound* snd = new Sound();
		if(load_resources && use_sound) {
			if(streamed) {
				snd->streamSource = devices.mods.resolve(sound_file);
				snd->volume = volume;
				if(fileExists(snd->streamSource))
					snd->loaded = true;
				else
					error("Could not locate streaming sound source: '%s'", sound_file.c_str());
			}
			else {
				resource::QueuedSound queued = {priority, snd, devices.mods.resolve(sound_file), volume};
				queuedSounds.push(queued);
			}
		}
		sounds[sound_name] = snd;

		sound_name.clear();
		sound_file.clear();
		volume = 1.f;
		priority = -61;
		streamed = false;
	};

	datahandler("Sound", [&](std::string& value) {
		makeSound();
		sound_name = value;
	});

	datahandler("Stream", [&](std::string& value) {
		makeSound();
		sound_name = value;
		streamed = true;
	});

	datahandler("File", [&](std::string& value) {
		sound_file = value;
	});

	datahandler("Volume", [&](std::string& value) {
		volume = toNumber<float>(value);
	});

	datahandler("LoadPriority", [&](std::string& value) {
		if(streamed)
			error("LoadPriority is not valid for streaming sounds");
		if(value == "Critical" || value == "Menu")
			priority = 10;
		else if(value == "Game")
			priority = -10;
		else
			priority = -111 + toNumber<int>(value);
	});

	datahandler.read(filename);
	makeSound();
}

}
