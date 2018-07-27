#include "render/font.h"
#include "render/driver.h"
#include "render/vertexBuffer.h"
#include "main/initialization.h"
#include <stdio.h>
#include "str_util.h"
#include "vec2.h"

#ifdef _MSC_VER
#include <ft2build.h>
#else
#include <freetype2/ft2build.h>
#endif

#include FT_FREETYPE_H
#include FT_SIZES_H

#include <map>
#include <algorithm>

namespace resource {
extern render::Texture* queueImage(Image* img, int priority, bool mipmap, bool cachePixels);
};

namespace render {

Font* Font::createDummyFont() {
	return new Font();
}

bool clipQuad(rectf pos, rectf source, const rectf* clip, vec2f* verts, vec2f* texcoords) {
	if(clip) {
		if(!clip->overlaps(pos))
			return false;

		if(!clip->isRectInside(pos)) {
			//TODThere seem to be some oddities with the texture coordinates if a clip occurs
			rectf clipped = clip->clipAgainst(pos);
			source = source.clipProportional(pos, clipped);
			pos = clipped;
		}
	}

	verts[0] = vec2f(pos.topLeft.x, pos.topLeft.y);
	verts[1] = vec2f(pos.botRight.x, pos.topLeft.y);
	verts[3] = vec2f(pos.topLeft.x, pos.botRight.y);
	verts[2] = vec2f(pos.botRight.x, pos.botRight.y);
	
	texcoords[0] = vec2f(source.topLeft.x, source.topLeft.y);
	texcoords[1] = vec2f(source.botRight.x, source.topLeft.y);
	texcoords[3] = vec2f(source.topLeft.x, source.botRight.y);
	texcoords[2] = vec2f(source.botRight.x, source.botRight.y);

	return true;
}

class FontFT2 : public Font {
public:
	std::vector<render::RenderState*> textures;

	struct Glyph {
		unsigned short x : 16, y : 16;
		bool draw : 1;
		unsigned char page : 7;
		unsigned char w : 8, h : 8;
		char wOff : 8, hOff : 8;
		float xAdv;
		int glyph_index;
	};

	struct GlyphEntry {
		fontChar letter;
		Glyph glyph;

		bool operator<(const GlyphEntry& other) const { return letter < other.letter; }
		GlyphEntry(fontChar Letter) : letter(Letter) {}
		GlyphEntry(fontChar Letter, Glyph& Glyph) : letter(Letter), glyph(Glyph) {}
	};

	Glyph* lowChars;
	FT_Face* face;
	FT_Size size;
	std::vector<GlyphEntry> hiChars;

	double x_scale, y_scale;
	unsigned glyphHeight, baseLine, textureHeight, textureWidth;

	void draw(render::RenderDriver* driver, const char* text, int X, int Y, const Color* color, const recti* clip = 0) const {
		float x = (float)X, y = (float)Y;
		Color col = color ? *color : Color();

		float xFactor = 1.f / float(textureWidth), yFactor = 1.f / float(textureHeight);
		vec2f font_verts[4], font_tc[4];

		rectf fclip;
		if(clip)
			fclip = rectf(*clip);

		FT_Activate_Size(size);

		unsigned lastTexture = (unsigned)textures.size();
		VertexBufferTCV* buffer = 0;

		u8it it(text);
		fontChar lastC = 0;

		while(fontChar c = it++) {
			if(c == L'\n') {
				y += glyphHeight;
				x = (float)X;
				lastC = 0;
			}
			else if(c == L'\t') {
				x += 32.f - fmod(x - X, 32.f);
				lastC = L' ';
			}
			else {
				Glyph glyph;

				if(c <= 0xff)
					glyph = lowChars[c];
				else {
					auto g = std::lower_bound(hiChars.begin(), hiChars.end(), c);
					if(g != hiChars.end() && g->letter == c) {
						glyph = g->glyph;
					}
					else {
						glyph = lowChars['?'];
					}
				}

				//Don't kern anything involving digits
				if(c >= '0' && c <= '9') {
					lastC = 0;
				}
				else {
					if(lastC) {
						FT_Vector kerning;
						FT_Get_Kerning(*face, lastC, glyph.glyph_index, 0/*FT_KERNING_UNFITTED*/, &kerning);
						
						if(kerning.x != 0)
							x += ((float)kerning.x) / 64.f;
					}

					lastC = glyph.glyph_index;
				}

				if(glyph.draw) {
					rectf pos = rectf::area(vec2f(x + (float)glyph.wOff, y + (float)glyph.hOff), vec2f(glyph.w, glyph.h));
					rectf source = rectf::area(vec2f((float)glyph.x * xFactor, (float)glyph.y * yFactor),
										vec2f((float)glyph.w * xFactor, (float)glyph.h * yFactor));

					if(clipQuad(pos, source, clip ? &fclip : 0, font_verts, font_tc)) {
						if(glyph.page != lastTexture) {
							auto& mat = *textures[glyph.page];
							buffer = VertexBufferTCV::fetch(&mat);
							lastTexture = glyph.page;
						}

						auto* verts = buffer->request(1, PT_Quads);

						for(unsigned i = 0; i < 4; ++i) {
							auto& v = verts[i];
							v.uv = font_tc[i];
							v.col = col;
							v.pos.set(font_verts[i].x, font_verts[i].y, 0);
						}
					}
				}

				x += glyph.xAdv;
			}
		}
	}

