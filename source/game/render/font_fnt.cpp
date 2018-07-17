#include "render/font.h"
#include "render/driver.h"
#include <stdio.h>
#include "str_util.h"
#include "vec2.h"
#include "main/initialization.h"

#include <algorithm>

namespace resource {
extern render::Texture* queueImage(const std::string& abs_file, int priority, bool mipmap, bool cachePixels, bool cubemap = false);
};

namespace render {

class FontFNT : public Font {
public:
	std::vector<render::RenderState*> textures;

	struct Glyph {
		unsigned short x : 16, y : 16;
		bool draw : 1;
		unsigned char page : 3;
		unsigned char w : 8, h : 8;
		char wOff : 8, hOff : 8;
		unsigned char xAdv : 8;
	};

	struct GlyphEntry {
		fontChar letter;
		Glyph glyph;

		bool operator<(const GlyphEntry& other) const { return letter < other.letter; }
		GlyphEntry(fontChar Letter) : letter(Letter) {}
		GlyphEntry(fontChar Letter, Glyph& Glyph) : letter(Letter), glyph(Glyph) {}
	};

	struct KernEntry {
		union {
			unsigned v;
			struct { fontChar left : 16, right : 16; };
		};
		int offset;

		bool operator<(const KernEntry& other) const { return v < other.v; }
		KernEntry(fontChar Left, fontChar Right) : left(Left), right(Right) {}
	};

	Glyph* lowChars;
	std::vector<GlyphEntry> hiChars;
	std::vector<KernEntry> kerning;

	unsigned glyphHeight, textureHeight, textureWidth;

	unsigned getBaseline() const {
		return glyphHeight;
	}

	unsigned getLineHeight() const {
		return glyphHeight;
	}

	void draw(render::RenderDriver* driver, const char* text, int X, int Y, const Color* color, const recti* clip = 0) const {
		int x = X, y = Y;

		Color colors[4];
		if(color)
			colors[0] = colors[1] = colors[2] = colors[3] = *color;

		float xFactor = 1.f / float(textureWidth), yFactor = 1.f / float(textureHeight);
		vec2f font_verts[4], font_tc[4];

		rectf fclip;
		if(clip)
			fclip = rectf(*clip);

		unsigned lastTexture = (unsigned)textures.size();

		fontChar lastC = 0;
		u8it it(text);

		while(fontChar c = it++) {
			if(c == L'\n') {
				y += glyphHeight;
				x = X;
				lastC = 0;
			}
			else {
				if(lastC) {
					auto k = std::lower_bound(kerning.begin(), kerning.end(), KernEntry(lastC, c));
					if(k != kerning.end() && k->left == lastC && k->right == c)
						x += k->offset;
				}
				lastC = c;

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

				if(glyph.draw) {
					rectf pos = rectf::area(vec2f((float)(x + glyph.wOff), (float)(y + glyph.hOff)), vec2f(glyph.w, glyph.h));
					rectf source = rectf::area(vec2f((float)glyph.x * xFactor, (float)glyph.y * yFactor),
										vec2f((float)glyph.w * xFactor, (float)glyph.h * yFactor));

					if(clipQuad(pos, source, clip ? &fclip : 0, font_verts, font_tc)) {
						if(glyph.page != lastTexture) {
							auto& mat = *textures[glyph.page];
							driver->switchToRenderState(mat);
							lastTexture = glyph.page;
						}

						driver->drawQuad(font_verts,font_tc,color ? colors : 0);
					}
				}

				x += glyph.xAdv;
			}
		}
	}

	vec2i drawChar(render::RenderDriver* driver, int c, int lastC,
					int X, int Y, const Color* color, const recti* clip = 0) const {
		int x = X, y = Y;
		Color colors[4];
		if(color)
			colors[0] = colors[1] = colors[2] = colors[3] = *color;

		float xFactor = 1.f / float(textureWidth), yFactor = 1.f / float(textureHeight);
		vec2f font_verts[4], font_tc[4];

		rectf fclip;
		if(clip)
			fclip = rectf(*clip);

		if(lastC) {
			auto k = std::lower_bound(kerning.begin(), kerning.end(), KernEntry(lastC, c));
			if(k != kerning.end() && k->left == lastC && k->right == c)
				x += k->offset;
		}

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

		if(glyph.draw) {
			rectf pos = rectf::area(vec2f((float)(x + glyph.wOff), (float)(y + glyph.hOff)), vec2f(glyph.w, glyph.h));
			rectf source = rectf::area(vec2f((float)glyph.x * xFactor, (float)glyph.y * yFactor),
								vec2f((float)glyph.w * xFactor, (float)glyph.h * yFactor));

			if(clipQuad(pos, source, clip ? &fclip : 0, font_verts, font_tc)) {
				auto& mat = *textures[glyph.page];
				driver->switchToRenderState(mat);
			
				driver->drawQuad(font_verts,font_tc,color ? colors : 0);
			}
		}

		x += glyph.xAdv;
		return vec2i(x - X, y - Y);
	}

