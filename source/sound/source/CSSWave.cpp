#include "CSSWave.h"

#include "al.h"

#include "SLoadError.h"
#include "SAutoDrop.h"

#include <string.h>

#define read(v, s) fread(v, 1, s, file)

namespace audio {
	CSSWave::CSSWave(FILE* file, ISoundDevice* device) : CSoundSource(device), length_ms(-1) {
		soundBuffer = device->getFreeBufferID();
		if(!alIsBuffer(soundBuffer))
			throw SLoadError("No free buffers");

		char dwordTxt[5]; dwordTxt[4] = '\0';
		unsigned int dwordData;

		//Check for 'RIFF' identifier
		read(dwordTxt, 4);
		if(strcmp(dwordTxt, "RIFF") != 0)
			throw NotThisType();

		//Skip over ChunkSize
		fseek(file, 4, SEEK_CUR);

		//Check for the 'WAVE' identifier
		read(dwordTxt, 4);
		if(strcmp(dwordTxt, "WAVE") != 0)
			throw SLoadError("Can only load WAVE formats");

		//Check for the 'fmt ' identifier
		read(dwordTxt, 4);
		if(strcmp(dwordTxt, "fmt ") != 0)
			throw SLoadError("Can only load WAVE formats");

		unsigned int chunkSize;
		read(&chunkSize, 4);

		unsigned short format;
		read(&format, 2); //1 for PCM, 0xFFFE for extensible
		fseek(file, -2, SEEK_CUR);

		if(format != 1 && format != 0xFFFE)
			throw SLoadError("Can only load WAVE files with PCM encoded data");

		struct {
			unsigned short format;
			unsigned short numChannels;
			unsigned int sampleRate;
			unsigned int byteRate;
			unsigned short blockAlign;
			unsigned short bitsPerSample;
			unsigned short extensionSize;
		} PCMData;

		if(format == 1) {
			read(&PCMData, 16);
			PCMData.extensionSize = 0;
			if(chunkSize > 16)
				fseek(file, (long)(chunkSize - 16), SEEK_CUR);
		}
		else {
			read(&PCMData, 18);

			if(PCMData.extensionSize != 22)
				throw SLoadError("Can only load WAVE files with PCM encoded data");

			//Skip over valid bits/sample and speaker mask sections
			fseek(file, 6, SEEK_CUR);

			//Read true format and skip remaining data
			read(&format, 2);
			fseek(file, 14, SEEK_CUR);
		}

		if(format != 1)
			throw SLoadError("Can only load uncompressed PCM-formatted WAVE files", true);
		if(PCMData.numChannels > 2)
			throw SLoadError("Can only load 1 or 2 channel WAVE files", true);
		if(PCMData.bitsPerSample != 8 && PCMData.bitsPerSample != 16)
			throw SLoadError("Can only load 8 or 16 bit sampled WAVE files", true);

		read(dwordTxt, 4);

		if(strcmp(dwordTxt, "fact") == 0) {
			//Skip over the 'fact' section, if it exists
			read(&dwordData, 4);
			fseek(file, (long)dwordData, SEEK_CUR);
			read(dwordTxt, 4);
		}

		if(strcmp(dwordTxt, "data") != 0)
			throw SLoadError("WAVE file missing data portion", true);

		read(&dwordData, 4);
		if(dwordData > 16000000)
			throw SLoadError("WAVE files greater than 16MB not supported", true);

		unsigned char* data = new unsigned char[dwordData];
		if(read(data, dwordData) != dwordData) {
			delete[] data;
			throw SLoadError("File did not contain sufficient samples", true);
		}

		length_ms = int(dwordData / (PCMData.numChannels * (PCMData.bitsPerSample/8) * PCMData.sampleRate));

		alBufferData(soundBuffer,
			PCMData.numChannels == 2 ? ( PCMData.bitsPerSample == 8 ? AL_FORMAT_STEREO8 : AL_FORMAT_STEREO16 ) : (PCMData.bitsPerSample == 8 ? AL_FORMAT_MONO8 : AL_FORMAT_MONO16),
			data, (ALsizei)dwordData, (ALsizei)PCMData.sampleRate);

		delete[] data;
	}
	
	int CSSWave::getLength_ms() const {
		return length_ms;
	}
	
	bool CSSWave::isStreaming() const {
		return false;
	}

	bufferID CSSWave::getBuffer() const {
		return soundBuffer;
	}

	bufferID CSSWave::getStreamBuffer(long& point) const {
		return invalidBuffer;
	}

	CSSWave::~CSSWave() {
	}

	CSoundSource* load_wav(FILE* file, ISoundDevice* device) {
		return new CSSWave(file, device);
	}
};

