#include "CSoundSource.h"
#include "ISoundDevice.h"

#include "al.h"
#include "ogg.h"

#include "threads.h"

#include "SLoadError.h"
#include "SAutoDrop.h"

#include <map>
#include <vector>
#include <stdio.h>
#include <string.h>

//==========
//Much of this loader is taken from "PlayOggVorbis.cpp" in the OpenAL SDK
//==========

#include <vorbisfile.h>

#ifndef LIN_MODE
#include "windows.h"
HINSTANCE g_hVorbisFileDLL = NULL;
#else
#include <time.h>
void Sleep(unsigned int milliseconds) {
	struct timespec wait;
	wait.tv_sec = (milliseconds / 1000);
	wait.tv_nsec = (milliseconds % 1000) * 1000 * 1000;

	nanosleep(&wait, 0);
}
#endif


typedef int (*LPOVCLEAR)(OggVorbis_File *vf);
typedef long (*LPOVREAD)(OggVorbis_File *vf,char *buffer,int length,int bigendianp,int word,int sgned,int *bitstream);
typedef ogg_int64_t (*LPOVPCMTOTAL)(OggVorbis_File *vf,int i);
typedef vorbis_info * (*LPOVINFO)(OggVorbis_File *vf,int link);
typedef vorbis_comment * (*LPOVCOMMENT)(OggVorbis_File *vf,int link);
typedef int (*LPOVOPENCALLBACKS)(void *datasource, OggVorbis_File *vf,char *initial, long ibytes, ov_callbacks callbacks);
typedef long (*LPOVSEEKABLE)(OggVorbis_File *vf);
typedef int (*LPOVPCMSEEK)(OggVorbis_File *vf,ogg_int64_t pos);
typedef ogg_int64_t (*LPOVPCMTELL)(OggVorbis_File *vf);

LPOVCLEAR			fn_ov_clear = NULL;
LPOVREAD			fn_ov_read = NULL;
LPOVINFO			fn_ov_info = NULL;
LPOVCOMMENT			fn_ov_comment = NULL;
LPOVOPENCALLBACKS	fn_ov_open_callbacks = NULL;
LPOVPCMTOTAL		fn_ov_pcm_total = NULL;
LPOVSEEKABLE		fn_ov_seekable = NULL;
LPOVPCMSEEK			fn_ov_pcm_seek = NULL;
LPOVPCMSEEK			fn_ov_pcm_seek_lap = NULL;
LPOVPCMTELL			fn_ov_pcm_tell = NULL;


volatile int g_bVorbisInit = 0;
threads::Mutex vorbisInitLock;

void InitVorbisFile()
{
	if(g_bVorbisInit != 0)
		return;

	threads::Lock lock(vorbisInitLock);
	if(g_bVorbisInit != 0)
		return;

	#ifndef LIN_MODE
	// Try and load Vorbis DLLs (VorbisFile.dll will load ogg.dll and vorbis.dll)
	g_hVorbisFileDLL = LoadLibrary("libvorbisfile.dll");
	if (g_hVorbisFileDLL)
	{
		fn_ov_clear = (LPOVCLEAR)GetProcAddress(g_hVorbisFileDLL, "ov_clear");
		fn_ov_read = (LPOVREAD)GetProcAddress(g_hVorbisFileDLL, "ov_read");
		fn_ov_info = (LPOVINFO)GetProcAddress(g_hVorbisFileDLL, "ov_info");
		fn_ov_comment = (LPOVCOMMENT)GetProcAddress(g_hVorbisFileDLL, "ov_comment");
		fn_ov_open_callbacks = (LPOVOPENCALLBACKS)GetProcAddress(g_hVorbisFileDLL, "ov_open_callbacks");

		fn_ov_pcm_total = (LPOVPCMTOTAL)GetProcAddress(g_hVorbisFileDLL, "ov_pcm_total");
		fn_ov_seekable = (LPOVSEEKABLE)GetProcAddress(g_hVorbisFileDLL, "ov_seekable");
		fn_ov_pcm_seek = (LPOVPCMSEEK)GetProcAddress(g_hVorbisFileDLL, "ov_pcm_seek");
		fn_ov_pcm_seek_lap = (LPOVPCMSEEK)GetProcAddress(g_hVorbisFileDLL, "ov_pcm_seek_lap");
		fn_ov_pcm_tell = (LPOVPCMTELL)GetProcAddress(g_hVorbisFileDLL, "ov_pcm_tell");

		if (fn_ov_clear && fn_ov_read && fn_ov_pcm_total && fn_ov_info &&
			fn_ov_comment && fn_ov_open_callbacks)
		{
			g_bVorbisInit = 1;
		}
		else
		{
			g_bVorbisInit = -1;
		}
	}
	#else
		fn_ov_clear = &ov_clear;
		fn_ov_read = &ov_read;
		fn_ov_info = &ov_info;
		fn_ov_comment = &ov_comment;
		fn_ov_open_callbacks = &ov_open_callbacks;
		
		fn_ov_pcm_total = &ov_pcm_total;
		fn_ov_seekable = &ov_seekable;
		fn_ov_pcm_seek = &ov_pcm_seek;
		fn_ov_pcm_seek_lap = &ov_pcm_seek_lap;
		fn_ov_pcm_tell = &ov_pcm_tell;

		g_bVorbisInit = 1;
	#endif
}

