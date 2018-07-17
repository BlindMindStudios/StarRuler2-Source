#if defined(_MSC_VER) && defined(_M_AMD64)
#include <emmintrin.h>
#define HAVE_SSE
#define m128d_f64(reg, num) reg._m128d_f64[num]
#endif

#if defined(__GNUG__) && defined(__amd64__)
#include <emmintrin.h>
#define HAVE_SSE
#define m128d_f64(reg, num) reg[num]
#endif
