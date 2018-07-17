#include "main/references.h"

references devices;

references::references() : physics(nullptr), nodePhysics(nullptr), cloud(nullptr) {
}

namespace audio {
	bool disableSFX = false;
};
