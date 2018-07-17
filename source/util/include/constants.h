#pragma once
#define _USE_MATH_DEFINES
#include <math.h>

#ifdef M_PIl
const double e = M_El;
const double pi = M_PIl;
const double twopi = M_PIl * 2;
#else
const double e = M_E;
const double pi = M_PI;
const double twopi = M_PI * 2;
#endif
