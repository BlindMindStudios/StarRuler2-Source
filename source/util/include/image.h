#pragma once
#include "color.h"
#include "vec2.h"
#include "rect.h"
#include <string.h>
#include <cmath>

enum ColorFormat {
	FMT_Grey,
	FMT_Alpha,
	FMT_RGB,
	FMT_RGBA,
	FMT_INVALID
};

enum ColorDepth {
	DEPTH_Grey = sizeof(unsigned char),
	DEPTH_Alpha = sizeof(unsigned char),
	DEPTH_RGB = sizeof(ColorRGB),
	DEPTH_RGBA = sizeof(Color)
};

//Color depths by format (e.g. ColorDepths[FMT_RGB] == DEPTH_RGB)
extern unsigned ColorDepths[4];

//Standard image in 32-bit RGBA format
struct Image {
	union {
		unsigned char* grey;
		ColorRGB* rgb;
		Color* rgba;
	};

	ColorFormat format;
	unsigned int width, height;

	unsigned char& get_alpha(unsigned int x, unsigned int y) {
		return grey[x + (y * width)];
	}

	unsigned char get_alpha(unsigned int x, unsigned int y) const {
		return grey[x + (y * width)];
	}

	unsigned char& get_grey(unsigned int x, unsigned int y) {
		return grey[x + (y * width)];
	}

	unsigned char get_grey(unsigned int x, unsigned int y) const {
		return grey[x + (y * width)];
	}

	ColorRGB& get_rgb(unsigned int x, unsigned int y) {
		return rgb[x + (y * width)];
	}

	ColorRGB get_rgb(unsigned int x, unsigned int y) const {
		return rgb[x + (y * width)];
	}

	Color& get_rgba(unsigned int x, unsigned int y) {
		return rgba[x + (y * width)];
	}

	Color get_rgba(unsigned int x, unsigned int y) const {
		return rgba[x + (y * width)];
	}

	Color get(unsigned int x, unsigned int y) const {
		switch(format) {
		case FMT_Grey:
		case FMT_Alpha:
			return grey[x + (y * width)];
		case FMT_RGB:
			return rgb[x + (y * width)];
		case FMT_RGBA:
			return rgba[x + (y * width)];
		}
		return Color();
	}

	Color getTexel(float x, float y) {
		float ipart;
		float u = std::modf(x,&ipart), v = std::modf(y,&ipart);
		if(u < 0)
			u = 1.f + u;
		u *= (float)width;
		if(v < 0)
			v = 1.f + v;
		v *= (float)height;

		int x1 = (int)u;
		int x2 = (x1 + 1) % (int)width;
		int y1 = (int)v;
		int y2 = (y1 + 1) % (int)height;
		
		Color upper = get(x1,y1).getInterpolated(get(x2,y1), std::modf(u,&ipart));
		Color lower = get(x1,y2).getInterpolated(get(x2,y2), std::modf(u,&ipart));
		
		return upper.getInterpolated(lower, std::modf(v,&ipart));
	}

	Color getTexel(const vec2f& pos) {
		return getTexel(pos.x, pos.y);
	}

	static Image* random(const vec2u& resolution, int(int,int));

	//Returns an image that is a sphere-distortion-corrected version of this one
	Image* sphereDistort() const;

	//Returns a half-resolution version of this image
	//If the image is too small, returns 0
	Image* makeMipmap() const;

	Image* crop(const rect<unsigned>& bound) const;

	Image() : width(0), height(0), rgba(0) {}

	Image(const Image& other) : width(0), height(0), rgba(0) {
		*this = other;
	}

