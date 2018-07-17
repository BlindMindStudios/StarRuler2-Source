#pragma once

#include "CSoundSource.h"
#include "ISoundDevice.h"
#include <stdio.h>

namespace audio {
	class ISoundDevice;

	class CSSWave : public CSoundSource {
		bufferID soundBuffer;
		int length_ms;
	public:
		CSSWave(FILE* file, ISoundDevice* device);
		~CSSWave();
		
		virtual bool isStreaming() const;
		virtual int getLength_ms() const;
		virtual bufferID getBuffer() const;
		virtual bufferID getStreamBuffer(long& point) const;
	};
};