#pragma once

//4 Dimensional Vector structure
template<class T = double>
struct vec4 {
	T x,y,z,w;
	
	vec4() : x(0), y(0), z(0), w(0) {}
	vec4(T def) : x(def), y(def), z(def), w(def) {}
	vec4(T X, T Y, T Z, T W) : x(X), y(Y), z(Z), w(W) {}

	template<class O>
	explicit vec4(const vec4<O>& other) : x((T)other.x), y((T)other.y), z((T)other.z), w((T)other.w) {}
	
	vec4& operator=(const vec4& other) {
		x = other.x;
		y = other.y;
		z = other.z;
		w = other.w;
		return *this;
	}

	bool operator==(const vec4& other) {
		return x == other.x && y == other.y && z == other.z && w == other.w;
	}

	vec4 operator*(T scalar) const {
		return vec4(x * scalar, y * scalar, z * scalar, w * scalar);
	}

	vec4& operator+=(const vec4& other) {
		x += other.x;
		y += other.y;
		z += other.z;
		w += other.w;
		return *this;
	}

	bool zero() {
		return x == 0.0 && y == 0.0 && z == 0.0 && w == 0.0;
	}
};

typedef vec4<float> vec4f;
typedef vec4<double> vec4d;
typedef vec4<int> vec4i;
