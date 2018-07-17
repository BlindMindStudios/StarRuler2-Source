#pragma once

#ifndef LIN_MODE
#ifdef SND_EXPORT
#define _export __declspec(dllexport)
#else
#define _export __declspec(dllimport)
#endif
#else
#define _export
#endif

namespace audio {

	class IAudioReference {
		mutable int references;

	public:
		virtual ~IAudioReference();
		IAudioReference();

		_export void grab() const;
		_export void drop() const;
	};

};