void CloseVorbisFile()
{
#ifndef LIN_MODE
	if (g_hVorbisFileDLL)
	{
		FreeLibrary(g_hVorbisFileDLL);
		g_hVorbisFileDLL = NULL;
	}
#endif
	g_bVorbisInit = 0;
}

size_t fn_ov_read_func(void *ptr, size_t size, size_t nmemb, void *datasource) {
	FILE* file = (FILE*)datasource;
	return fread(ptr, size, nmemb, file);
}

int fn_ov_seek_func(void *datasource, ogg_int64_t offset, int whence) {
	FILE* file = (FILE*)datasource;
	return fseek(file, (long)offset, whence);
}

int fn_ov_close_func(void *datasource) {
	FILE* file = (FILE*)datasource;
	return fclose(file);
}

long fn_ov_tell_func(void *datasource) {
	FILE* file = (FILE*)datasource;
	return ftell(file);
}

void Swap(short &s1, short &s2)
{
	short sTemp = s1;
	s1 = s2;
	s2 = sTemp;
}

unsigned long DecodeOggVorbis(OggVorbis_File *psOggVorbisFile, char *pDecodeBuffer, unsigned long ulBufferSize, unsigned long ulChannels)
{
	int current_section;
	long lDecodeSize;
	unsigned long ulSamples;
	short *pSamples;

	unsigned long ulBytesDone = 0;
	while(true) {
		lDecodeSize = fn_ov_read(psOggVorbisFile, pDecodeBuffer + ulBytesDone, ulBufferSize - ulBytesDone, 0, 2, 1, &current_section);
		if(lDecodeSize > 0) {
			ulBytesDone += lDecodeSize;

			if(ulBytesDone >= ulBufferSize)
				break;
		}
		else {
			break;
		}
	}

	// Mono, Stereo and 4-Channel files decode into the same channel order as WAVEFORMATEXTENSIBLE,
	// however 6-Channels files need to be re-ordered
	if(ulChannels == 6) {		
		pSamples = (short*)pDecodeBuffer;
		for(ulSamples = 0; ulSamples < (ulBufferSize>>1); ulSamples+=6) {
			// WAVEFORMATEXTENSIBLE Order : FL, FR, FC, LFE, RL, RR
			// OggVorbis Order            : FL, FC, FR,  RL, RR, LFE
			Swap(pSamples[ulSamples+1], pSamples[ulSamples+2]);
			Swap(pSamples[ulSamples+3], pSamples[ulSamples+5]);
			Swap(pSamples[ulSamples+4], pSamples[ulSamples+5]);
		}
	}

	return ulBytesDone;
}

namespace audio {

struct AutoClearOVF {
public:
	OggVorbis_File* file;

	AutoClearOVF(OggVorbis_File* clearFile) : file(clearFile) {}
	~AutoClearOVF() { if(file) fn_ov_clear(file); }
};

struct AutoDelArray {
	char* pData;
	AutoDelArray(char* data) : pData(data) {}
	~AutoDelArray() { delete[] pData; }
};

struct SubBuffer {
	char* pData; unsigned int size;
	void free() { delete[] pData; pData = 0; size = 0; }
	SubBuffer(char* data, unsigned int byteSize) : pData(data), size(byteSize) {}
};
	
class CSSOgg : public CSoundSource {
public:
	FILE* cfile;
	mutable OggVorbis_File ogg;
	vorbis_info	*psVorbisInfo;
	
