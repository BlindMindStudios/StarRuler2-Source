#pragma once
#include <math.h>

#if defined(_MSC_VER) && defined(_M_AMD64)
#include <emmintrin.h>
#endif

//3 Dimensional Vector structure
template<class T = double>
struct vec3 {
	T x,y,z;
	
	vec3() : x(0), y(0), z(0) {}
	explicit vec3(T def) : x(def), y(def), z(def) {}
	explicit vec3(T X, T Y, T Z) : x(X), y(Y), z(Z) {}

	template<class O>
	explicit vec3(const vec3<O>& other) : x((T)other.x), y((T)other.y), z((T)other.z) {}
	
	static vec3 up(T len = (T)1.0) { return vec3(0,len,0); }
	static vec3 front(T len = (T)1.0) { return vec3(len,0,0); }
	static vec3 right(T len = (T)1.0) { return vec3(0,0,-len); }

#if defined(_MSC_VER) && defined(_M_AMD64)

	double distanceTo(const vec3& other) const {
        __m128d reg0 = _mm_set_sd(x), reg1 = _mm_set_sd(other.x);
        reg0 = _mm_sub_sd(reg0, reg1);
		__m128d reg2 = _mm_set_sd(y);
		reg0 = _mm_mul_sd(reg0, reg0);
		reg1 = _mm_set_sd(other.y);
		reg1 = _mm_sub_sd(reg2, reg1);
		__m128d reg3 = _mm_set_sd(z);
		reg1 = _mm_mul_sd(reg1, reg1);
		reg2 = _mm_set_sd(other.z);
		reg0 = _mm_add_sd(reg0, reg1);
		reg2 = _mm_sub_sd(reg3, reg2);
		reg2 = _mm_mul_sd(reg2, reg2);
		reg0 = _mm_add_sd(reg0, reg2);
		reg0 = _mm_sqrt_sd(reg0, reg0);
        return reg0.m128d_f64[0];
	}

	double distanceToSQ(const vec3& other) const {
        __m128d reg0 = _mm_set_sd(x), reg1 = _mm_set_sd(other.x);
        reg0 = _mm_sub_sd(reg0, reg1);
		__m128d reg2 = _mm_set_sd(y);
		reg0 = _mm_mul_sd(reg0, reg0);
		reg1 = _mm_set_sd(other.y);
		reg1 = _mm_sub_sd(reg2, reg1);
		__m128d reg3 = _mm_set_sd(z);
		reg1 = _mm_mul_sd(reg1, reg1);
		reg2 = _mm_set_sd(other.z);
		reg0 = _mm_add_sd(reg0, reg1);
		reg2 = _mm_sub_sd(reg3, reg2);
		reg2 = _mm_mul_sd(reg2, reg2);
		reg0 = _mm_add_sd(reg0, reg2);
        return reg0.m128d_f64[0];
	}

	T getLength() const {
        __m128d reg0 = _mm_set_sd(x);
		reg0 = _mm_mul_sd(reg0, reg0);
		__m128d reg1 = _mm_set_sd(y);
		reg1 = _mm_mul_sd(reg1, reg1);
		__m128d reg2 = _mm_set_sd(z);
		reg2 = _mm_mul_sd(reg2, reg2);
		reg0 = _mm_add_sd(reg0, reg1);
		reg0 = _mm_add_sd(reg0, reg2);
		reg0 = _mm_sqrt_sd(reg0, reg0);
        return reg0.m128d_f64[0];
	}

	T getLengthSQ() const {
        __m128d reg0 = _mm_set_sd(x);
		reg0 = _mm_mul_sd(reg0, reg0);
		__m128d reg1 = _mm_set_sd(y);
		reg1 = _mm_mul_sd(reg1, reg1);
		__m128d reg2 = _mm_set_sd(z);
		reg2 = _mm_mul_sd(reg2, reg2);
		reg0 = _mm_add_sd(reg0, reg1);
		reg0 = _mm_add_sd(reg0, reg2);
        return reg0.m128d_f64[0];
	}

	double dot(const vec3& other) const {
        __m128d reg0 = _mm_set_sd(x), reg1 = _mm_set_sd(other.x);
        reg0 = _mm_mul_sd(reg0, reg1);
		__m128d reg2 = _mm_set_sd(y);
		reg1 = _mm_set_sd(other.y);
		reg1 = _mm_mul_sd(reg2, reg1);
		__m128d reg3 = _mm_set_sd(z);
		reg0 = _mm_add_sd(reg0, reg1);
		reg2 = _mm_set_sd(other.z);
		reg2 = _mm_mul_sd(reg3, reg2);
		reg0 = _mm_add_sd(reg0, reg2);
        return reg0.m128d_f64[0];
	}
#else

	double distanceTo(const vec3& other) const {
		double tx = x-other.x,
		  ty = y-other.y,
		  tz = z-other.z;
		return sqrt((tx*tx)+(ty*ty)+(tz*tz));
	}

