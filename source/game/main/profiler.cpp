#include "profiler.h"

#include "main/references.h"
#include "main/logging.h"

namespace profiler {

	double profileStart() {
		return devices.driver->getAccurateTime();
	}

	void profileEnd(double startTime, const char* section) {
		double delta = devices.driver->getAccurateTime() - startTime;

		if(delta >= 5e-1)
			print("%s: %.1fs\n", section, delta);
		else if(delta >= 5e-4)
			print("%s: %.1fms\n", section, delta * 1e3);
		else if(delta >= 5e-7)
			print("%s: %.1fus\n", section, delta * 1e6);
		else
			print("%s: %.1fns\n", section, delta * 1e9);
	}

};