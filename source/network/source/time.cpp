#include <network/time.h>

#ifdef _MSC_VER
#include <Windows.h>
#endif

namespace net {

#ifdef _MSC_VER
void time_now(time& tm) {
	tm = timeGetTime();
}
#elif defined(__GNUC__)
void time_now(time& tm) {
	timeval tv;
	gettimeofday(&tv, 0);

	uint64_t value = 0;
	value += tv.tv_sec * 1000;
	value += tv.tv_usec / 1000;
	tm = (time)value;
}
#endif

uint64_t time_diff(time& from, time& to) {
	return to - from;
}

void time_add(time& base, int64_t add_ms) {
	base += add_ms;
}
};