	unsigned long ulFrequency, ulFormat, ulChannels, ulBufferSize;

	bool seekable;
	int length_ms;
	long startPoint;

	bufferID soundBuffer;

	bool loadBuffer(bufferID outBuffer, unsigned maxBytes, bool streaming, unsigned* timestamp) const {
		const int subBufferSize = 0x10000;
		unsigned totalDecodedBytes = 0;

		char* pDecodeBuffer = new char[subBufferSize];
		AutoDelArray clearDecodeBuff(pDecodeBuffer);
		
		std::vector<SubBuffer> subBuffers;

		while(totalDecodedBytes < maxBytes) {
			unsigned long decoded = DecodeOggVorbis(&ogg, pDecodeBuffer, subBufferSize, ulChannels);
			if(decoded == 0)
				break;
			totalDecodedBytes += decoded;
			if(timestamp)
				*timestamp += (decoded * 1000) / (ulFrequency * ulChannels);

			if(totalDecodedBytes < maxBytes) {
				if(char* chunkCopy = new char[decoded]) {
					memcpy(chunkCopy, pDecodeBuffer, decoded);
					subBuffers.push_back( SubBuffer(chunkCopy, decoded) );
				}
				else {
					//When out of memory, just use the existing decode buffer and give up
					subBuffers.push_back( SubBuffer(pDecodeBuffer, decoded) );
					clearDecodeBuff.pData = 0;
					break;
				}
			}
			else {
				//If we are done loading chunks, use the pre-existing buffer instead of copying
				subBuffers.push_back( SubBuffer(pDecodeBuffer, decoded) );
				clearDecodeBuff.pData = 0;
				break;
			}
			
			Sleep(0);
		}

		if(subBuffers.empty())
			return false;

		alGetError();

		ALsizei bufferSize = (ALsizei)totalDecodedBytes;
		bufferSize -= bufferSize % (psVorbisInfo->channels * 2);

		if(subBuffers.size() != 1) {
			char* buffer = new char[totalDecodedBytes];
			if(buffer == 0) { //Could not allocate memory
				for(unsigned int i = 0, chunks = subBuffers.size(); i < chunks; ++i) {
					SubBuffer& buff = subBuffers[i];
					buff.free();
				}
				subBuffers.clear();
				return false;
			}
			Sleep(0);

			//Merge all sub-buffers
			char* curPos = buffer;
			for(unsigned int i = 0, chunks = subBuffers.size(); i < chunks; ++i) {
				SubBuffer& buff = subBuffers[i];
				memcpy(curPos, buff.pData, buff.size);
				curPos += buff.size;
				buff.free();
				Sleep(0);
			}
			subBuffers.clear();

			alBufferData(outBuffer, ulFormat, buffer, bufferSize, ulFrequency);
			Sleep(0);

			delete[] buffer;
		}
		else {
			alBufferData(outBuffer, ulFormat, subBuffers.front().pData, bufferSize, ulFrequency);
			subBuffers.front().free();
		}

		return true;
	}
	
