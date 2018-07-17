#include "ISoundDevice.h"

#include "al.h"
#include "alc.h"
#include "alext.h"

#include <vector>
#include <list>
#include <deque>
#include <string>
#include <assert.h>

#include "threads.h"

#include "SLoadError.h"
#include "SAutoDrop.h"

#include "CSSWave.h"

#include "CSound.h"
#include "CStreamSound.h"

threads::Mutex soundMutex;

#define PRIORITY_SOURCE_COUNT 16

//#define DEBUG_SOUND
void CloseVorbisFile();

struct SoundThreadData {
	threads::Mutex mutex;
	std::list<audio::ISound*> sounds;
	bool finish;
	bool threadDone;

	inline void lock() {
		mutex.lock();
	}

	inline void unlock() {
		mutex.release();
	}

	void addSound(audio::ISound* snd) {
		lock();
		sounds.push_back(snd);
		unlock();
	}

	void stop() {
		finish = true;
		lock();
		for(auto i = sounds.begin(), end = sounds.end(); i != end; ++i) {
			audio::ISound* sound = *i;
			sound->stop();
		}
		unlock();
		while(!threadDone)
			threads::sleep(1);
	}

	SoundThreadData() {
		finish = false;
		threadDone = false;
	}
};

struct AutoClose {
	FILE* file;

	AutoClose(FILE* pFile) : file(pFile) {}
	~AutoClose() { if(file) fclose(file); }
};

threads::threadreturn threadcall soundManager(void* userData) {
	using namespace audio;
	SoundThreadData& data = *(SoundThreadData*)userData;

	while(!data.finish) {
		data.lock();

		for(auto i = data.sounds.begin(), end = data.sounds.end(); i != end;) {
			ISound& snd = **i;
			snd.streamData();
			if(snd.isStopped()) {
				i = data.sounds.erase(i);
				data.unlock();

				snd.drop();

				data.lock();
			}
			else {
				++i;
			}
		}

		data.unlock();

		threads::sleep(50);
	}

	for(auto i = data.sounds.begin(), end = data.sounds.end(); i != end; ++i)
		(*i)->drop();
	data.sounds.clear();

	data.threadDone = true;
	return 0;
}

namespace audio {

#ifndef NDEBUG
void checkError() {
	ALenum err = alGetError();
	assert(err == AL_NO_ERROR);
}
#else
void checkError() {}
#endif
	
	class CSoundDevice : public ISoundDevice {
		SoundThreadData* threadData;
		ALCdevice* device;
		ALCcontext* context;
		std::vector<ALuint> buffers, sources, filters;
		std::deque<ALuint> freeBuffers, freeSources, prioritySources, freeFilters;
		bool playSounds;

		bool efx;
		ALint maxAuxilliary;
		
		LPALGENEFFECTS genEffects;
		LPALDELETEEFFECTS delEffects;

		LPALGENFILTERS genFilters;
		LPALDELETEFILTERS delFilters;
		LPALFILTERF setFilterf;
		LPALFILTERI setFilteri;
	public:

		void registerSound(ISound* sound) {
			threadData->addSound(sound);
		}