	double distanceToSQ(const vec3& other) const {
		double tx = x-other.x,
		  ty = y-other.y,
		  tz = z-other.z;
		return ((tx*tx)+(ty*ty)+(tz*tz));
	}

	T getLength() const {
		return (T)sqrt((double)(x*x)+(double)(y*y)+(double)(z*z));
	}

	T getLengthSQ() const {
		return (x*x)+(y*y)+(z*z);
	}

	double dot(const vec3& other) const {
		return (double(x)*double(other.x)) + (double(y)*double(other.y)) + (double(z)*double(other.z));
	}
#endif

	double angleDistance(const vec3& other) const {
		double _dot = dot(other);
		if(_dot < -1.0)
			_dot = -1.0;
		else if(_dot > 1.0)
			_dot = 1.0;

		return acos(_dot);
	}

	vec3 cross(const vec3& other) const {
		return vec3(
			(y*other.z)-(z*other.y),
			(z*other.x)-(x*other.z),
			(x*other.y)-(y*other.x) );
	}

	vec3 operator+(const vec3& other) const {
		return vec3(x+other.x, y+other.y, z+other.z);
	}

	vec3& operator+=(const vec3& other) {
		x += other.x;
		y += other.y;
		z += other.z;
		return *this;
	}

	vec3 operator-() const {
		return vec3(-x, -y, -z);
	}

	vec3 operator-(const vec3& other) const {
		return vec3(x-other.x, y-other.y, z-other.z);
	}

	vec3& operator-=(const vec3& other) {
		x -= other.x;
		y -= other.y;
		z -= other.z;
		return *this;
	}

	vec3 operator*(const vec3& other) const {
		return vec3(x*other.x, y*other.y, z*other.z);
	}

	vec3 operator*(double scalar) const {
		return vec3(T((double)x*scalar), T((double)y*scalar), T((double)z*scalar));
	}

	vec3& operator*=(double scalar) {
		x = T((double)x * scalar);
		y = T((double)y * scalar);
		z = T((double)z * scalar);
		return *this;
	}

	vec3 operator/(double scalar) const {
		return vec3(T((double)x/scalar), T((double)y/scalar), T((double)z/scalar));
	}

	vec3& operator/=(double scalar) {
		x = T((double)x / scalar);
		y = T((double)y / scalar);
		z = T((double)z / scalar);
		return *this;
	}

	vec3& operator=(const vec3& other) {
		x = other.x;
		y = other.y;
		z = other.z;
		return *this;
	}

	bool operator==(const vec3& other) const {
		return x == other.x && y == other.y && z == other.z;
	}

	bool operator!=(const vec3& other) const {
		return x != other.x || y != other.y || z != other.z;
	}

	vec3 interpolate(const vec3& other, double pct) const {
		return *this + (other - *this) * pct;
	}

	//Spherically interpolate between normalized vectors
	vec3 slerp(const vec3& other, double pct) const {
		if(pct >= 1.0)
			return other;
		if(pct <= 0.0)
			return *this;

		double _dot = dot(other);
		if(_dot > 0.999)
			return interpolate(other, pct);
		if(_dot <= -1.0) {
			//Normally this would reduce to lerp, but we know we want to rotate in some direction instead
			// We find a vector perpendicular to our endpoints and interpolate based on our progress
			vec3 temp = cross(vec3::up());
			if(temp.zero())
				return other;
			else if(pct < 0.5)
				return slerp(temp, pct * 2.0);
			else
				return temp.slerp(other, (pct - 0.5) * 2.0);
		}

		double omega = acos(_dot);
		if(omega < 0.001)
			return interpolate(other, pct);

		double sinOmg = sin(omega);
		return ((*this * sin((1.0 - pct)*omega)/sinOmg) + (other * sin(pct * omega)/sinOmg)).normalized();
	}

	vec3& normalize(T length = (T)1.0) {
		double X = x, Y = y, Z = z,
			L = (X*X)+(Y*Y)+(Z*Z);
		if(L == 0.0)
			return *this;
		L = (double)length / sqrt(L);

		x = (T)(X*L);
		y = (T)(Y*L);
		z = (T)(Z*L);
		return *this;
	}

	vec3 normalized(T length = (T)1.0) const {
		vec3 temp(*this);
		temp.normalize(length);
		return temp;
	}

	void set(T X, T Y, T Z) {
		x = X;
		y = Y;
		z = Z;
	}

	vec3<T> elementMax(const vec3<T>& other) const {
		return vec3<T>(
			x > other.x ? x : other.x,
			y > other.y ? y : other.y,
			z > other.z ? z : other.z);
	}

	vec3<T> elementMin(const vec3<T>& other) const {
		return vec3<T>(
			x < other.x ? x : other.x,
			y < other.y ? y : other.y,
			z < other.z ? z : other.z);
	}

	bool zero() {
		return x == 0.0 && y == 0.0 && z == 0.0;
	}
};

typedef vec3<float> vec3f;
typedef vec3<double> vec3d;
typedef vec3<int> vec3i;
