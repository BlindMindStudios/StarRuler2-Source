#include "image.h"
#include "str_util.h"
#include <png.h>
#include <stdint.h>
#include <functional>

unsigned ColorDepths[4] = { DEPTH_Grey, DEPTH_Alpha, DEPTH_RGB, DEPTH_RGBA };

Image* Image::random(const vec2u& resolution, int rnd(int,int)) {
	Image* img = new Image(resolution.width, resolution.height, FMT_RGB);
	
	for(unsigned y = 0; y < resolution.height; ++y)
		for(unsigned x = 0; x < resolution.width; ++x)
			img->get_rgb(x,y) = ColorRGB(rnd(0,255), rnd(0,255), rnd(0,255));

	return img;
}

Image* Image::sphereDistort() const {
	Image* out = new Image(width, height, format);
	Image& img = *out;

	auto get_wrapped = [this](int x, int y) -> Color {
		x = (x + width) % width;
		return get(x,y);
	};

	auto set_out = [&img](unsigned x, unsigned y, const Color& col) {

		switch(img.format) {
		case FMT_Grey:
			img.grey[y*img.width + x] = col.r;
			break;
		case FMT_Alpha:
			img.grey[y*img.width + x] = col.a;
			break;
		case FMT_RGB:
			img.rgb[y*img.width + x] = ColorRGB(col.r,col.g,col.b);
			break;
		case FMT_RGBA:
			img.rgba[y*img.width + x] = col;
			break;
		}
	};

	for(unsigned y = 0; y < height; ++y) {
		double angle = ((double)y - (double)height * 0.5) * 3.14159265359 / (double)height;
		double needPixels = (1.0 / cos(angle)); needPixels *= needPixels;

		if(y == 0 || y == height-1 || needPixels >= (double)width) {
			//Special case for poles: Average all pixels

			unsigned r = 0, g = 0, b = 0, a = 0;

			for(unsigned x = 0; x < width; ++x) {
				Color col = get(x,y);
				r += col.r;
				g += col.g;
				b += col.b;
				a += col.a;
			}

			Color col((r+width/2) / width, (g+width/2) / width, (b+width/2) / width, (a+width/2) / width);
			for(unsigned x = 0; x < width; ++x)
				set_out(x,y,col);
		}
		else {

			unsigned r,g,b,a;
			auto addCol = [&r,&g,&b,&a](Color col) {
				r += col.r; g += col.g; b += col.b; a += col.a;
			};

			for(unsigned x = 0; x < width; ++x) {
				double pixels = needPixels;

				Color col = get(x,y);
				r = col.r, g = col.g, b = col.b, a = col.a;
				pixels -= 1.0;

				for(int off = 1; true; ++off) {
					if(pixels >= 2.0) {
						addCol(get_wrapped(x-off,y));
						addCol(get_wrapped(x+off,y));
						pixels -= 2.0;
					}
					else {
						addCol( Color(Colorf(get_wrapped(x-off,y)) * (pixels * 0.5)) );
						addCol( Color(Colorf(get_wrapped(x+off,y)) * (pixels * 0.5)) );
						break;
					}
				}
				
				r = unsigned((double)r / needPixels + 0.5);
				if(r > 0xff)
					r = 0xff;
				g = unsigned((double)g / needPixels + 0.5);
				if(g > 0xff)
					g = 0xff;
				b = unsigned((double)b / needPixels + 0.5);
				if(b > 0xff)
					b = 0xff;
				a = unsigned((double)a / needPixels + 0.5);
				if(a > 0xff)
					a = 0xff;

				set_out(x,y, Color(r,g,b,a));
			}
		}
	}

	return out;
}