	CSSOgg(FILE* file, ISoundDevice* device, bool stream) : CSoundSource(device), cfile(0), soundBuffer(invalidBuffer) {
		InitVorbisFile();
		if(g_bVorbisInit != 1)
			throw SLoadError("Vorbis dlls failed to load", true);
		
		ulFrequency = 0;
		ulFormat = 0;
		ulChannels = 0;

		ov_callbacks	sCallbacks;
	
		sCallbacks.close_func = fn_ov_close_func;
		sCallbacks.seek_func = fn_ov_seek_func;
		sCallbacks.tell_func = fn_ov_tell_func;
		sCallbacks.read_func = fn_ov_read_func;

		int result = fn_ov_open_callbacks((void*)file, &ogg, NULL, 0, sCallbacks);
		if(result != 0) {
			if(result == OV_ENOTVORBIS)
				throw NotThisType();
			else
				throw SLoadError("Unable to open ogg stream reader", true);
		}

		AutoClearOVF fileClear(&ogg);

		psVorbisInfo = fn_ov_info(&ogg, -1);
		if(psVorbisInfo == 0)
			throw SLoadError("Unable to read vorbis information", true);

		seekable = fn_ov_seekable(&ogg) != 0;

		ulFrequency = psVorbisInfo->rate;
		ulChannels = psVorbisInfo->channels;

		if (psVorbisInfo->channels == 1)
		{
			ulFormat = AL_FORMAT_MONO16;
			// Set BufferSize to 250ms (Frequency * 2 (16bit) divided by 4 (quarter of a second))
			ulBufferSize = ulFrequency >> 1;
			// IMPORTANT : The Buffer Size must be an exact multiple of the BlockAlignment ...
			ulBufferSize -= (ulBufferSize % 2);
		}
		else if (psVorbisInfo->channels == 2)
		{
			ulFormat = AL_FORMAT_STEREO16;
			// Set BufferSize to 250ms (Frequency * 4 (16bit stereo) divided by 4 (quarter of a second))
			ulBufferSize = ulFrequency;
			// IMPORTANT : The Buffer Size must be an exact multiple of the BlockAlignment ...
			ulBufferSize -= (ulBufferSize % 4);
		}
		else if (psVorbisInfo->channels == 4)
		{
			ulFormat = alGetEnumValue("AL_FORMAT_QUAD16");
			// Set BufferSize to 250ms (Frequency * 8 (16bit 4-channel) divided by 4 (quarter of a second))
			ulBufferSize = ulFrequency * 2;
			// IMPORTANT : The Buffer Size must be an exact multiple of the BlockAlignment ...
			ulBufferSize -= (ulBufferSize % 8);
		}
		else if (psVorbisInfo->channels == 6)
		{
			ulFormat = alGetEnumValue("AL_FORMAT_51CHN16");
			// Set BufferSize to 250ms (Frequency * 12 (16bit 6-channel) divided by 4 (quarter of a second))
			ulBufferSize = ulFrequency * 3;
			// IMPORTANT : The Buffer Size must be an exact multiple of the BlockAlignment ...
			ulBufferSize -= (ulBufferSize % 12);
		}

		if(ulFormat == 0)
			throw SLoadError("Invalid vorbis format");

		if(seekable) {
			ogg_int64_t samples = fn_ov_pcm_total(&ogg, -1);
			length_ms = int((samples * 1000) / ulFrequency);
		}
		else {
			length_ms = -1;
		}

		if(!stream) {
			soundBuffer = device->getFreeBufferID();
			loadBuffer(soundBuffer,16000000,false,0);

			switch(alGetError()) {
				case AL_OUT_OF_MEMORY:
					throw SLoadError("Buffer too large");
				case AL_INVALID_VALUE:
					throw SLoadError("Invalid size or buffer");
				case AL_INVALID_ENUM:
					throw SLoadError("Invalid format");
				case AL_INVALID_NAME:
					throw SLoadError("Buffer was invalid");
				default:
					throw SLoadError("Unspecified error");
				case AL_NO_ERROR:
					break;
			}
		}
		else {
			fileClear.file = 0;
			cfile = file;
			startPoint = (long)fn_ov_pcm_tell(&ogg);
		}
	}

	int getLength_ms() const {
		return length_ms;
	}
	
	bool isStreaming() const {
		//We only keep a file reference if we are a streaming sound
		return cfile != 0;
	}

	bufferID getBuffer() const {
		return soundBuffer;
	}
	
	bufferID getStreamBuffer(long& point) const {
		audio::bufferID buffer = device->getFreeBufferID();
		if(!alIsBuffer(buffer))
			return invalidBuffer;

		if(point == 0)
			point = startPoint;

		//Only advance the stream if there's a discontinuity, otherwise we'll clip the sound
		if(fn_ov_pcm_tell(&ogg) != point) {
			if(fn_ov_pcm_seek_lap(&ogg, point) != 0) {
				device->freeBuffer(buffer);
				return invalidBuffer;
			}
		}

		if(loadBuffer(buffer, 0x10000, true, 0)) {
			point = (long)fn_ov_pcm_tell(&ogg);
			return buffer;
		}
		else {
			device->freeBuffer(buffer);
			point = -1;
			return invalidBuffer;
		}
	}

	~CSSOgg() {
		if(cfile) {
			fn_ov_clear(&ogg);
		}
	}

};

CSoundSource* load_ogg(FILE* file, ISoundDevice* device) {
	return new CSSOgg(file, device, false);
}

CSoundSource* load_ogg_stream(FILE* file, ISoundDevice* device) {
	return new CSSOgg(file, device, true);
}

};