	vec2i drawChar(render::RenderDriver* driver, int c, int lastC,
					int X, int Y, const Color* color, const recti* clip = 0) const {
		float x = (float)X, y = (float)Y;
		Color colors[4];
		if(color)
			colors[0] = colors[1] = colors[2] = colors[3] = *color;

		rectf fclip;
		if(clip)
			fclip = rectf(*clip);

		float xFactor = 1.f / float(textureWidth), yFactor = 1.f / float(textureHeight);
		vec2f font_verts[4], font_tc[4];

		FT_Activate_Size(size);

		Glyph glyph;

		if(c <= 0xff)
			glyph = lowChars[c];
		else {
			auto g = std::lower_bound(hiChars.begin(), hiChars.end(), c);
			if(g != hiChars.end() && g->letter == c) {
				glyph = g->glyph;
			}
			else {
				glyph = lowChars['?'];
			}
		}

		//Don't kern anything involving digits
		if(c >= '0' && c <= '9') {
			lastC = 0;
		}
		else {
			if(lastC) {
				FT_Vector kerning;
				FT_Get_Kerning(*face, lastC, glyph.glyph_index, 0, &kerning);
				
				if(kerning.x != 0)
					x += ((float)kerning.x) / 64.f;
			}

			lastC = glyph.glyph_index;
		}

		if(glyph.draw) {
			rectf pos = rectf::area(vec2f(x + glyph.wOff, y + glyph.hOff), vec2f(glyph.w, glyph.h));
			rectf source = rectf::area(vec2f((float)glyph.x * xFactor, (float)glyph.y * yFactor),
								vec2f((float)glyph.w * xFactor, (float)glyph.h * yFactor));

			if(clipQuad(pos, source, clip ? &fclip : 0, font_verts, font_tc))
				driver->drawQuad(textures[glyph.page], font_verts, font_tc, color ? colors : 0);
		}

		x += glyph.xAdv;
		return vec2i((int)x - X, (int)y - Y);
	}

	vec2i getDimension(const char* text) const {
		vec2i dim(0, glyphHeight);

		FT_Activate_Size(size);

		fontChar lastC = 0;
		u8it it(text);
		unsigned maxWidth = 0;

		while(fontChar c = it++) {
			const Glyph* glyph = 0;

			if(c == L'\n') {
				if(dim.x > (int)maxWidth)
					maxWidth = dim.x;
				dim.x = 0;
				dim.y += glyphHeight;
			}
			else if(c <= 0xff) {
				glyph = &lowChars[c];
			}
			else {
				auto g = std::lower_bound(hiChars.begin(), hiChars.end(), c);
				if(g != hiChars.end() && g->letter == c)
					glyph = &g->glyph;
				else
					glyph = &lowChars['?'];
			}

			if(glyph) {
				dim.x += (int)glyph->xAdv;

				//Don't kern anything involving digits
				if(c < '0' || c > '9') {
					if(lastC) {
						FT_Vector kerning;
						FT_Get_Kerning(*face, lastC, glyph->glyph_index, 0, &kerning);
						
						if(kerning.x != 0)
							dim.x += (unsigned)(kerning.x >> 6);
					}
				}
			}
		}

		if(dim.x < (int)maxWidth)
			dim.x = maxWidth;
		return dim;
	}

	vec2i getDimension(int c, int lastC) const {
		vec2i dim(0, glyphHeight);

		FT_Activate_Size(size);

		const Glyph* glyph = 0;

		if(c <= 0xff) {
			glyph = &lowChars[c];
		}
		else {
			auto g = std::lower_bound(hiChars.begin(), hiChars.end(), c);
			if(g != hiChars.end() && g->letter == c)
				glyph = &g->glyph;
			else
				glyph = &lowChars['?'];
		}

		if(glyph) {
			dim.x += (int)glyph->xAdv;

			//Don't kern anything involving digits
			if(c < '0' || c > '9') {
				if(lastC) {
					FT_Vector kerning;
					FT_Get_Kerning(*face, lastC, glyph->glyph_index, 0, &kerning);
					
					if(kerning.x != 0)
						dim.x += (unsigned)(kerning.x >> 6);
				}
			}
		}

		return dim;
	}

	unsigned getBaseline() const {
		return baseLine;
	}

	unsigned getLineHeight() const {
		return glyphHeight;
	}

	FontFT2()
		: lowChars(new Glyph[256]), glyphHeight(0), baseLine(0), textureHeight(1), textureWidth(1)
	{
		memset(lowChars, 0, sizeof(Glyph) * 256);
	}