	void operator=(const Image& other) {
		if(other.width != width || other.height != height || other.format != format) {
			width = other.width;
			height = other.height;
			format = other.format;

			switch(format) {
				case FMT_Grey:
				case FMT_Alpha:
					delete[] grey;
					grey = new unsigned char[width*height];
				break;
				case FMT_RGB:
					delete[] rgb;
					rgb = new ColorRGB[width*height];
				break;
				case FMT_RGBA:
					delete[] rgba;
					rgba = new Color[width*height];
				break;
			}
		}

		switch(format) {
			case FMT_Grey:
			case FMT_Alpha:
				memcpy(grey, other.grey, width*height*sizeof(unsigned char));
			break;
			case FMT_RGB:
				memcpy(rgb, other.rgb, width*height*sizeof(ColorRGB));
			break;
			case FMT_RGBA:
				memcpy(rgba, other.rgba, width*height*sizeof(Color));
			break;
		}
	}

	Image(unsigned int Width, unsigned int Height, ColorFormat Format)
		: width(Width), height(Height), format(Format), rgba(0)
	{
		if(width > 0 && height > 0) {
			switch(Format) {
			case FMT_Grey:
			case FMT_Alpha:
				grey = new unsigned char[Width*Height]; break;
			case FMT_RGB:
				rgb = new ColorRGB[Width*Height]; break;
			case FMT_RGBA:
				rgba = new Color[Width*Height]; break;
			}
		}
	}

	Image(unsigned int Width, unsigned int Height, ColorFormat Format, unsigned char defaultLevel)
		: width(Width), height(Height), format(Format), rgba(0)
	{
		if(width > 0 && height > 0) {
			switch(Format) {
				case FMT_Grey:
				case FMT_Alpha:
					grey = new unsigned char[Width*Height]; break;
				case FMT_RGB:
					rgb = new ColorRGB[Width*Height]; break;
				case FMT_RGBA:
					rgba = new Color[Width*Height]; break;
			}

			if(grey)
				memset(grey, defaultLevel, Width * Height * ColorDepths[format]);
		}
	}

	void makeRGBA(const Image& other) {
		resize(other.width, other.height, FMT_RGBA);
		switch(other.format) {
			case FMT_Grey:
			case FMT_Alpha:
				for(size_t i = 0, sz = other.width * other.height; i < sz; ++i) {
					Color& col = rgba[i];
					col.r = other.grey[i];
					col.g = col.r;
					col.b = col.r;
					col.a = 0xff;
				}
			break;
			case FMT_RGB:
				for(size_t i = 0, sz = other.width * other.height; i < sz; ++i) {
					Color& col = rgba[i];
					ColorRGB& ocol = other.rgb[i];
					col.r = ocol.r;
					col.g = ocol.g;
					col.b = ocol.b;
					col.a = 0xff;
				}
			break;
			case FMT_RGBA:
				for(size_t i = 0, sz = other.width * other.height; i < sz; ++i)
					rgba[i] = other.rgba[i];
			break;
		}
	}

	void resize(unsigned Width, unsigned Height, ColorFormat newFormat = FMT_INVALID) {
		if(newFormat == FMT_INVALID)
			newFormat = format;

		width = Width;
		height = Height;

		switch(format) {
			case FMT_Grey:
			case FMT_Alpha:
				delete[] grey; break;
			case FMT_RGB:
				delete[] rgb; break;
			case FMT_RGBA:
				delete[] rgba; break;
		}
		if(width > 0 && height > 0) {
			format = newFormat;
			switch(format) {
				case FMT_Grey:
				case FMT_Alpha:
					grey = new unsigned char[Width*Height]; break;
				case FMT_RGB:
					rgb = new ColorRGB[Width*Height]; break;
				case FMT_RGBA:
					rgba = new Color[Width*Height]; break;
			}
		}
	}

	~Image() {
			switch(format) {
			case FMT_Grey:
			case FMT_Alpha:
				delete[] grey; break;
			case FMT_RGB:
				delete[] rgb; break;
			case FMT_RGBA:
				delete[] rgba; break;
			}
	}
};

//Attempts to load the file according to the extension. If the file cannot be loaded, 0 is returned.
Image* loadImage(const char* filename);
bool saveImage(const Image* img, const char* filename, bool flip = false);
