#pragma once

#include "ISoundSource.h"
#include "SoundTypes.h"
#include <stdio.h>

namespace audio {

	class ISoundDevice;

	class CSoundSource : public ISoundSource {
	public:
		CSoundSource(ISoundDevice* dev);
		virtual ~CSoundSource();

		virtual void setDefaultSettings(sourceID source) const;

		virtual bufferID getBuffer() const = 0;
		virtual bufferID getStreamBuffer(long& point) const = 0;

		virtual void setDefaultVolume(float volume);
		virtual float getDefaultVolume() const;

	protected:
		float volume;
	};
	
	CSoundSource* load_ogg(FILE* file, ISoundDevice* device);
	CSoundSource* load_wav(FILE* file, ISoundDevice* device);

	CSoundSource* load_ogg_stream(FILE* file, ISoundDevice* device);

};