Image* Image::makeMipmap() const {
	if(width <= 2 || height <= 2)
		return 0;

	Image* img = new Image(width/2, height/2, format);

	unsigned r,g,b,a;
	auto addRGB = [&r,&g,&b](const ColorRGB& col) {
		r += col.r;
		g += col.g;
		b += col.b;
	};
	
	auto addRGBA = [&r,&g,&b,&a](const Color& col) {
		r += col.r;
		g += col.g;
		b += col.b;
		a += col.a;
	};
	
	for(unsigned y = 0; y < img->height; ++y) {
		for(unsigned x = 0; x < img->width; ++x) {
			unsigned lx = x * 2, ly = y * 2;

			switch(format) {
			case FMT_Grey: case FMT_Alpha:
				r = 2;
				r += get_grey(lx,ly);
				r += get_grey(lx+1,ly);
				r += get_grey(lx,ly);
				r += get_grey(lx+1,ly+1);

				img->get_grey(x, y) = r / 4;
				break;
			case FMT_RGB:
				r = g = b = 2;
				addRGB(get_rgb(lx,ly));
				addRGB(get_rgb(lx+1,ly));
				addRGB(get_rgb(lx,ly+1));
				addRGB(get_rgb(lx+1,ly+1));

				img->get_rgb(x,y) = ColorRGB(r/4,g/4,b/4);
				break;
			case FMT_RGBA:
				r = g = b = a = 2;
				
				addRGBA(get_rgba(lx,ly));
				addRGBA(get_rgba(lx+1,ly));
				addRGBA(get_rgba(lx,ly+1));
				addRGBA(get_rgba(lx+1,ly+1));

				img->get_rgba(x,y) = Color(r/4,g/4,b/4,a/4);
				break;
			};
		}
	}

	return img;
}

Image* Image::crop(const rect<unsigned>& region) const {
	auto bound = region.clipAgainst(rect<unsigned>(0, 0, width, height));
	if(bound.getSize() == vec2u(width, height))
		return new Image(*this);

	Image* out = new Image(bound.getWidth(), bound.getHeight(), format);
	if(out->width == 0 || out->height == 0)
		return out;

	unsigned bpp = ColorDepths[format];

	for(unsigned y = bound.topLeft.y; y < bound.botRight.y; ++y)
		memcpy(&out->grey[(y-bound.topLeft.y) * bpp * out->width], &grey[((y*width) + bound.topLeft.x) * bpp], bound.getWidth() * bpp);

	return out;
}

Image* loadPNG(const char* filename);
bool savePNG(const Image* img, const char* filename, bool flip);

Image* loadImage(const char* filename) {
	auto p_ext = strrchr(filename, '.');
	if(p_ext == 0) //No extension to the filename (TODO: Handle this a better way?)
		return 0;

	if(strcmp_nocase(p_ext, ".png") == 0)
		return loadPNG(filename);

	return 0;
}

//PNG Loader

namespace PNG_UTIL {

struct callOnReturn {
	std::function<void(void)> func;

	callOnReturn(std::function<void(void)> func) : func(func) {}
	~callOnReturn() { func(); }
};

void f_read(png_structp png, png_bytep out, png_size_t count) {
	fread(out, count, 1, (FILE*)png_get_io_ptr(png));
}

void f_write(png_structp png, png_bytep in, png_size_t count) {
	fwrite(in, count, 1, (FILE*)png_get_io_ptr(png));
}

void f_flush(png_structp png) {
	fflush((FILE*)png_get_io_ptr(png));
}

};

