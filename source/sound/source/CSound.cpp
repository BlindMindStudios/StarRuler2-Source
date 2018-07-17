#include "CSound.h"

#include "ISoundDevice.h"
#include "CSoundSource.h"
#include "SAutoLocker.h"
#include "sound_vector.h"

#include "al.h"
#include "alc.h"

namespace audio {

	CSound::CSound(const ISoundSource* sound, bool is3D, bool priority) : soundID(invalidSource), filterID(invalidSource), soundSource(0) {
		const CSoundSource* snd = dynamic_cast<const CSoundSource*>(sound);
		if(snd == 0)
			return;

		ISoundDevice* device = snd->getDevice();

		SAutoLocker<ISoundDevice> lock(device);

		alGetError();

		bufferID buffer = snd->getBuffer();
		if(!alIsBuffer(buffer))
			return;

		sourceID id = device->getFreeSourceID(priority);
		if(!alIsSource(id))
			return;

		alSourcei(id, AL_BUFFER, buffer);
		if(alGetError() != AL_NO_ERROR) {
			device->freeSource(id);
			return;
		}

		//ALenum err = alGetError();

		snd->setDefaultSettings(id);

		if(is3D) {
			alSourcei(id, AL_SOURCE_RELATIVE, AL_FALSE);
			alSourcef(id, AL_ROLLOFF_FACTOR, 1.f);
			alSource3f(id, AL_VELOCITY, 0,0,0);
		}
		else {
			alSourcei(id, AL_SOURCE_RELATIVE, AL_TRUE);
			alSource3f(id, AL_POSITION, 0,0,0);
			alSource3f(id, AL_VELOCITY, 0,0,0);
			alSourcef(id, AL_ROLLOFF_FACTOR, 0.f);
		}

		soundSource = snd; snd->grab();
		soundID = id;
	}

	CSound::~CSound() {
		if(soundSource) {
			alSourcei(soundID, AL_BUFFER, 0);
			checkError();

			auto* device = soundSource->getDevice();
			device->freeSource(soundID);
			if(filterID != invalidSource)
				device->freeFilter(soundID, filterID);

			soundSource->drop();
			soundSource = 0;
		}
	}

	void CSound::streamData() {	}

	bool CSound::isStopped() const {
		if(soundSource == 0)
			return true;
		ALint state;
		alGetSourcei(soundID, AL_SOURCE_STATE, &state);
		return state == AL_STOPPED;
	}

	bool CSound::isPlaying() const {
		if(!soundSource)
			return false;
		ALint state;
		alGetSourcei(soundID, AL_SOURCE_STATE, &state);
		return state == AL_PLAYING;
	}

	void CSound::pause() {
		acquire();
		if(soundSource)
			alSourcePause(soundID);
		release();
	}

	void CSound::resume() {
		acquire();
		if(soundSource)
			alSourcePlay(soundID);
		release();
	}

	void CSound::seek(int timeMS) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_SEC_OFFSET, (float)timeMS / 1000.f);
		release();
	}

	void CSound::setLooped(bool loop) {
		acquire();
		if(soundSource)
			alSourcei(soundID, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);
		release();
	}

	bool CSound::isLooped() const {
		acquire();
		if(soundSource) {
			int looped;
			alGetSourcei(soundID, AL_LOOPING, &looped);
			release();
			return looped != 0;
		}
		release();
		return false;
	}

	void CSound::stop() {
		acquire();
		if(soundSource)
			alSourceStop(soundID);
		release();
	}

	void CSound::setPosition(float x, float y, float z) {
		if(!valid(x,y,z))
			return;
		acquire();
		sync(x,y,z);
		if(soundSource)
			alSource3f(soundID, AL_POSITION, x, y, z);
		release();
	}

	void CSound::setVelocity(float x, float y, float z) {
		if(!valid(x,y,z))
			return;
		acquire();
		sync(x,y,z);
		if(soundSource)
			alSource3f(soundID, AL_VELOCITY, x, y, z);
		release();
	}

	void CSound::setRolloff(float factor) {
		acquire();
		if(factor >= 0.f && soundSource)
			alSourcef(soundID, AL_ROLLOFF_FACTOR, factor);
		release();
	}
	
	void CSound::setLowPass(float strength) {
		acquire();
		if(soundSource) {
			if(filterID != invalidSource) {
				soundSource->getDevice()->freeFilter(soundID, filterID);
				filterID = invalidSource;
			}

			if(strength > 0)
				filterID = soundSource->getDevice()->applyLowPassFilter(soundID, strength);
		}
		release();
	}

	void CSound::setVolume(float volume) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_GAIN, volume * soundSource->getDefaultVolume());
		release();
	}

	void CSound::setPitch(float pitch) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_PITCH, pitch);
		release();
	}

	void CSound::setPlayPosition(int timeMs) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_SEC_OFFSET, (float)timeMs / 1000.f);
		release();
	}

	int CSound::getPlayPosition() {
		acquire();
		int pos = 0;
		if(soundSource) {
			float posS = 0.f;
			alGetSourcef(soundID, AL_SEC_OFFSET, &posS);
			pos = (int)(posS * 1000.f);
		}
		release();
		return pos;
	}

	int CSound::getPlayLength() {
		acquire();
		if(soundSource) {
			bufferID buffer = soundSource->getBuffer();
			ALint bytesPerSample, channels, frequency, totalBytes;

			alGetBufferi(buffer, AL_CHANNELS, &channels);
			alGetBufferi(buffer, AL_BITS, &bytesPerSample); bytesPerSample = (bytesPerSample * channels) / 8;
			alGetBufferi(buffer, AL_FREQUENCY, &frequency);
			alGetBufferi(buffer, AL_SIZE, &totalBytes);

			ALint samples = totalBytes / bytesPerSample;
			release();
			return (int)((float)samples * 1000.f / (float)frequency);
		}
		release();
		return -1;
	}

	void CSound::setMinDistance(float minDist) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_REFERENCE_DISTANCE, minDist);
		release();
	}

	void CSound::setMaxDistance(float maxDist) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_MAX_DISTANCE, maxDist);
		release();
	}

	const ISoundSource* CSound::getSoundSource() {
		return soundSource;
	}
};