		CSoundDevice(const char* soundDeviceName) : device(0), context(0), playSounds(false), efx(false), maxAuxilliary(0) {
			if(soundDeviceName) {
				device = alcOpenDevice(soundDeviceName);
				//TODO: Inform of error
			}

			if(device == 0)
				device = alcOpenDevice(0);

			if(device == 0)
				throw "Could not initialize sound system";
			alcGetError(device);

			ALint attribs[4] = {0,0,0,0};

			if(alcIsExtensionPresent(device, "ALC_EXT_EFX") != AL_FALSE) {
				efx = true;
				attribs[0] = ALC_MAX_AUXILIARY_SENDS;
				attribs[1] = 4;
			}

			try {
				context = alcCreateContext(device, attribs);
				if(efx) {
					alcGetIntegerv(device, ALC_MAX_AUXILIARY_SENDS, 1, &maxAuxilliary);
					genEffects = (LPALGENEFFECTS)alGetProcAddress("alGenEffects");
					delEffects = (LPALDELETEEFFECTS)alGetProcAddress("alDeleteEffects");
					genFilters = (LPALGENFILTERS)alGetProcAddress("alGenFilters");
					delFilters = (LPALDELETEFILTERS)alGetProcAddress("alDeleteFilters");
					setFilterf = (LPALFILTERF)alGetProcAddress("alFilterf");
					setFilteri = (LPALFILTERI)alGetProcAddress("alFilteri");
					if(!genEffects || !delEffects || !genFilters || !delFilters || !setFilterf || !setFilteri)
						efx = false;
				}
				alcMakeContextCurrent(context);

				//Fetch as many buffers as possible (up to 512)
				while(buffers.size() < 512) {
					unsigned int prevSize = buffers.size();
					buffers.resize(prevSize + 32);
					alGenBuffers(32, buffers.data() + prevSize);
					if(alcGetError(device) != ALC_NO_ERROR) {
						buffers.resize(prevSize);
						break;
					}
				}

				if(buffers.empty())
					throw "Error generating buffers";

				for(unsigned int i = 0; i < buffers.size(); ++i)
					freeBuffers.push_back(buffers[i]);

				//Fetch sources (up to 128)
				while(sources.size() < 128) {
					unsigned int prevSize = sources.size();
					sources.resize(prevSize + 32);
					alGenSources(32, sources.data() + prevSize);
					if(alcGetError(device) != ALC_NO_ERROR) {
						sources.resize(prevSize);
						break;
					}
				}

				if(sources.empty())
					throw "Error generating sources";

				{
					unsigned int i = 0;
					for(; i < sources.size() && i < PRIORITY_SOURCE_COUNT; ++i)
						prioritySources.push_back(sources[i]);
					for(; i < sources.size(); ++i)
						freeSources.push_back(sources[i]);
				}

				alDistanceModel(AL_EXPONENT_DISTANCE/*_CLAMPED*/);

				if(efx) {
					alGetError();
					//Generate up to as many filters as we can have sources
					while(filters.size() < sources.size()) {
						ALuint id;
						genFilters(1, &id);
						if(alGetError() != AL_NO_ERROR)
							break;
						filters.push_back(id);
						freeFilters.push_back(id);
					}
				}

	#ifdef DEBUG_SOUND
				print("==SOUND==\nBuffers: %i, Sources: %i\n", buffers.size(), sources.size());
	#endif

				threadData = new SoundThreadData();
				threads::createThread(soundManager, (void*)threadData);
			}
			catch(const char* pStr) {
				//Cleanup any resources
				if(!filters.empty()) {
					delFilters(filters.size(), filters.data());
					filters.clear();
				}
				if(!buffers.empty()) {
					alDeleteBuffers(buffers.size(), buffers.data());
					buffers.clear();
				}
				if(!sources.empty()) {
					alDeleteSources(sources.size(), sources.data());
					sources.clear();
				}
				if(context != 0) {
					alcMakeContextCurrent(0);
					alcDestroyContext(context);
				}
				if(device != 0)
					alcCloseDevice(device);
				throw pStr;
			}
		}

		~CSoundDevice() {
			alDeleteBuffers(buffers.size(), buffers.data());
			alDeleteSources(sources.size(), sources.data());

			alcMakeContextCurrent(0);
			alcDestroyContext(context);

			threadData->stop();
			delete threadData;
		
			alcCloseDevice(device);

			CloseVorbisFile();
		}
		
		void stopAllSounds() {
			threadData->stop();
			delete threadData;

			threadData = new SoundThreadData;
			threads::createThread(soundManager, (void*)threadData);
		}

		sourceID getFreeSourceID(bool priority) {
			sourceID id = invalidSource;

			soundMutex.lock();
			if(priority && !prioritySources.empty()) {
				id = *prioritySources.begin();
				prioritySources.pop_front();
			}
			else if(!freeSources.empty()) {
				id = *freeSources.begin();
				freeSources.pop_front();
			}
			soundMutex.release();

			return id;
		}