Image* loadPNG(const char* filename) {
	//Number of bytes of the PNG signature to read (must <= 8)
	const unsigned int readSigBytes = 8;

	auto imgfile = fopen(filename,"rb");
	if(imgfile == 0)
		return 0;

	PNG_UTIL::callOnReturn closeFile(
		[&imgfile](){ fclose(imgfile); }
	);

	//Confirm that the file is a png image
	unsigned char buffer[readSigBytes];
	if(fread(buffer,1,readSigBytes,imgfile) != readSigBytes || png_sig_cmp(buffer, 0, readSigBytes) != 0)
		return 0;
	
	//Prep png structures
	png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
	if(png == 0)
		return 0;

	png_infop png_info = png_create_info_struct(png);
	if(png_info == 0) {
		png_destroy_read_struct(&png, NULL, NULL);
		return 0;
	}

	PNG_UTIL::callOnReturn deletePNG(
		[&png,&png_info]() { png_destroy_read_struct(&png, &png_info, NULL); }
	);

	//Prep PNG error handling
	if(setjmp(png_jmpbuf(png))) {
        fprintf(stderr, "Error reading png file: %s\n", filename);
		return 0;
	}

	//Use c standard file operations, and read the png as an 8-bit depth, RGBA
	png_set_read_fn(png, imgfile, PNG_UTIL::f_read);
	//png_init_io(png, imgfile);
	png_set_sig_bytes(png, readSigBytes);

	png_read_info(png, png_info);

	//Setup transformations for formats we can't use anyway
	png_set_expand(png);
	png_set_strip_16(png);
	png_set_packing(png);
	png_set_interlace_handling(png);

	png_read_update_info(png, png_info);
	
	unsigned int w, h;
	int depth, format, interlace, compress, filter;
	png_get_IHDR(png, png_info, &w, &h, &depth, &format, &interlace, &compress, &filter);

	if(depth != 8 || w == 0 || h == 0)
		return 0;

	png_bytepp rows = new png_bytep[h];
	Image* image = 0;
	ColorFormat imageFormat = FMT_INVALID;

	//TODO: Handle other file formats?
	switch(format) {
	case PNG_COLOR_TYPE_GRAY:
		imageFormat = FMT_Grey; break;
	case PNG_COLOR_TYPE_RGB:
		imageFormat = FMT_RGB; break;
	case PNG_COLOR_TYPE_RGB_ALPHA:
		imageFormat = FMT_RGBA; break;
	}

	if(imageFormat != FMT_INVALID) {
		image = new Image(w, h, imageFormat);

		for(int y = h-1; y >= 0; --y)
			rows[y] = (png_bytep)(image->grey + (y * w * ColorDepths[image->format]));

		png_read_image(png, rows);
	}

	delete[] rows;
	return image;
}

bool saveImage(const Image* img, const char* filename, bool flip) {
	auto p_ext = strrchr(filename, '.');
	if(p_ext == 0) //No extension to the filename (TODO: Handle this a better way?)
		return false;

	if(strcmp_nocase(p_ext, ".png") == 0)
		return savePNG(img, filename, flip);
	return false;
}

bool savePNG(const Image* img, const char* filename, bool flip) {
	auto imgfile = fopen(filename, "wb");
	if(!imgfile)
		return false;

	png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);

	if(!png) {
		fclose(imgfile);
		return false;
	}

	png_infop info = png_create_info_struct(png);
	png_byte** rows = 0;
	png_byte* row_head = 0;
	unsigned Bpp;

	if(setjmp(png_jmpbuf(png))) {
		fprintf(stderr, "Error writing png file: %s\n", filename);
		goto png_fail;
	}

	png_uint_32 pngFmt;
	switch(img->format) {
	case FMT_Grey:
		pngFmt = PNG_COLOR_TYPE_GRAY;
		break;
	case FMT_RGB:
		pngFmt = PNG_COLOR_TYPE_RGB;
		break;
	case FMT_RGBA:
		pngFmt = PNG_COLOR_TYPE_RGBA;
		break;
	default:
		goto png_fail;
	}

	png_set_IHDR(png, info,
		img->width, img->height,
		8,
		pngFmt,
		PNG_INTERLACE_NONE,
		PNG_COMPRESSION_TYPE_DEFAULT,
		PNG_FILTER_TYPE_DEFAULT
		);

	Bpp = ColorDepths[img->format];

	rows = (png_byte**)png_malloc(png, img->height * sizeof(png_byte*));

	row_head = (png_byte*)png_malloc(png, img->height * img->width * Bpp);

	for(unsigned y = 0; y < img->height; ++y) {
		png_byte* row = row_head + (img->width * y * Bpp);
		rows[y] = row;

		unsigned cy = flip ? img->height - 1 - y : y;
		switch(img->format) {
		case FMT_Grey:
			memcpy(row, &img->grey[cy*img->width], img->width * Bpp);
			break;
		case FMT_RGB:
			memcpy(row, &img->rgb[cy*img->width], img->width * Bpp);
			break;
		case FMT_RGBA:
			memcpy(row, &img->rgba[cy*img->width], img->width * Bpp);
			break;
		}
	}
	
	png_set_write_fn(png, imgfile, PNG_UTIL::f_write, PNG_UTIL::f_flush);
	//png_init_io(png, imgfile);
	png_set_rows(png, info, rows);
	png_write_png(png, info, PNG_TRANSFORM_IDENTITY, NULL);

	png_free(png, row_head);
	png_free(png, rows);

	fclose(imgfile);
	return true;

png_fail:
	png_destroy_write_struct(&png, &info);
	fclose(imgfile);
	return false;
}
