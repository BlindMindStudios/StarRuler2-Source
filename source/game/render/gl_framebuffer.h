#include "texture.h"
#include "compat/gl.h"

namespace render {

	class glFrameBuffer : public Texture {
		GLuint buffer;
		GLuint* textures;
		GLuint* renderBuffers;
	public:
		glFrameBuffer(const vec2i& Size);
		~glFrameBuffer();

		Texture* depthTexture;

		bool isPixelActive(vec2i px) const;
		void bind();
		unsigned getID() const;
		void load(Image& img, bool mipmap = true, bool cachePixels = false);
		void loadStart(Image& image, bool mipmap = true, bool cachePixels = false, unsigned lod = 0);
		void loadPartial(Image& image, const recti& pixels, bool cachePixels = false, unsigned lod = 0);
		void loadFinish(bool mipmap, unsigned lod = 0);
		void save(Image& img) const;
		unsigned getTextureBytes() const;
		void setAsTarget();
	};

};
