#pragma once
#include "vec2.h"
#include <algorithm>

template<class T>
T _clip(T v, T s, T x1, T x2, T w) {
	// -_-
	return (T)(w > 0 ? (double)v+(((double)x2 - (double)x1)/(double)w)*(double)s : (double)v);
}

//Generic rectangle
template<class T>
struct rect {
	vec2<T> topLeft;
	vec2<T> botRight;

	rect() {}
	rect(vec2<T> a, vec2<T> b) :
		topLeft(a), botRight(b) {}
	rect(T x1, T y1, T x2, T y2) :
		topLeft(x1, y1), botRight(x2, y2) {}

	template<class Q>
	rect(const rect<Q>& other) {
		topLeft.x = (T)other.topLeft.x;
		topLeft.y = (T)other.topLeft.y;
		botRight.x = (T)other.botRight.x;
		botRight.y = (T)other.botRight.y;
	}

	static rect<T> area(T x, T y, T w, T h) {
		return rect<T>(x, y, x+w, y+h);
	}

	static rect<T> area(const vec2<T> pos, const vec2<T> size) {
		return rect<T>(pos.x, pos.y, pos.x+size.width, pos.y+size.height);
	}

	static rect<T> centered(const vec2<T> around, const vec2<T> size) {
		return area(around.x - size.x/2, around.y - size.y/2, size.width, size.height);
	}

	static rect<T> centered(const rect<T>& within, const vec2<T> size) {
		return centered( vec2<T>((within.topLeft.x + within.botRight.x) / 2, (within.topLeft.y + within.botRight.y) / 2), size);
	}

	bool operator==(const rect& other) {
		return topLeft == other.topLeft && botRight == other.botRight;
	}

	rect& operator=(const rect& other) {
		topLeft = other.topLeft;
		botRight = other.botRight;
		return *this;
	}

	rect& operator+=(const vec2<T>& other) {
		topLeft += other;
		botRight += other;
		return *this;
	}

	rect operator+(const vec2<T>& other) const {
		return rect(topLeft+other, botRight+other);
	}

	rect& operator-=(const vec2<T>& other) {
		topLeft -= other;
		botRight -= other;
		return *this;
	}

	rect operator-(const vec2<T>& other) const {
		return rect(topLeft-other, botRight-other);
	}
	
	vec2<T> getSize() const {
		return botRight - topLeft;
	}

	T getWidth() const {
		return botRight.x - topLeft.x;
	}

	T getHeight() const {
		return botRight.y - topLeft.y;
	}

	vec2<T> getBotLeft() const {
		return vec2<T>(topLeft.x, botRight.y);
	}

	vec2<T> getTopRight() const {
		return vec2<T>(botRight.x, topLeft.y);
	}

	rect<T> interpolate(const rect<T>& other, double pct) const {
		return rect<T>(
			topLeft.x + (T)((double)(other.topLeft.x - topLeft.x) * pct),
			topLeft.y + (T)((double)(other.topLeft.y - topLeft.y) * pct),
			botRight.x + (T)((double)(other.botRight.x - botRight.x) * pct),
			botRight.y + (T)((double)(other.botRight.y - botRight.y) * pct) );
	}

	vec2<T> getCenter() const {
		return vec2<T>(
			topLeft.x + (botRight.x - topLeft.x) / 2,
			topLeft.y + (botRight.y - topLeft.y) / 2
		);
	}

	float distanceTo(const vec2<T>& pos) {
		if(pos.x < topLeft.x) {
			if(pos.y < topLeft.y) {
				//Distance to top left corner
				float xdist = float(topLeft.x - pos.x);
				float ydist = float(topLeft.y - pos.y);
				return sqrt(xdist*xdist + ydist*ydist);
			}
			else if(pos.y > botRight.y) {
				//Distance to bottom left corner
				float xdist = float(topLeft.x - pos.x);
				float ydist = float(botRight.y - pos.y);
				return sqrt(xdist*xdist + ydist*ydist);
			}
			else {
				//Distance to left edge
				float xdist = float(topLeft.x - pos.x);
				return xdist;
			}
		}
		else if(pos.x > botRight.x) {
			if(pos.y < topLeft.y) {
				//Distance to top right corner
				float xdist = float(botRight.x - pos.x);
				float ydist = float(topLeft.y - pos.y);
				return sqrt(xdist*xdist + ydist*ydist);
			}
			else if(pos.y > botRight.y) {
				//Distance to bottom right corner
				float xdist = float(botRight.x - pos.x);
				float ydist = float(botRight.y - pos.y);
				return sqrt(xdist*xdist + ydist*ydist);
			}
			else {
				//Distance to right edge
				float xdist = float(pos.x - botRight.x);
				return xdist;
			}
		}
		else {
			if(pos.y < topLeft.y) {
				//Distance to top edge
				float ydist = float(topLeft.y - pos.y);
				return ydist;
			}
			else if(pos.y > botRight.y) {
				//Distance to bottom edge
				float ydist = float(pos.y - botRight.y);
				return ydist;
			}
			else {
				//Inside rectangle
				return 0.f;
			}
		}
	}

	bool isWithin(const vec2<T>& pos) const {
		return pos.x >= topLeft.x && pos.y >= topLeft.y
			&& pos.x < botRight.x && pos.y < botRight.y;
	}

