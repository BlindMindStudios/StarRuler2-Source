#pragma once


#include "IAudioReference.h"
#include "SoundTypes.h"
#include "sound_vector.h"

#include <string>
#include <list>
#include <vector>
#include <functional>

namespace audio {
	class ISound;
	class ISoundSource;

	extern void checkError();

	class ISoundDevice : public IAudioReference {
	public:

		virtual ISound* play2D(const ISoundSource* sound, bool loop = false, bool startPaused = false, bool priority = false) = 0;
		virtual ISound* play3D(const ISoundSource* sound, const snd_vec& at, bool loop = false, bool startPaused = false, bool priority = false) = 0;

		virtual void stopAllSounds() = 0;

		virtual void setListenerData(const snd_vec& pos, const snd_vec& vel, const snd_vec& at, const snd_vec& up) = 0;

		virtual void setVolume(float volume) = 0;
		virtual float getVolume() const = 0;
		virtual void setRolloffFactor(float rolloff) = 0;
		
		virtual ISoundSource* loadSound(const std::string& fileName) = 0;
		virtual ISoundSource* loadStreamingSound(const std::string& fileName) = 0;

		//Returns a unique source ID. If this ID is valid, it should be passed to freeSource() when it is no longer used.
		virtual sourceID getFreeSourceID(bool priority) = 0;
		virtual void freeSource(sourceID id) = 0;

		virtual bufferID getFreeBufferID() = 0;
		virtual void freeBuffer(bufferID id) = 0;

		virtual sourceID applyLowPassFilter(sourceID applyTo, float strength) = 0;
		virtual void freeFilter(sourceID fromSource, sourceID id) = 0;

		//Prevents alterations to the sound system until unlockSounds() is called
		virtual void lock() = 0;
		//Allows alterations to the sound system after a call to lockSounds()
		virtual void unlock() = 0;

		virtual ~ISoundDevice();
	};

	_export void enumerateDevices(std::function<void(const char*)> cb);
	_export ISoundDevice* createAudioDevice(const char* useSoundDevice = 0);
	_export ISoundDevice* createDummyAudioDevice();
};