		void freeSource(sourceID id) {
			if(id == invalidSource)
				return;
			soundMutex.lock();
			if(prioritySources.size() < PRIORITY_SOURCE_COUNT)
				prioritySources.push_front(id);
			else
				freeSources.push_front(id);
			soundMutex.release();
		}

		bool hasFreeSources(bool priority) {
			if(!freeSources.empty())
				return true;
			if(priority && !prioritySources.empty())
				return true;
			return false;
		}

		bufferID getFreeBufferID() {
			if(freeBuffers.empty())
				return invalidBuffer;

			soundMutex.lock();

			bufferID id = *freeBuffers.begin();
			freeBuffers.erase(freeBuffers.begin());
		
			soundMutex.release();

			return id;
		}

		void freeBuffer(bufferID id) {
			if(id == invalidBuffer)
				return;

			soundMutex.lock();
			freeBuffers.push_front(id);
			soundMutex.release();
		}

		sourceID applyLowPassFilter(sourceID applyTo, float strength) {
			if(!efx || freeFilters.empty() || applyTo == invalidSource)
				return invalidSource;

			soundMutex.lock();
			sourceID filter = invalidSource;
			if(!freeFilters.empty()) {
				filter = freeFilters.front();
				freeFilters.pop_front();
			}
			soundMutex.release();

			if(filter != invalidSource) {
				setFilteri(filter, AL_FILTER_TYPE, AL_FILTER_LOWPASS);
				setFilterf(filter, AL_LOWPASS_GAIN, 1.f);
				setFilterf(filter, AL_LOWPASS_GAINHF, 1.f - strength);
				alSourcei(applyTo, AL_DIRECT_FILTER, filter);
				checkError();
			}

			return filter;
		}

		void freeFilter(sourceID fromSound, sourceID id) {
			if(id == invalidBuffer)
				return;

			if(fromSound != invalidBuffer) {
				alSourcei(fromSound, AL_DIRECT_FILTER, AL_FILTER_NULL);
				checkError();
			}

			soundMutex.lock();
			freeFilters.push_back(id);
			soundMutex.release();
		}

		ISoundSource* loadSound(const std::string& fileName) {
			FILE* file = fopen(fileName.c_str(), "rb");
			if(file == 0)
				throw SLoadError("File does not exist", true);

			AutoClose close(file);

			ISoundSource* source = 0;

			try {
				source = load_wav(file, this);
			}
			catch(NotThisType) { fseek(file, 0, SEEK_SET); }

			try {
				if(source == 0) {
					source = load_ogg(file, this);
					close.file = 0;
				}
			}
			catch(NotThisType) { fseek(file, 0, SEEK_SET); }

			if(source == 0)
				throw SLoadError("Unsupported format", false);

			return source;
		}

		ISoundSource* loadStreamingSound(const std::string& fileName) {
			FILE* file = fopen(fileName.c_str(), "rb");
			if(file == 0)
				throw SLoadError("File does not exist", true);

			AutoClose close(file);

			ISoundSource* source = 0;

			try {
				source = load_ogg_stream(file, this);
				close.file = 0;
			}
			catch(NotThisType) {  }

			if(source == 0)
				throw SLoadError("Unsupported format", false);

			return source;
		}

		void lock() {
			soundMutex.lock();
		}

		void unlock() {
			soundMutex.release();
		}

		void setListenerData(const snd_vec& pos, const snd_vec& vel, const snd_vec& at, const snd_vec& up) {
			soundMutex.lock();

			snd_vec Pos = sync(pos), Vel = sync(vel);

			struct {
				snd_vec At, Up;
			} View;

			View.At = sync((at - pos).normalize());
			View.Up = sync(up);

			alListenerfv(AL_POSITION, (const ALfloat*)&Pos);
			alListenerfv(AL_VELOCITY, (const ALfloat*)&Vel);
			alListenerfv(AL_ORIENTATION, (const ALfloat*)&View);

			soundMutex.release();
		}

