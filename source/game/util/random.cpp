#include <random>
#include "threads.h"
#include <time.h>
#include "constants.h"
#include "vec3.h"
#include "vec2.h"
#include "main/references.h"
#include "os/driver.h"
#include "random.h"
#if defined(_MSC_VER)
#include <intrin.h>
#define GET_MSB(var, x) do{ unsigned long _index_; _BitScanReverse(&_index_, x); var = _index_ + 1; } while(false)
#elif defined(__GNUC__)
#define GET_MSB(var, x) do { var = (32 - __builtin_clz(x)); } while(false)
#else
unsigned _get_msb(unsigned v) {
	unsigned index = 0;
	while((1 << index) <= v)
		++index;
	return index;
}
#define GET_MSB(var, x) do { var = _get_msb(x); } while(false)
#endif

Threaded(std::mt19937*) engine;

void seed(unsigned long seed);

void initRandomizer() {
    engine = new std::mt19937();
	seed((unsigned long)time(0) ^ (unsigned long)threads::getThreadID());
}

void freeRandomizer() {
	delete engine;
}

void seed(unsigned long seed) {
    engine->seed(seed);
}

unsigned sysRandomi() {
	unsigned ret = 0;
	if(!devices.driver->systemRandom((unsigned char*)&ret, 4)) {
		if(engine)
			ret = (unsigned)randomi();
		else {
			initRandomizer();
			ret = (unsigned)randomi();
			freeRandomizer();
		}
	}
	return ret;
}

double randomd() {
	//Choose random numbers until we don't get max
	unsigned m = engine->max();
	unsigned r;
	do {
		r = (*engine)();
	} while(r == m);
    return (double)r / (double)m;
}

double randomd(double min, double max) {
    return randomd() * (max - min) + min;
}

double normald(double min, double max, int steps) {
	double sum = 0;

	for(int i = 0; i < steps; ++i)
		sum += randomd();

	return min + (max-min)*sum/(double)steps;
}

float randomf() {
    return (float)randomd();
}

float randomf(float min, float max) {
    return (float)(randomd() * (double)(max - min)) + min;
}

unsigned randomi() {
	return (*engine)();
}

int randomi(int min, int max) {
	unsigned range = (unsigned)max - (unsigned)min;
	if(range == 0)
		return min;

	unsigned msb;
	GET_MSB(msb, range);

	unsigned mask = 0xffffffff >> (32 - msb);

	//Choose uniformly distributed values until one falls into our range
	//Worst case scenario is the possible values is split in half (+1), so it will still resolve quickly
	unsigned r;
	do {
		r = (unsigned)((*engine)());
	} while((r & mask) > range);

    return min + (r & mask);
}

vec3d random3d(double radius) {
	double theta = randomd(0, twopi);

	double u = randomd(-1.0, 1.0);
	double s = sqrt(1.0-(u*u));

	vec3d out;
	out.x = s * cos(theta) * radius;
	out.y = s * sin(theta) * radius;
	out.z = u * radius;

	return out;
}

vec3d random3d(double minRadius, double maxRadius) {
	return random3d(minRadius + (maxRadius - minRadius) * sqrt(randomd()));
}

vec2d random2d(double radius) {
	double theta = randomd(0, twopi);
	return vec2d(radius * cos(theta), radius * sin(theta));
}

vec2d random2d(double minRadius, double maxRadius) {
	return random2d(minRadius + (maxRadius - minRadius) * sqrt(randomd()));
}

class MersenneEngine : public RandomEngine {
	std::mt19937 rnd;
public:
	void seed(unsigned initial) {
		rnd.seed((unsigned long)initial);
	}

	unsigned randomi() {
		return rnd();
	}

	unsigned randomi(unsigned min, unsigned max) {
		unsigned range = (unsigned)max - (unsigned)min;
		if(range == 0)
			return min;

		unsigned msb;
		GET_MSB(msb, range);

		unsigned mask = 0xffffffff >> (32 - msb);

		//Choose uniformly distributed values until one falls into our range
		//Worst case scenario is the possible values is split in half (+1), so it will still resolve quickly
		unsigned r;
		do {
			r = (unsigned)(rnd());
		} while((r & mask) > range);

		return min + (r & mask);
	}

	double randomd() {
		unsigned m = rnd.max();
		unsigned r;
		do {
			r = rnd();
		} while(r == m);
		return (double)r / (double)m;
	}

	double randomd(double min, double max) {
		return (randomd() * (max - min)) + min;
	}
};

RandomEngine* RandomEngine::makeMersenne(unsigned seed) {
	auto* engine = new MersenneEngine();
	engine->seed(seed);
	return engine;
}