	~FontFT2()
	{
		FT_Done_Size(size);
		delete[] lowChars;
		for(auto tex = textures.begin(), end = textures.end(); tex != end; ++tex)
			delete *tex;
	}
};

FT_Library* library = 0;
std::map<std::string, FT_Face*> faces;
const int FONT_PAGE_SIZE = 512;

Font* loadFontFT2(render::RenderDriver& driver, const char* filename,
					std::vector<std::pair<int,int>>& pages, int size) {
	FontFT2* font = new FontFT2();
	font->textureWidth = FONT_PAGE_SIZE;
	font->textureHeight = FONT_PAGE_SIZE;

	std::vector<Image*> images;
	int cur_page = 0;

	Image* img = new Image(FONT_PAGE_SIZE, FONT_PAGE_SIZE, FMT_Alpha, 0xff);
	images.push_back(img);

	int x = 0, y = 0;

	//Create the library if none exists
	if(!library) {
		library = new FT_Library();
		FT_Init_FreeType(library);
	}

	//Read in the font face if necessary
	FT_Face* face = 0;

	auto it = faces.find(filename);
	if(it != faces.end()) {
		face = it->second;
	}
	else {
		face = new FT_Face();
		if (int err = FT_New_Face(*library, filename, 0, face)) {
			fprintf(stderr, "Error loading font %s (code %d).\n", filename, err);
			return 0;
		}

		faces[filename] = face;
	}

	FT_New_Size(*face, &font->size);
	FT_Activate_Size(font->size);

	FT_Set_Char_Size(*face, 0, size << 6, 96, 96);

	font->x_scale = (double)((*face)->size->metrics.x_scale / 65536.0);
	font->y_scale = (double)((*face)->size->metrics.y_scale / 65536.0);
	font->glyphHeight = (unsigned)((*face)->size->metrics.height >> 6);
	font->face = face;

	font->baseLine = font->glyphHeight + (unsigned)((*face)->size->metrics.descender >> 6);
	int lineHeight = 0;
	
	for(auto page = pages.begin(), end = pages.end(); page != end; ++page) {
		int from = page->first;
		int to = page->second;

		for(int ch = from; ch < to; ++ch) {
			int glyph_ind = FT_Get_Char_Index(*face, ch);

			FontFT2::Glyph glyph;
			glyph.page = cur_page;

			if(glyph_ind != 0) {
				FT_Load_Glyph(*face, glyph_ind, FT_LOAD_RENDER);

				auto glp = (*face)->glyph;
				auto bmp = glp->bitmap;

				//Collect data about glyph
				glyph.draw = true;
				glyph.glyph_index = glyph_ind;
				glyph.w = glp->bitmap.width;
				glyph.h = glp->bitmap.rows;
				glyph.wOff = glp->bitmap_left;
				glyph.hOff = font->baseLine - glp->bitmap_top;
				glyph.xAdv = ((float)glp->metrics.horiAdvance) / 64.f;

				glyph.x = x;
				glyph.y = y;

				if(glyph.h > lineHeight)
					lineHeight = glyph.h;

				//Find a fitting spot on the image
				x += (unsigned)glyph.w + 2;
				if(x > FONT_PAGE_SIZE) {
					x = (unsigned)glyph.w + 2;
					glyph.x = 0;

					y += lineHeight + 1;
					glyph.y += lineHeight + 1;
					lineHeight = glyph.h;

					if(y + font->glyphHeight + 1 > (unsigned)FONT_PAGE_SIZE) {
						img = new Image(FONT_PAGE_SIZE, FONT_PAGE_SIZE, FMT_Alpha, 0xff);
						images.push_back(img);

						y = 0;
						glyph.y = 0;

						++cur_page;
						++glyph.page;
					}
				}


				//Put the glyph on the actual image
				unsigned char* buffer = bmp.buffer;
				for(int row = 0; row < bmp.rows; ++row, buffer += bmp.width)
					memcpy(&img->get_alpha(glyph.x, glyph.y + row), buffer, bmp.width);
			}
			else {
				glyph.draw = false;
				glyph.xAdv = 0;
			}

			if(ch <= 0xff)
				font->lowChars[ch] = glyph;
			else
				font->hiChars.push_back(FontFT2::GlyphEntry(ch, glyph));
		}
	}

	//Create the textures
	for(auto it = images.begin(), end = images.end(); it != end; ++it) {
		auto material = new render::RenderState();
		material->depthTest = render::DT_NoDepthTest;
		material->lighting = false;
		material->culling = render::FC_None;
		material->baseMat = MAT_Font;
		material->depthWrite = false;
		if(load_resources)
			material->textures[0] = resource::queueImage(*it, 20, true, false);

		font->textures.push_back(material);
	}

	std::sort(font->hiChars.begin(), font->hiChars.end());
	return font;
}

};