		ISound* play2D(const ISoundSource* sound, bool loop, bool startPaused, bool priority) {
			if(!sound || !playSounds || !hasFreeSources(priority))
				return 0;
			lock();

			ISound* snd;
			if(sound->isStreaming())
				snd = new CStreamSound(sound, false, priority);
			else
				snd = new CSound(sound, false, priority);

			snd->setLooped(loop);
			snd->resume();
			if(startPaused)
				snd->pause();

			if(snd->isStopped()) {
				snd->drop();
				unlock();
				return 0;
			}

			unlock();
			registerSound(snd);
			return snd;
		}

		ISound* play3D(const ISoundSource* sound, const snd_vec& at, bool loop, bool startPaused, bool priority) {
			if(!sound || !playSounds || !valid(at) || !hasFreeSources(priority))
				return 0;

			lock();

			ISound* snd;
			if(sound->isStreaming())
				snd = new CStreamSound(sound, true, priority);
			else
				snd = new CSound(sound, true, priority);

			snd->setPosition(at.x, at.y, at.z);
			snd->setLooped(loop);

			//Always do a resume step here so pause() will set the state to PAUSED rather than STOPPED
			snd->resume();
			if(startPaused)
				snd->pause();

			if(snd->isStopped()) {
				snd->drop();
				unlock();
				return 0;
			}

			unlock();
			registerSound(snd);
			return snd;
		}

		void setVolume(float volume) {
			playSounds = volume > 0;
			if(volume >= 0)
				alListenerf(AL_GAIN, volume);
		}

		float getVolume() const {
			float ret = 0;
			alGetListenerf(AL_GAIN, &ret);
			return ret;
		}

		void setRolloffFactor(float rolloff) {
			lock();
			for(unsigned int i = 0; i < sources.size(); ++i)
				alSourcef(sources[i], AL_ROLLOFF_FACTOR, rolloff);
			unlock();
		}
	};

	//Creates an instance of CSoundDevice
	ISoundDevice* createAudioDevice(const char* useSoundDevice) {
		return new CSoundDevice(useSoundDevice);
	}

	
	class CDummySoundDevice : public ISoundDevice {
		sourceID getFreeSourceID(bool priority) { return invalidSource; }
		void freeSource(sourceID id) {}

		bufferID getFreeBufferID() { return invalidBuffer; }
		void freeBuffer(bufferID id) {}

		void registerSound(ISound* sound) {}
		
		ISoundSource* loadSound(const std::string& fileName) { return 0; }
		ISoundSource* loadStreamingSound(const std::string& fileName) { return 0; }

		void setListenerData(const snd_vec& pos, const snd_vec& vel, const snd_vec& at, const snd_vec& up) {}

		void lock() {}
		void unlock() {}

		ISound* play2D(const ISoundSource* sound, bool loop, bool startPaused, bool priority) { return 0; }
		ISound* play3D(const ISoundSource* sound, const snd_vec& at, bool loop, bool startPaused, bool priority) { return 0; }

		sourceID applyLowPassFilter(sourceID applyTo, float strength) { return invalidSource; }
		void freeFilter(sourceID from, sourceID id) {}

		void setVolume(float volume) {}
		float getVolume() const { return 0; }

		void setRolloffFactor(float rolloff) {}
		
		void stopAllSounds() {}
	};
	
	ISoundDevice* createDummyAudioDevice() {
		return new CDummySoundDevice();
	}

	void enumerateDevices(std::function<void(const char*)> cb) {
		if(!cb)
			return;

		const char* deviceNames = nullptr;
		if(alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT") == AL_TRUE)
			deviceNames = alcGetString(nullptr, ALC_ALL_DEVICES_SPECIFIER);
		else if(alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_EXT") == AL_TRUE)
			deviceNames = alcGetString(nullptr, ALC_DEVICE_SPECIFIER);

		if(!deviceNames)
			return;

		while(true) {
			std::string deviceName = deviceNames;
			if(!deviceName.empty())
				cb(deviceName.c_str());
			deviceNames += deviceName.size() + 1;
			if(deviceNames[0] == '\0')
				break;
		}
	}
};