	vec2i getDimension(const char* text) const {
		vec2i size(0, glyphHeight);

		fontChar lastC = 0;
		u8it it(text);

		while(fontChar c = it++) {
			if(lastC) {
				auto k = std::lower_bound(kerning.begin(), kerning.end(), KernEntry(lastC, c));
				if(k != kerning.end() && k->left == lastC && k->right == c)
					size.x += k->offset;
			}
			lastC = c;

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

			if(glyph)
				size.x += glyph->xAdv;
			++text;
		}

		return size;
	}


	vec2i getDimension(int c, int lastC) const {
		vec2i size(0, glyphHeight);

		if(lastC) {
			auto k = std::lower_bound(kerning.begin(), kerning.end(), KernEntry(lastC, c));
			if(k != kerning.end() && k->left == lastC && k->right == c)
				size.x += k->offset;
		}

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

		if(glyph)
			size.x += glyph->xAdv;

		return size;
	}

	FontFNT()
		: lowChars(new Glyph[256]), glyphHeight(0), textureHeight(1), textureWidth(1)
	{
		memset(lowChars, 0, sizeof(Glyph) * 256);
	}

	~FontFNT()
	{
		delete[] lowChars;
		foreach(tex, textures)
			delete *tex;
	}
};

Font* loadFontFNT(render::RenderDriver* driver, const char* filename) {
	auto file = fopen(filename, "r");
	if(file == 0)
		return 0;

	auto slash = strrchr(filename, '/');
	if(auto bSlash = strrchr(filename, '\\'))
		if(bSlash > slash)
			slash = bSlash;

	std::string folder(filename, slash ? slash + 1 - filename : 0);

	//Skip first line
	do {
		int c = fgetc(file);
		if(c == L'\n' || c == L'\r' || c == EOF)
			break;
	} while(true);
	
	if(feof(file)) {
		fclose(file);
		return 0;
	}

	FontFNT* font = new FontFNT;

	if(false) {
failedLoad:
		delete font;
		fclose(file);
		return 0;
	}

	int pages, lineCheck;

	if(fscanf(file,
		" common lineHeight=%i base=%*i scaleW=%i scaleH=%i pages=%i packed=%*i alphaChnl=%*i redChnl=%*i greenChnl=%*i blueChnl=%i ",
		&font->glyphHeight, &font->textureWidth, &font->textureHeight, &pages, &lineCheck) < 5
		|| pages == 0 || pages > 7 || font->glyphHeight <= 0)
		goto failedLoad;

	int page; char pageName[256];
	while(pages--) {
		int args = fscanf(file,"page id=%i file=%255s ", &page, pageName);
		if(args < 2 || (unsigned int)page != font->textures.size())
			goto failedLoad;

		std::string pageFile = folder + trim(pageName,"\"");

		auto material = new render::RenderState();
		material->depthTest = render::DT_NoDepthTest;
		material->lighting = false;
		material->culling = render::FC_None;
		material->baseMat = render::MAT_Alpha;
		if(load_resources)
			material->textures[0] = resource::queueImage(pageFile, 20, true, false);

		font->textures.push_back(material);
	}

	int glyphs;
	if(fscanf(file, "chars count=%i ", &glyphs) != 1)
		goto failedLoad;

	while(glyphs--) {
		int c, x, y, w, h, wOff, hOff, xAdv, page, channel;
		if(fscanf(file, "char id=%i x=%i y=%i width=%i height=%i xoffset=%i yoffset=%i xadvance=%i page=%i chnl=%i ",
			&c, &x, &y, &w, &h, &wOff, &hOff, &xAdv, &page, &channel) != 10
			|| page < 0 || page >= (int)font->textures.size())
			goto failedLoad;
		FontFNT::Glyph glyph;
		glyph.draw = c != 32;
		glyph.x = x;
		glyph.y = y;
		glyph.w = w;
		glyph.h = h;
		glyph.wOff = wOff;
		glyph.hOff = hOff;
		glyph.xAdv = xAdv;
		glyph.page = page;

		if(c <= 0xff)
			font->lowChars[c] = glyph;
		else
			font->hiChars.push_back(FontFNT::GlyphEntry(c,glyph));
	}

	//Load kerning data
	int kerns;
	if(fscanf(file, "kernings count=%i ", &kerns) == 1) {
		while(kerns--) {
			int left, right, offset;
			if(fscanf(file, "kerning first=%i second=%i amount=%i ", &left, &right, &offset) == 3) {
				FontFNT::KernEntry kerning((fontChar)left, (fontChar)right);
				kerning.offset = offset;
				font->kerning.push_back(kerning);
			}
			else {
				break;
			}
		}
	}
	
	std::sort(font->hiChars.begin(), font->hiChars.end());
	std::sort(font->kerning.begin(), font->kerning.end());
	return font;
}

};
