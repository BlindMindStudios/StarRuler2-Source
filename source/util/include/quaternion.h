#pragma once
#include <math.h>
#include "vec3.h"
#include "matrix.h"

//4 Dimensional Vector structure
template<class T = double>
struct quaternion {
	vec3<T> xyz;
	T w;

	quaternion operator*(const quaternion& o) const {
		return quaternion(
			o.xyz*w + xyz*o.w + xyz.cross(o.xyz),
			(T)((double)(w*o.w) - xyz.dot(o.xyz))
			);
	}

	quaternion& operator*=(const quaternion& o) {
		*this = *this * o;
		return *this;
	}

	vec3<T> operator*(const vec3<T>& p) const {
		return (*this * quaternion(p,0) * inverted()).xyz;
	}

	bool operator==(const quaternion& other) const {
		return xyz == other.xyz && w == other.w;
	}

	quaternion inverted() const {
		return quaternion(-xyz, w);
	}

	quaternion& normalize(T len = 1) {
		double L = double(xyz.getLengthSQ()) + double(w)*double(w);
		if(L == 0 || L == len)
			return *this;
		L = 1.0/sqrt(L);
		xyz *= (T)L;
		w *= (T)L;
		return *this;
	}

	double dot(const quaternion& other) const {
		return xyz.dot(other.xyz) + w*other.w;
	}

	//Spherical Linear Interpolation
	//Note: Both quaternions must be unit quaternions
	quaternion slerp(const quaternion& other, T percent) const {
		if(percent <= 0.0)
			return *this;
		else if(percent >= 1.0)
			return other;

		double _dot = dot(other);
		double omega = acos(_dot);

		quaternion from;
		if(_dot < 0.0) {
			omega = -omega;
			from = quaternion(-xyz.x, -xyz.y, -xyz.z, -w);
		}
		else {
			from = *this;
		}

		if(omega > 0.001) {
			T sinOmega = (T)sin(omega);

			T p0 = (T)sin((1 - percent)*omega)/sinOmega, p1 = (T)sin(percent*omega)/sinOmega;

			quaternion ret;
			ret.xyz = (from.xyz * p0) + (other.xyz * p1);
			ret.w = (from.w * p0) + (other.w * p1);

			return ret.normalize();
		}
		else {
			T p0 = (1 - percent), p1 = percent;

			quaternion ret;
			ret.xyz = (from.xyz * p0) + (other.xyz * p1);
			ret.w = (from.w * p0) + (other.w * p1);

			return ret.normalize();
		}
	}

	void toMatrix(Matrix& mat) const {
		double X = xyz.x, Y = xyz.y, Z = xyz.z, W = -w;
		double Xsq = X*X, Ysq = Y*Y, Zsq = Z*Z, Wsq = W*W;

		double XY = X*Y, XZ = X*Z, WX = X*W,
			   YZ = Y*Z, WY = Y*W, WZ = W*Z;

		mat[0] = Wsq + Xsq - Ysq - Zsq;
		mat[1] = 2.0 * (XY - WZ);
		mat[2] = 2.0 * (XZ + WY);
		mat[3] = 0;
		mat[4] = 2.0 * (XY + WZ);
		mat[5] = Wsq - Xsq + Ysq - Zsq;
		mat[6] = 2.0 * (YZ - WX);
		mat[7] = 0;
		mat[8] = 2.0 * (XZ - WY);
		mat[9] = 2.0 * (YZ + WX);
		mat[10] = Wsq - Xsq - Ysq + Zsq;
		mat[11] = 0;
		mat[12] = 0;
		mat[13] = 0;
		mat[14] = 0;
		mat[15] = Wsq + Xsq + Ysq + Zsq;
	}

	void toTransform(Matrix& mat, const vec3<T>& translation, const double scale) const {
		const double X = xyz.x, Y = xyz.y, Z = xyz.z, W = -w;
		const double Xsq = X*X, Ysq = Y*Y, Zsq = Z*Z, Wsq = W*W;

		const double XY = X*Y, XZ = X*Z, WX = X*W,
			   YZ = Y*Z, WY = Y*W, WZ = W*Z;

		const double commonFactor = 2.0 * scale;

		mat[0] = scale * (Wsq + Xsq - Ysq - Zsq);
		mat[1] = commonFactor * (XY - WZ);
		mat[2] = commonFactor * (XZ + WY);
		mat[3] = 0;
		mat[4] = commonFactor * (XY + WZ);
		mat[5] = scale * (Wsq - Xsq + Ysq - Zsq);
		mat[6] = commonFactor * (YZ - WX);
		mat[7] = 0;
		mat[8] = commonFactor * (XZ - WY);
		mat[9] = commonFactor * (YZ + WX);
		mat[10] = scale * (Wsq - Xsq - Ysq + Zsq);
		mat[11] = 0;
		mat[12] = translation.x;
		mat[13] = translation.y;
		mat[14] = translation.z;
		mat[15] = Wsq + Xsq + Ysq + Zsq;
	}

