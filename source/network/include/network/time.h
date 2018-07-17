#pragma once
#include <stdint.h>

#ifdef __GNUC__
#include <sys/time.h>
#endif

namespace net {

#ifdef __GNUC__
typedef unsigned int time;
#else
typedef unsigned int time;
#endif

void time_now(time& time);
uint64_t time_diff(time& from, time& to);
void time_add(time& base, int64_t add_ms);

};
