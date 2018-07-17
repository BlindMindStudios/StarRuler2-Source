#include "ISoundSource.h"
#include "ISoundDevice.h"


namespace audio {

	ISoundSource::ISoundSource(ISoundDevice* Device) : device(Device) {
		device->grab();
	}

	ISoundSource::~ISoundSource() {
		device->drop();
	}

};