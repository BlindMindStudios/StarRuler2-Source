#include "CSoundSource.h"
#include "ISoundDevice.h"

#include "al.h"
#include "alc.h"

#include "SLoadError.h"

namespace audio {

	CSoundSource::CSoundSource(ISoundDevice* dev)
		: ISoundSource(dev), volume(1.f)
	{
	}

	CSoundSource::~CSoundSource() {
	}

	void CSoundSource::setDefaultSettings(sourceID source) const {
		alSourcef(source, AL_GAIN, volume);
		const float refDist = 50.f;
		alSourcef(source, AL_REFERENCE_DISTANCE, refDist);
		alSourcef(source, AL_MAX_DISTANCE, refDist * 128.f);
		alSourcef(source, AL_PITCH, 1.f);
		//alSourcef(source, AL_MIN_GAIN, 0.f);
		//alSourcef(source, AL_MAX_GAIN, 1.f);
	}

	void CSoundSource::setDefaultVolume(float volume) {
		if(volume >= 0)
			this->volume = volume;
	}

	float CSoundSource::getDefaultVolume() const {
		return volume;
	}

};