	bool isRectInside(const rect<T>& other) const {
		return ((other.topLeft.x >= topLeft.x && other.topLeft.x < botRight.x)
			&& (other.botRight.x >= topLeft.x && other.botRight.x < botRight.x))
			&& ((other.topLeft.y >= topLeft.y && other.topLeft.y < botRight.y)
			&& (other.botRight.y >= topLeft.y && other.botRight.y < botRight.y));
	}

	bool overlaps(const rect<T>& other) const {
		return topLeft.x < other.botRight.x && botRight.x > other.topLeft.x
			&& topLeft.y < other.botRight.y && botRight.y > other.topLeft.y;
	}

	bool empty() const {
		return botRight.x == topLeft.x && botRight.y == topLeft.y;
	}

	rect<T> padded(T padding) const {
		return rect<T>(topLeft.x + padding, topLeft.y + padding,
				botRight.x - padding, botRight.y - padding);
	}

	rect<T> padded(T horiz, T vert) const {
		return rect<T>(topLeft.x + horiz, topLeft.y + vert,
				botRight.x - horiz, botRight.y - vert);
	}

	rect<T> padded(T x1, T y1, T x2, T y2) const {
		return rect<T>(topLeft.x + x1, topLeft.y + y1,
				botRight.x - x2, botRight.y - y2);
	}

	rect<T> resized(T w = 0, T h = 0, double horizAlign = 0.0, double vertAlign = 0.0) const {
		rect<T> result = *this;
		if(w != 0) {
			double width = getWidth();
			double diff = (width - w);
			result.topLeft.x += (T)(diff * horizAlign);
			result.botRight.x -= (T)(diff * (1.0 - horizAlign));
		}

		if(h != 0) {
			double height = getHeight();
			double diff = (height - h);
			result.topLeft.y += (T)(diff * vertAlign);
			result.botRight.y -= (T)(diff * (1.0 - vertAlign));
		}
		return result;
	}

	rect<T> aspectAligned(double aspect, double horizAlign = 0.5, double vertAlign = 0.5) {
		double height = getHeight();
		double width = getWidth();

		double aspectWidth = height * aspect;
		double aspectHeight = width / aspect;

		rect<T> result = *this;

		if(aspectWidth < width) {
			double diff = (width - aspectWidth);
			result.topLeft.x += (T)(diff * horizAlign);
			result.botRight.x -= (T)(diff * (1.0 - horizAlign));
		}
		else if(aspectHeight < height) {
			double diff = (height - aspectHeight);
			result.topLeft.y += (T)(diff * vertAlign);
			result.botRight.y -= (T)(diff * (1.0 - vertAlign));
		}

		return result;
	}

	rect<T> clipAgainst(const rect<T>& other) const {
		return rect<T>(
			std::max(topLeft.x, other.topLeft.x),
			std::max(topLeft.y, other.topLeft.y),
			std::min(botRight.x, other.botRight.x),
			std::min(botRight.y, other.botRight.y));
	}

	rect<T> clipProportional(const rect<T>& from, const rect<T>& to) const {
		vec2<T> size = getSize();
		vec2<T> otherSize = from.getSize();

		return rect<T>(
			_clip(topLeft.x, size.width, from.topLeft.x, to.topLeft.x, otherSize.width),
			_clip(topLeft.y, size.height, from.topLeft.y, to.topLeft.y, otherSize.height),
			_clip(botRight.x, size.width, from.botRight.x, to.botRight.x, otherSize.width),
			_clip(botRight.y, size.height, from.botRight.y, to.botRight.y, otherSize.height));
	}
};

typedef rect<int> recti;
typedef rect<float> rectf;
typedef rect<double> rectd;

//Relative position specifier
enum RelativePositionType {
	RPT_Left,
	RPT_Right,
	RPT_Top = RPT_Left,
	RPT_Bottom = RPT_Right,
};

template<class T>
struct relpos {
	RelativePositionType type;
	T pos;
	double percent;

	relpos() : type(RPT_Left), pos(0), percent(0.0) {
	}

	void set(RelativePositionType Type, T Pos, double Percent) {
		type = Type;
		pos = Pos;
		percent = Percent;
	}

	void setOffset(T value) {
		pos = value;
	}

	void setPercentage(double value) {
		percent = value;
	}

	T evaluate(T from, T to) const {
		T rp;
		switch(type) {
			default:
			case RPT_Left:
				rp = from + pos + (T)((double)(to - from) * percent);
			break;
			case RPT_Right:
				rp = to - pos - (T)((double)(to - from) * percent);
			break;
		}
		return rp;
	}
};

typedef relpos<int> relposi;
typedef relpos<float> relposf;
typedef relpos<double> relposd;

//Relative position rectangle
template<class T>
struct relrect {
	relpos<T> left, top;
	relpos<T> right, bottom;

	relrect() {
		right.type = RPT_Right;
		bottom.type = RPT_Bottom;
	}

	recti evaluate(const recti& pos) const {
		recti out;

		out.topLeft.x = left.evaluate(pos.topLeft.x, pos.botRight.x);
		out.topLeft.y = top.evaluate(pos.topLeft.y, pos.botRight.y);

		out.botRight.x = right.evaluate(pos.topLeft.x, pos.botRight.x);
		out.botRight.y = bottom.evaluate(pos.topLeft.y, pos.botRight.y);

		return out;
	}
};

typedef relrect<int> relrecti;
typedef relrect<float> relrectf;
typedef relrect<double> relrectd;