	void toTransform(Matrix& mat, const vec3<T>& translation, const vec3<T>& scale) const {
		const double X = xyz.x, Y = xyz.y, Z = xyz.z, W = -w;
		const double Xsq = X*X, Ysq = Y*Y, Zsq = Z*Z, Wsq = W*W;

		const double XY = X*Y, XZ = X*Z, WX = X*W,
			   YZ = Y*Z, WY = Y*W, WZ = W*Z;

		mat[0] = scale.x * (Wsq + Xsq - Ysq - Zsq);
		mat[1] = (2.0 * scale.x) * (XY - WZ);
		mat[2] = (2.0 * scale.x) * (XZ + WY);
		mat[3] = 0;
		mat[4] = (2.0 * scale.y) * (XY + WZ);
		mat[5] = scale.y * (Wsq - Xsq + Ysq - Zsq);
		mat[6] = (2.0 * scale.y) * (YZ - WX);
		mat[7] = 0;
		mat[8] = (2.0 * scale.z) * (XZ - WY);
		mat[9] = (2.0 * scale.z) * (YZ + WX);
		mat[10] = scale.z * (Wsq - Xsq - Ysq + Zsq);
		mat[11] = 0;
		mat[12] = translation.x;
		mat[13] = translation.y;
		mat[14] = translation.z;
		mat[15] = Wsq + Xsq + Ysq + Zsq;
	}

	Matrix toMatrix() const {
		double X = xyz.x, Y = xyz.y, Z = xyz.z, W = -w;
		double Xsq = X*X, Ysq = Y*Y, Zsq = Z*Z, Wsq = W*W;

		double XY = X*Y, XZ = X*Z, WX = X*W,
			   YZ = Y*Z, WY = Y*W, WZ = W*Z;

		Matrix temp;
		temp[0] = Wsq + Xsq - Ysq - Zsq;
		temp[1] = 2.0 * (XY - WZ);
		temp[2] = 2.0 * (XZ + WY);
		//3 = 0
		temp[4] = 2.0 * (XY + WZ);
		temp[5] = Wsq - Xsq + Ysq - Zsq;
		temp[6] = 2.0 * (YZ - WX);
		//7 = 0
		temp[8] = 2.0 * (XZ - WY);
		temp[9] = 2.0 * (YZ + WX);
		temp[10] = Wsq - Xsq - Ysq + Zsq;
		//8-14 = 0
		temp[15] = Wsq + Xsq + Ysq + Zsq;

		return temp;
	}

	//Builds a rotation quaternion from the rotation <Angle> radians about the <Axis>
	static quaternion fromAxisAngle(const vec3<T>& Axis, T Angle) {
		return quaternion(Axis * sin(Angle * (T)0.5), cos(Angle * (T)0.5));
	}

	//Builds a rotation that rotates <From> into the direction of <To>
	static quaternion fromImpliedTransform(const vec3<T>& From, const vec3<T>& To) {
		double _dot = From.normalized().dot(To.normalized());
		if(_dot > 1.0)
			_dot = 1.0;
		else if(_dot < -1.0)
			_dot = -1.0;

		double angle = -acos(_dot);
		vec3<T> axis = From.cross(To).normalized();
		if(axis.cross(To).dot(From) < 0)
			angle = -angle;

		return quaternion::fromAxisAngle(axis, (T)angle);
	}

	//Builds a rotation that rotates <From> into the direction of <To>, maintaining an up vector similar to <Up> 
	static quaternion fromImpliedTransform(const vec3<T>& From, const vec3<T>& To, const vec3<T>& Up) {
		vec3<T> f = From.normalized(), to = To.normalized();
		double _dot = f.dot(to);
		if(_dot > 1.0)
			_dot = 1.0;
		else if(_dot < -1.0)
			_dot = -1.0;

		double angle = -acos(_dot);
		vec3<T> axis = f.cross(to).normalized();
		if(axis.cross(to).dot(f) < 0)
			angle = -angle;

		auto rot = quaternion::fromAxisAngle(axis, (T)angle);
		return (fromImpliedTransform(rot * Up, to.cross(Up).cross(to)) * rot).normalize();
	}
	
	quaternion() : xyz(0), w(1) {}
	quaternion(T def) : xyz(def), w(def) {}
	quaternion(vec3<T> XYZ, T W) : xyz(XYZ), w(W) {}
	quaternion(T X, T Y, T Z, T W) : xyz(X,Y,Z), w(W) {}
	quaternion(const quaternion<T>& other) : xyz(other.xyz), w(other.w) {}
};

typedef quaternion<float> quaternionf;
typedef quaternion<double> quaterniond;
