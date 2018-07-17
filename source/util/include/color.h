#pragma once
#include <math.h>

struct ColorRGB {
	unsigned char r : 8;
	unsigned char g : 8;
	unsigned char b : 8;

	ColorRGB() : r(255), g(255), b(255) {}
	ColorRGB(unsigned char R, unsigned char G, unsigned char B) : r(R), g(G), b(B) {}
};

struct Color {
	union {
		unsigned int color;
		struct {
			unsigned char r : 8;
			unsigned char g : 8;
			unsigned char b : 8;
			unsigned char a : 8;
		};
	};

	Color() : color(0xffffffff) {}
	Color(unsigned int col) { set(col); }
	Color(unsigned char grey) : r(grey), g(grey), b(grey), a(255) {}
	Color(unsigned char R, unsigned char G, unsigned char B) : r(R), g(G), b(B), a(0xff) {}
	Color(unsigned char R, unsigned char G, unsigned char B, unsigned char A) : r(R), g(G), b(B), a(A) {}

	Color(ColorRGB rgb) : r(rgb.r), g(rgb.g), b(rgb.b), a(255) {}

	void set(unsigned int col) {
		r = (col & 0xff000000) >> 24;
		g = (col & 0x00ff0000) >> 16;
		b = (col & 0x0000ff00) >> 8;
		a = (col & 0x000000ff);
	}

	Color getInterpolated(const Color& other, float pct) const {
		if(pct <= 0)
			return *this;
		else if(pct >= 1)
			return other;
		else {
			return Color(
				(unsigned char)(float(r) + float(other.r - r) * pct),
				(unsigned char)(float(g) + float(other.g - g) * pct),
				(unsigned char)(float(b) + float(other.b - b) * pct),
				(unsigned char)(float(a) + float(other.a - a) * pct) );
		}
	}

	Color operator*(const Color& other) const {
		return Color(
			(unsigned char)(float(r) / 255.f * float(other.r)),
			(unsigned char)(float(g) / 255.f * float(other.g)),
			(unsigned char)(float(b) / 255.f * float(other.b)),
			(unsigned char)(float(a) / 255.f * float(other.a)) );
	}
};

struct Colorf {
	float r, g, b, a;

	Colorf() : r(1), g(1), b(1), a(1) {}
	Colorf(float R, float G, float B) : r(R), g(G), b(B), a(1) {}
	Colorf(float R, float G, float B, float A) : r(R), g(G), b(B), a(A) {}

	bool operator!=(const Colorf& other) const {
		return r != other.r || g != other.g || b != other.b || a != other.a;
	}

	operator Color() const {
		return Color(
			(r >= 1.f ? 255 : (r <= 0.f ? 0 : (unsigned char)(r * 255.f))),
			(g >= 1.f ? 255 : (g <= 0.f ? 0 : (unsigned char)(g * 255.f))),
			(b >= 1.f ? 255 : (b <= 0.f ? 0 : (unsigned char)(b * 255.f))),
			(a >= 1.f ? 255 : (a <= 0.f ? 0 : (unsigned char)(a * 255.f)))
			);
	}

	explicit Colorf(const Color& c)
		: r(float(c.r) / 255.f), g(float(c.g) / 255.f), b(float(c.b) / 255.f), a(float(c.a) / 255.f)
	{}

	void operator=(const Color& c) {
		float ratio = 1/255.f;
		r = float(c.r) * ratio;
		g = float(c.g) * ratio;
		b = float(c.b) * ratio;
		a = float(c.a) * ratio;
	}

	Colorf operator*(float factor) const {
		return Colorf(r * factor, g * factor, b * factor, a * factor);
	}

	Colorf& operator*=(float factor) {
		r *= factor;
		g *= factor;
		b *= factor;
		a *= factor;
		return *this;
	}

	Colorf& operator+=(const Colorf& other) {
		r += other.r;
		g += other.g;
		b += other.b;
		a += other.a;
		return *this;
	}

	//Returns the maximal value of the color channels
	//For colors in the [0,1] range, this is the Value of that color
	float getValue() const {
		float V = r;
		if(g>V) V=g;
		if(b>V) V=b;
		return V;
	}

	//Returns the saturation of the color
	float getSaturation() const {
		float M = r; if(g>M) M=g; if(b>M) M=b;
		float m = r; if(g<m) m=g; if(b<m) m=b;
		float Chroma = M-m;

		if(Chroma == 0)
			return 0;
		else
			return Chroma/M;
	}

	//Returns the hue of the color, in degrees in the range [0,360)
	//Greys return as 0
	float getHue() const {
		float M = r; if(g>M) M=g; if(b>M) M=b;
		float m = r; if(g<m) m=g; if(b<m) m=b;
		float Chroma = M-m;

		if(Chroma == 0)
			return 0;

		float hue;

		if(M == r) {
			hue = (g-b)/Chroma;
			if(hue < 0)
				hue += 6.f;
		}
		else if(M == g) {
			hue = 2.f + (b-r)/Chroma;
		}
		else { //M == b
			hue = 4.f + (r-g)/Chroma;
		}

		return hue * 60.f;
	}

	//Sets this color to the RGB[0,1] representation of the HSV values
	//Alpha is unaffected
	//Hue must be in [0,360)
	void fromHSV(float hue, float saturation, float value) {
		//Generate necessary values
		float Chroma = saturation * value;
		float X = Chroma * (1.f - fabs(fmod(hue/60.f,2.f) - 1.f));
		float m = value - Chroma;

		//Correct color ranges and set channels to the maximal value
		Chroma += m;
		X += m;
		
		r = Chroma;
		g = Chroma;
		b = Chroma;

		//Pick the lower channels according to the hue
		unsigned h = unsigned(hue/60.f);
		switch(h) {
		case 0:
			g=X; b=m; break;
		case 1:
			r=X; b=m; break;
		case 2:
			b=X; r=m; break;
		case 3:
			g=X; r=m; break;
		case 4:
			r=X; g=m; break;
		case 5:
			b=X; g=m; break;
		}
	}
};
