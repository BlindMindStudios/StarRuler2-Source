#pragma once

#include "IAudioReference.h"

#include "sound_vector.h"

namespace audio {

	class ISoundSource;

	class ISound : public IAudioReference {
	public:
		virtual ~ISound();
		ISound();

		//Returns true if the sound is stopped, and cannot be played again.
		virtual bool isStopped() const = 0;

		//Returns true if the sound is playing
		virtual bool isPlaying() const = 0;

		//For streaming sources, buffers additional sound data (if necessary)
		virtual void streamData() = 0;

		//Pauses the sound
		virtual void pause() = 0;

		//Resumes the sound
		virtual void resume() = 0;

		//Changes the sound's current time stamp
		virtual void seek(int timeMS) = 0;

		virtual void setLooped(bool loop) = 0;

		virtual bool isLooped() const = 0;

		//Ends the sound. The sound may not be resumed from this state.
		virtual void stop() = 0;

		//Sets the sound's 3D Position. For 2D Sounds, this is in camera space.
		virtual void setPosition(float x, float y, float z) = 0;

		inline void setPosition(const snd_vec& pos) {
			setPosition(pos.x, pos.y, pos.z);
		}

		//Sets the sound's 3D Velocity. For 2D Sounds, this is in camera space.
		virtual void setVelocity(float x, float y, float z) = 0;

		inline void setVelocity(const snd_vec& vel) {
			setVelocity(vel.x, vel.y, vel.z);
		}

		virtual void setVolume(float volume) = 0;

		//Pitch is a factor from 0.5 to 2.0, defaulting to 1.0
		virtual void setPitch(float pitch) = 0;

		virtual void setRolloff(float factor) = 0;

		//Applies a low pass filter with a strength from 0 to 1 (none to max)
		virtual void setLowPass(float strength) = 0;

		//Returns the sound's position in the file
		virtual int getPlayPosition() = 0;

		virtual int getPlayLength() = 0;

		inline void setIsPaused(bool paused) {
			if(paused)
				pause();
			else
				resume();
		}

		virtual void setMinDistance(float minDist) = 0;
		virtual void setMaxDistance(float maxDist) = 0;

		virtual void setPlayPosition(int timeMs) = 0;

		//Returns the sound source used to create this sound.
		//This pointer should not be dropped.
		virtual const ISoundSource* getSoundSource() = 0;
	};

};