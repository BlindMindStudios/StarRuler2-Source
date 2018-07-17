#include "gl_framebuffer.h"
#include "main/logging.h"
#include "main/references.h"

namespace render {

class DummyTexture : public Texture {
	GLuint glName;
public:
	DummyTexture(GLuint name) : glName(name) {
		type = TT_2D;
		hasMipMaps = false;
		loaded = true;
	}

	virtual bool isPixelActive(vec2i px) const { return false; }

	virtual void loadStart(Image& image, bool mipmap = true, bool cachePixels = false, unsigned lod = 0) {}
	virtual void loadPartial(Image& image, const recti& pixels, bool cachePixels = false, unsigned lod = 0) {}
	virtual void loadFinish(bool mipmap, unsigned lod = 0) {}

	virtual void load(Image& image, bool mipmap = true, bool cachePixels = false) {}
	virtual void save(Image& image) const {}
	virtual void bind() { glBindTexture(GL_TEXTURE_2D, glName); }
	virtual unsigned getID() const { return glName; }

	virtual unsigned getTextureBytes() const { return 0; }
};

glFrameBuffer::glFrameBuffer(const vec2i& Size) {
	devices.render->reportErrors();

	type = TT_2D;
	loaded = true;

	size = Size;
	hasMipMaps = false;
	glGenFramebuffers(1, &buffer);
	glBindFramebuffer(GL_FRAMEBUFFER, buffer);
	prevRenderState.filterMin = TF_Nearest;
	prevRenderState.filterMag = TF_Nearest;

	textures = new GLuint[2];
	glGenTextures(2, textures);

	glBindTexture(GL_TEXTURE_2D, textures[0]);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, Size.width, Size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glBindTexture(GL_TEXTURE_2D, 0);

	glBindTexture(GL_TEXTURE_2D, textures[1]);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, Size.width, Size.height, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, 0);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);
	glBindTexture(GL_TEXTURE_2D, 0);

	devices.render->reportErrors("setting framebuffer parameters");

	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[0], 0);

	devices.render->reportErrors("creating framebuffer color attachment");

	renderBuffers = new GLuint[1];
	//glGenRenderbuffers(1, renderBuffers);
	//glBindRenderbuffer(GL_RENDERBUFFER, renderBuffers[0]);
	//glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, Size.width, Size.height);
	//glBindRenderbuffer(GL_RENDERBUFFER, 0);

	//glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, renderBuffers[0]);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, textures[1], 0);

	depthTexture = new DummyTexture(textures[1]);

	devices.render->reportErrors("creating framebuffer depth attachment");

	auto state = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	if(state != GL_FRAMEBUFFER_COMPLETE)
		error("Incomplete framebuffer: %d", state);

	glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

glFrameBuffer::~glFrameBuffer() {
	glDeleteFramebuffers(1, &buffer);
	glDeleteTextures(2, textures); delete[] textures;
	//glDeleteRenderbuffers(1, renderBuffers);
	delete[] renderBuffers;
	delete depthTexture;
}

void glFrameBuffer::bind() {
	glBindTexture(GL_TEXTURE_2D, textures[0]);
}

unsigned glFrameBuffer::getID() const {
	return textures[0];
}

void glFrameBuffer::setAsTarget() {
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, buffer);
	glViewport(0,0,size.width, size.height);
}

void glFrameBuffer::save(Image& image) const {
	image.resize(size.width, size.height, FMT_RGB);
	glBindTexture(GL_TEXTURE_2D, textures[0]);
	glGetTexImage(GL_TEXTURE_2D, 0, GL_RGB, GL_UNSIGNED_BYTE, image.rgb);
}

void glFrameBuffer::load(Image& img, bool mipmap, bool cachePixels) {
	throw "Cannot load framebuffer from image.";
}

void glFrameBuffer::loadStart(Image& image, bool mipmap, bool cachePixels, unsigned lod) {
	throw "Cannot load framebuffer from image.";
}

void glFrameBuffer::loadPartial(Image& image, const recti& pixels, bool cachePixels, unsigned lod) {
	throw "Cannot load framebuffer from image.";
}

void glFrameBuffer::loadFinish(bool mipmap, unsigned lod) {
	throw "Cannot load framebuffer from image.";
}

bool glFrameBuffer::isPixelActive(vec2i px) const {
	throw "Cannot get framebuffer pixels.";
}

unsigned glFrameBuffer::getTextureBytes() const {
	//4 bytes for RGBA, 3 bytes for 24 bit z buffer
	return size.width * size.height * 7;
}

};
