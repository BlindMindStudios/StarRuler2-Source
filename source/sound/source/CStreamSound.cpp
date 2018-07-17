#include "CStreamSound.h"

#include "ISoundDevice.h"
#include "CSoundSource.h"
#include "SAutoLocker.h"
#include "sound_vector.h"

#include "al.h"
#include "alc.h"

namespace audio {

	CStreamSound::CStreamSound(const ISoundSource* sound, bool is3D, bool priority)
		: soundID(invalidSource), filterID(invalidSource), soundSource(0), streamPos(0), loop(false), timestamp(0), resetStampID(invalidBuffer)
	{
		const CSoundSource* snd = dynamic_cast<const CSoundSource*>(sound);
		if(snd == 0)
			return;

		ISoundDevice* device = snd->getDevice();

		SAutoLocker<ISoundDevice> lock(device);

		alGetError();

		bufferID buffer = snd->getStreamBuffer(streamPos);
		if(!alIsBuffer(buffer))
			return;

		sourceID id = device->getFreeSourceID(priority);
		if(!alIsSource(id)) {
			device->freeBuffer(buffer);
			return;
		}

		alSourceQueueBuffers(id, 1, &buffer);
		if(alGetError() != AL_NO_ERROR) {
			device->freeBuffer(buffer);
			device->freeSource(id);
			return;
		}

		buffers.insert(buffer);

		{
			ALint freq, channels, bits;
			alGetBufferi(buffer, AL_FREQUENCY, &freq);
			alGetBufferi(buffer, AL_CHANNELS, &channels);
			alGetBufferi(buffer, AL_BITS, &bits);
			byterate = freq * channels * (bits/8);
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
	
	void CStreamSound::freeQueuedBuffers() {
		ALint count = 0;
		alGetSourcei(soundID,AL_BUFFERS_PROCESSED,&count);
		ALuint* buffList = (ALuint*)alloca(count * sizeof(ALint));

		alSourceUnqueueBuffers(soundID,count,buffList);

		for(ALint i = 0; i < count; ++i) {
			bufferID buffer = buffList[i];

			if(buffer == resetStampID) {
				timestamp = 0;
				resetStampID = invalidBuffer;
			}

			ALint size;
			alGetBufferi(buffer, AL_SIZE, &size);
			timestamp += unsigned(size);

			soundSource->getDevice()->freeBuffer(buffer);
			buffers.erase(buffer);
		}
		checkError();
	}

	CStreamSound::~CStreamSound() {
		if(soundSource) {
			freeQueuedBuffers();
			alSourcei(soundID, AL_BUFFER, 0);
			checkError();

			auto* device = soundSource->getDevice();
			device->freeSource(soundID);
			for(auto i = buffers.begin(); i != buffers.end(); ++i)
				device->freeBuffer(*i);
			if(filterID != invalidSource)
				device->freeFilter(soundID, filterID);

			soundSource->drop();
			soundSource = 0;
		}
	}

	void CStreamSound::streamData() {
		acquire();
		if(soundSource) {
			freeQueuedBuffers();

			//Queue up to 4 sound buffers
			ALint queued;
			alGetSourcei(soundID, AL_BUFFERS_QUEUED, &queued);
			if(queued < 4) {
				bufferID buffer = soundSource->getStreamBuffer(streamPos);
				if(alIsBuffer(buffer)) {
					alSourceQueueBuffers(soundID, 1, &buffer);
					buffers.insert(buffer);
				}
				else if(loop) {
					//If we fail to allocate a buffer, assume we reached the end
					//	If we're looping, we start at the beginning again
					streamPos = 0;
					buffer = soundSource->getStreamBuffer(streamPos);
					if(alIsBuffer(buffer)) {
						alSourceQueueBuffers(soundID, 1, &buffer);
						resetStampID = buffer;
						buffers.insert(buffer);
					}
				}
			}
		}
		release();
	}

	bool CStreamSound::isStopped() const {
		if(soundSource == 0)
			return true;
		acquire();
		ALint state;
		alGetSourcei(soundID, AL_SOURCE_STATE, &state);
		release();
		return state == AL_STOPPED;
	}

	bool CStreamSound::isPlaying() const {
		if(!soundSource)
			return false;
		acquire();
		ALint state;
		alGetSourcei(soundID, AL_SOURCE_STATE, &state);
		release();
		return state == AL_PLAYING;
	}

	void CStreamSound::stop() {
		acquire();
		if(soundSource)
			alSourceStop(soundID);
		release();
	}

	void CStreamSound::pause() {
		acquire();
		if(soundSource)
			alSourcePause(soundID);
		release();
	}

	void CStreamSound::resume() {
		acquire();
		if(soundSource)
			alSourcePlay(soundID);
		release();
	}

	void CStreamSound::seek(int timeMS) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_SEC_OFFSET, (float)timeMS / 1000.f);
		release();
	}

	void CStreamSound::setLooped(bool Loop) {
		loop = Loop;
	}

	bool CStreamSound::isLooped() const {
		return loop;
	}

	void CStreamSound::setPosition(float x, float y, float z) {
		if(!valid(x,y,z))
			return;
		sync(x,y,z);
		acquire();
		if(soundSource)
			alSource3f(soundID, AL_POSITION, x, y, z);
		release();
	}

	void CStreamSound::setVelocity(float x, float y, float z) {
		if(!valid(x,y,z))
			return;
		sync(x,y,z);
		acquire();
		if(soundSource)
			alSource3f(soundID, AL_VELOCITY, x, y, z);
		release();
	}

	void CStreamSound::setRolloff(float factor) {
		acquire();
		if(factor >= 0.f && soundSource)
			alSourcef(soundID, AL_ROLLOFF_FACTOR, factor);
		release();
	}
	
	void CStreamSound::setLowPass(float strength) {
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

	void CStreamSound::setVolume(float volume) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_GAIN, volume * soundSource->getDefaultVolume());
		release();
	}

	void CStreamSound::setPitch(float pitch) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_PITCH, pitch);
		release();
	}

	void CStreamSound::setPlayPosition(int timeMs) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_SEC_OFFSET, (float)timeMs / 1000.f);
		release();
	}

	int CStreamSound::getPlayPosition() {
		acquire();
		if(soundSource) {
			float offset;
			alGetSourcef(soundID, AL_SEC_OFFSET, &offset);

			int time = int(((double(timestamp) * 1000.0) / double(byterate)) + double(offset * 1000.f));

			//When looping, the timestamp can exceed the file length; correct for this
			if(loop) {
				int length = soundSource->getLength_ms();
				if(time > length)
					time = time % length;
			}
			
			release();
			return time;
		}
		
		release();
		return 0;
	}

	int CStreamSound::getPlayLength() {
		int len = -1;
		acquire();
		if(soundSource)
			len = soundSource->getLength_ms();
		release();
		return len;
	}

	void CStreamSound::setMinDistance(float minDist) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_REFERENCE_DISTANCE, minDist);
		release();
	}

	void CStreamSound::setMaxDistance(float maxDist) {
		acquire();
		if(soundSource)
			alSourcef(soundID, AL_MAX_DISTANCE, maxDist);
		release();
	}

	const ISoundSource* CStreamSound::getSoundSource() {
		return soundSource;
	}
};