#ifdef _MSC_VER
#include <intrin.h>
#define PREFETCH(x) _mm_prefetch(x, _MM_HINT_T0)
#endif
#ifdef __GNUC__
#define PREFETCH(x) __builtin_prefetch(x, 0, 3)
#endif
