#pragma once

#include "IAudioReference.h"

#include "SoundTypes.h"

namespace audio {

	class ISoundDevice;

	class ISoundSource : public IAudioReference {
	protected:
		ISoundDevice* device;
	public:
		ISoundSource(ISoundDevice* Device);
		virtual ~ISoundSource();

		virtual int getLength_ms() const = 0;

		virtual bool isStreaming() const = 0;

		virtual void setDefaultVolume(float volume) = 0;
		virtual float getDefaultVolume() const = 0;

		ISoundDevice* getDevice() const { return device; }
	};

};