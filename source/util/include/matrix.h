#pragma once
#include "constants.h"
#include <memory.h>
#include "vec3.h"
#include "vec4.h"

const double _identityMatrixData[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};

//A 4x4 Matrix
struct Matrix {
	double m[16];

	void setScale(vec3<double>& scale) {
		m[0] = scale.x;
		m[5] = scale.y;
		m[10] = scale.z;
	}

	void scaleUniformly(double scale) {
		m[0] *= scale; m[4] *= scale; m[8] *= scale;
		m[1] *= scale; m[5] *= scale; m[9] *= scale;
		m[2] *= scale; m[6] *= scale; m[10] *= scale;
	}

	void setTranslation(vec3<double>& translation) {
		m[12] = translation.x;
		m[13] = translation.y;
		m[14] = translation.z;
	}

	vec3<double> getTranslation() const {
		return vec3<double>(m[12],m[13],m[14]);
	}

	double& operator[](unsigned i) {
		return m[i];
	}

	const double& operator[](unsigned i) const {
		return m[i];
	}

	void operator=(const Matrix& b) {
		memcpy(m, b.m, sizeof(m));
	}

	template<class T>
	vec3<T> rotate(const vec3<T>& b) const {
		vec3<T> r;
		r.x= (m[0]*b.x) + (m[4]*b.y) + (m[8]*b.z);
		r.y= (m[1]*b.x) + (m[5]*b.y) + (m[9]*b.z);
		r.z= (m[2]*b.x) + (m[6]*b.y) + (m[10]*b.z);
		return r;
	}
	
	template<class T>
	vec3<T> operator*(const vec3<T>& b) const {
		vec3<T> r;
		r.x= (m[0]*b.x) + (m[4]*b.y) + (m[8]*b.z) + m[12];
		r.y= (m[1]*b.x) + (m[5]*b.y) + (m[9]*b.z) + m[13];
		r.z= (m[2]*b.x) + (m[6]*b.y) + (m[10]*b.z) + m[14];
		return r;
	}
	
	template<class T>
	vec4<T> operator*(const vec4<T>& b) const {
		vec4<T> r;
		r.x= (m[0]*b.x) + (m[4]*b.y) + (m[8]*b.z) + (m[12]*b.w);
		r.y= (m[1]*b.x) + (m[5]*b.y) + (m[9]*b.z) + (m[13]*b.w);
		r.z= (m[2]*b.x) + (m[6]*b.y) + (m[10]*b.z) + (m[14]*b.w);
		r.w= (m[2]*b.x) + (m[6]*b.y) + (m[10]*b.z) + (m[15]*b.w);
		return r;
	}

	Matrix operator*(const Matrix& b) const {
		Matrix r;
		r[0]= (m[0]*b[0]) + (m[4]*b[1]) + (m[8]*b[2]) + (m[12]*b[3]);
		r[1]= (m[1]*b[0]) + (m[5]*b[1]) + (m[9]*b[2]) + (m[13]*b[3]);
		r[2]= (m[2]*b[0]) + (m[6]*b[1]) + (m[10]*b[2]) + (m[14]*b[3]);
		r[3]= (m[3]*b[0]) + (m[7]*b[1]) + (m[11]*b[2]) + (m[15]*b[3]);

		r[4]= (m[0]*b[4]) + (m[4]*b[5]) + (m[8]*b[6]) + (m[12]*b[7]);
		r[5]= (m[1]*b[4]) + (m[5]*b[5]) + (m[9]*b[6]) + (m[13]*b[7]);
		r[6]= (m[2]*b[4]) + (m[6]*b[5]) + (m[10]*b[6]) + (m[14]*b[7]);
		r[7]= (m[3]*b[4]) + (m[7]*b[5]) + (m[11]*b[6]) + (m[15]*b[7]);

		r[8]=  (m[0]*b[8]) + (m[4]*b[9]) + (m[8]*b[10]) + (m[12]*b[11]);
		r[9]=  (m[1]*b[8]) + (m[5]*b[9]) + (m[9]*b[10]) + (m[13]*b[11]);
		r[10]= (m[2]*b[8]) + (m[6]*b[9]) + (m[10]*b[10]) + (m[14]*b[11]);
		r[11]= (m[3]*b[8]) + (m[7]*b[9]) + (m[11]*b[10]) + (m[15]*b[11]);

		r[12]= (m[0]*b[12]) + (m[4]*b[13]) + (m[8]*b[14]) + (m[12]*b[15]);
		r[13]= (m[1]*b[12]) + (m[5]*b[13]) + (m[9]*b[14]) + (m[13]*b[15]);
		r[14]= (m[2]*b[12]) + (m[6]*b[13]) + (m[10]*b[14]) + (m[14]*b[15]);
		r[15]= (m[3]*b[12]) + (m[7]*b[13]) + (m[11]*b[14]) + (m[15]*b[15]);
		return r;
	}

	Matrix& operator*=(const Matrix& b) {
		*this = *this * b;
		return *this;
	}

	Matrix() {
		memcpy(m, _identityMatrixData, sizeof(_identityMatrixData));
	}

	Matrix(const Matrix& b) {
		memcpy(m, b.m, sizeof(m));
	}

	static Matrix projection(double fov, double aspect, double znear, double zfar) {
		double ymax = znear * tan(fov * pi / 360.0);
		double xmax = ymax * aspect;

		double w = xmax + xmax;
		double h = ymax + ymax;

		Matrix m;
		m[0] = (2.0 * znear) / w;
		//m[1] = 0;
		//m[2] = 0;
		//m[3] = 0;

		//m[4] = 0;
		m[5] = (2.0 * znear) / h;
		//m[6] = 0;
		//m[7] = 0;

		//m[8] = 0;
		//m[9] = 0;
		m[10] = (-zfar - znear) / (zfar - znear);
		m[11] = -1.0;

		//m[12] = 0;
		//m[13] = 0;
		m[14] = (-2.0 * znear * zfar) / (zfar - znear);
		m[15] = 0;

		return m;
	}
};
