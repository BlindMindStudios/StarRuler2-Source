#include "binds.h"
#include "main/references.h"
#include "main/initialization.h"
#include "main/logging.h"
#include "ISoundSource.h"
#include "ISoundDevice.h"
#include "ISound.h"
#include "SLoadError.h"
#include <string>

namespace scripts {

static bool soundEnabled() {
	return use_sound;
}

static float soundVolume() {
	return devices.sound->getVolume();
}

static void setSoundVolume(float vol) {
	devices.sound->setVolume(vol);
}

static void setSoundScale(float scale) {
	devices.sound->setRolloffFactor(1.f / scale);
}

static const resource::Sound* getSound(const std::string& name) {
	return devices.library.getSound(name);
}

static audio::ISound* playTrack(const std::string& file, bool loop, bool paused) {
	try {
		auto* source = devices.sound->loadStreamingSound(devices.mods.resolve(file));
		if(source) {
			audio::ISound* sound = devices.sound->play2D(source, loop, paused, true);
			if(sound)
				sound->grab();
			source->drop();
			return sound;
		}
		else {
			return 0;
		}
	}
	catch(audio::SLoadError) {
		return 0;
	}
}

static audio::ISound* playTrack3D(const std::string& file, const vec3d& pos, bool loop, bool paused) {
	try {
		auto* source = devices.sound->loadStreamingSound(devices.mods.resolve(file));
		if(source) {
			audio::ISound* sound = devices.sound->play3D(source, snd_vec(pos), loop, paused, true);
			if(sound)
				sound->grab();
			source->drop();
			return sound;
		}
		else {
			return 0;
		}
	}
	catch(audio::SLoadError) {
		return 0;
	}
}

static void setSoundPos(audio::ISound* snd, const vec3d& pos) {
	snd->setPosition((float)pos.x, (float)pos.y, (float)pos.z);
}

static void setSoundVel(audio::ISound* snd, const vec3d& vel) {
	snd->setVelocity((float)vel.x, (float)vel.y, (float)vel.z);
}

static float defaultVolume(resource::Sound* snd) {
	if(!snd->loaded)
		return 0.f;
	return snd->source->getDefaultVolume();
}

void RegisterSoundBinds() {
	//Sound progress
	ClassBind sp("Sound", asOBJ_REF, 0);
	sp.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(audio::ISound, grab));
	sp.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(audio::ISound, drop));

	sp.addMethod("bool get_stopped()", asMETHOD(audio::ISound, isStopped));
	sp.addMethod("bool get_playing()", asMETHOD(audio::ISound, isPlaying));
	sp.addMethod("bool get_loop()", asMETHOD(audio::ISound, isLooped));

	sp.addMethod("void set_paused(bool)", asMETHOD(audio::ISound, setIsPaused));
	sp.addMethod("void set_loop(bool)", asMETHOD(audio::ISound, setLooped));
	sp.addMethod("void set_volume(float factor)", asMETHOD(audio::ISound, setVolume));
	sp.addMethod("void set_pitch(float factor)", asMETHOD(audio::ISound, setPitch));

	sp.addMethod("int get_playLength()", asMETHOD(audio::ISound, getPlayLength));
	sp.addMethod("int get_playPosition()", asMETHOD(audio::ISound, getPlayPosition));
	sp.addMethod("void set_playPosition(int pos)", asMETHOD(audio::ISound, setPlayPosition));
	sp.addMethod("void seek(int pos)", asMETHOD(audio::ISound, seek));

	sp.addMethod("void set_minDistance(float dist)", asMETHOD(audio::ISound, setMinDistance));
	sp.addMethod("void set_maxDistance(float dist)", asMETHOD(audio::ISound, setMaxDistance));

	sp.addMethod("void pause()", asMETHOD(audio::ISound, pause));
	sp.addMethod("void resume()", asMETHOD(audio::ISound, resume));
	sp.addMethod("void stop()", asMETHOD(audio::ISound, stop));

	sp.addExternMethod("void set_position(const vec3d &in pos)", asFUNCTION(setSoundPos));
	sp.addExternMethod("void set_velocity(const vec3d &in pos)", asFUNCTION(setSoundVel));
	sp.addMethod("void set_rolloff(float)", asMETHOD(audio::ISound, setRolloff))
		doc("Sets how much distance attentuates the volume of 3D sounds.", "Rolloff factor. Higher values increase attenuation. Default for 3D sounds is 1.");

	//Sound source
	ClassBind ss("SoundSource", asOBJ_REF | asOBJ_NOCOUNT, 0);
	ss.addMember("bool loaded", offsetof(resource::Sound, loaded));
	ss.addMethod("Sound@ play(bool loop = false, bool pause = false, bool priority = false) const", asMETHOD(resource::Sound,play2D));
	ss.addMethod("Sound@ play(const vec3d &in position, bool loop = false, bool pause = false, bool priority = false) const", asMETHOD(resource::Sound,play3D));

	ss.addExternMethod("float get_defaultVolume() const", asFUNCTION(defaultVolume));

	//Global access
	bind("const SoundSource@ getSound(const string &in id)", asFUNCTION(getSound))
		doc("Returns the sound source associated with the id.", "id as specified in the data file.", "Can be null if not present.");
	bind("Sound@ playTrack(const string &in filename, bool loop = false, bool pause = false)", asFUNCTION(playTrack))
		doc("Plays a streaming sound source from the beginning.", "Filename to play.", "Whether to loop the sound. Defaults to false.", "Whether to start the sound paused. Defaults to false.", "Handle to the sound.");
	bind("Sound@ playTrack(const string &in filename, const vec3d &in pos, bool loop = false, bool pause = false)", asFUNCTION(playTrack3D))
		doc("Plays a streaming sound source from the beginning.", "Filename to play.", "Position to play from.", "Whether to loop the sound. Defaults to false.", "Whether to start the sound paused. Defaults to false.", "Handle to the sound.");
	bind("bool get_soundEnabled()", asFUNCTION(soundEnabled))
		doc("Returns true if the sound system is present (even at 0 volume).", "");
	bind("float get_soundVolume()", asFUNCTION(soundVolume))
		doc("Returns the current volume of the sound system.", "Multiplier to output volume between 0 and 1.");
	bind("void set_soundVolume(float)", asFUNCTION(setSoundVolume))
		doc("Sets the sound system's volume.", "Multiplier to output volume between 0 and 1.");
	bind("void set_soundScale(float)", asFUNCTION(setSoundScale))
		doc("Sets the overall scale of the sound system's world.", "Value of the scale.");
	bindGlobal("bool soundDisableSFX", &audio::disableSFX)
		doc("Whether to disable creation of SFX sounds.");

	//Bind sound globals
	{
		Namespace ns("sound");
		foreach(it, devices.library.sounds)
			bindGlobal(format("const ::SoundSource $1", it->first).c_str(), it->second);
	}
}

};
