#pragma once
#include "vec3.h"
#include "vec2.h"

// Generates random numbers with a thread-local generator

void initRandomizer();
void freeRandomizer();

void seed(unsigned long seed);

//Returns a high-quality random integer (slow)
unsigned sysRandomi();

//Random double in (0.0, 1.0)
double randomd();
//Random double in (min, max)
double randomd(double min, double max);
//Pseudo-normal distribution within min,max
double normald(double min, double max, int steps = 4);

//Random float in (0.0, 1.0)
float randomf();
//Random float in (min, max)
float randomf(float min, float max);

//Random int in [0, INT_MAX]
unsigned randomi();
//Random int in [min, max]
int randomi(int min, int max);

//Random on sphere surface
vec3d random3d(double radius = 1.0);
//Random on a donut sphere
vec3d random3d(double minRadius, double maxRadius);

//Random on circle circumference
vec2d random2d(double radius = 1.0);
//Random on a donut circle
vec2d random2d(double minRadius, double maxRadius);


class RandomEngine {
public:
	virtual void seed(unsigned initial) = 0;
	virtual unsigned randomi() = 0;
	virtual unsigned randomi(unsigned min, unsigned max) = 0;
	virtual double randomd() = 0;
	virtual double randomd(double min, double max) = 0;

	static RandomEngine* makeMersenne(unsigned seed);
};