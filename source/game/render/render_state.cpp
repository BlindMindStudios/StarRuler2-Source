#include "render_state.h"
#include "memory/AllocOnlyPool.h"
#include "threads.h"
#include <string.h>

namespace render {

memory::AllocOnlyPool<RenderState,threads::Mutex> renderStatePool(256);

RenderState::RenderState() : culling(FC_Back),
	depthTest(DT_Less), depthWrite(true), lighting(true),
	normalizeNormals(false), baseMat(MAT_Solid), drawMode(DM_Fill),
	wrapHorizontal(TW_Repeat), wrapVertical(TW_Repeat),
	filterMin(TF_Linear), filterMag(TF_Linear),
	mipmap(true), cachePixels(false),
	diffuse(1,1,1,1), specular(1,1,1,1), shininess(3.f), textures(), shader(0), constant(true)
{
	memset(textures, 0, sizeof(textures));
}

void* RenderState::operator new(size_t size) {
	return renderStatePool.alloc();
}

void RenderState::operator delete(void* p) {
	renderStatePool.dealloc((RenderState*)p);
}

};
