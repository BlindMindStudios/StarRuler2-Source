#pragma once
#include <math.h>
#include "constants.h"

template<class T>
struct vec2 {
	union {
		T x;
		T width;
	};

	union {
		T y;
		T height;
	};

	double distanceTo(const vec2<T>& other) const {
		double tX = (double)(other.x - x);
		double tY = (double)(other.y - y);

		return sqrt((tX * tX)+(tY * tY));
	}

	double distanceToSQ(const vec2<T>& other) const {
		double tX = (double)(other.x - x);
		double tY = (double)(other.y - y);

		return (tX * tX)+(tY * tY);
	}

	double length() const {
		double dx = (double)x;
		double dy = (double)y;
		return sqrt((dx*dx) + (dy*dy));
	}

	double lengthSQ() const {
		double dx = (double)x;
		double dy = (double)y;
		return (dx*dx) + (dy*dy);
	}

	vec2 operator*(double scalar) const {
		return vec2<T>((T)((double)x * scalar), (T)((double)y * scalar));
	}

	vec2& operator*=(double scalar) {
		x = (T)((double)x * scalar);
		y = (T)((double)y * scalar);
		return *this;
	}

	vec2 operator/(double scalar) const {
		return vec2<T>((T)((double)x / scalar), (T)((double)y / scalar));
	}

	vec2& operator/=(double scalar) {
		x = (T)((double)x / scalar);
		y = (T)((double)y / scalar);
		return *this;
	}

	vec2 operator+(const vec2& other) const {
		return vec2(x+other.x, y+other.y);
	}

	vec2& operator+=(const vec2& other) {
		x += other.x;
		y += other.y;
		return *this;
	}

	vec2 operator-() const {
		return vec2(-x, -y);
	}

	vec2 operator-(const vec2& other) const {
		return vec2(x-other.x, y-other.y);
	}

	vec2& operator-=(const vec2& other) {
		x -= other.x;
		y -= other.y;
		return *this;
	}

	vec2& operator=(const vec2& other) {
		x = other.x;
		y = other.y;
		return *this;
	}

	void set(T X, T Y) {
		x = X;
		y = Y;
	}

	bool operator==(const vec2& other) const {
		return x == other.x && y == other.y;
	}

	bool operator!=(const vec2& other) const {
		return x != other.x || y != other.y;
	}

	double radians() const {
		return atan2((double)y, (double)x);
	}

	vec2& normalize(T length = (T)1.0) {
		double X = x, Y = y,
			L = (X*X)+(Y*Y);
		if(L == 0.0)
			return *this;
		L = (double)length / sqrt(L);

		x = (T)(X*L);
		y = (T)(Y*L);
		return *this;
	}

	vec2 normalized(T length = (T)1.0) const {
		vec2 temp(*this);
		temp.normalize(length);
		return temp;
	}

	double dot(const vec2& other) const {
		return (double)x*(double)other.x + (double)y*(double)other.y;
	}

	vec2& rotate(double radians) {
		double c = cos(radians), s = sin(radians);

		double nX = (double)x * c - (double)y * s;
		double nY = (double)y * c + (double)x * s;

		x = (T)nX;
		y = (T)nY;

		return *this;
	}

	vec2 rotated(double radians) {
		double c = cos(radians), s = sin(radians);

		double nX = (double)x * c - (double)y * s;
		double nY = (double)y * c + (double)x * s;

		return vec2((T)nX, (T)nY);
	}

	double getRotation(const vec2& other) const {
		double from = radians() + twopi;
		double to = other.radians() + twopi;
		double diff = (to - from);
		if(diff < 0)
			diff = twopi + diff;
		return diff;
	}

	vec2() : x(0), y(0) {}
	explicit vec2(T def) : x(def), y(def) {}
	explicit vec2(T X, T Y) : x(X), y(Y) {}

	template<class Q>
	vec2(const vec2<Q>& other)
		: x((T)other.x), y((T)other.y) {}
};

typedef vec2<double> vec2d;
typedef vec2<float> vec2f;
typedef vec2<int> vec2i;
typedef vec2<unsigned> vec2u;
