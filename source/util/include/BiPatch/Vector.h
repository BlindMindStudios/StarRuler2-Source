#ifndef VECTOR_H
#define VECTOR_H 1

#include <math.h>

namespace BiPatch {

class Vector {
    double d[3];

public:

    inline Vector (double x, double y, double z=0);
    inline Vector(const Vector& v);
    inline Vector();
    inline double length() const;
    inline double length2() const;
    inline Vector& operator=(const Vector& v);
    inline bool operator==(const Vector& v) const;
    inline Vector operator*(double s) const;
    inline Vector operator*(const Vector& v) const;
    inline Vector operator/(const Vector& v) const;
    inline Vector& operator*=(double s);
    Vector operator/(double s) const;
    inline Vector operator+(const Vector& v) const;
    inline Vector& operator+=(const Vector& v);
    inline Vector operator-() const;
    inline Vector operator-(const Vector& v) const;
    Vector& operator-=(const Vector& v);
    inline double normalize();
    Vector normal() const;
    inline Vector cross(const Vector& v) const;
    inline double dot(const Vector& v) const;
    inline void x(double xx) {	d[0]=xx;    }
    inline double x() const;
    inline void y(double yy) {	d[1]=yy;    }
    inline double y() const;
    inline void z(double zz) {	d[2]=zz;    }
    inline double z() const;
    inline double minComponent() const;
    inline bool operator != (const Vector& v) const;
    inline double* ptr() const {return (double*)&d[0];}

    void make_ortho(Vector&v1, Vector&v2)
      {
	Vector v0(this->cross(Vector(1,0,0)));
	if(v0.length2() == 0){
	  v0=this->cross(this->cross(Vector(0,1,0)));
	}
	v1=this->cross(v0);
	v1.normalize();
	v2=this->cross(v1);
	v2.normalize();
      }
};


inline Vector::Vector(double x, double y, double z) {
    d[0]=x;
    d[1]=y;
    d[2]=z;
}

inline Vector::Vector(const Vector& v) {
    d[0]=v.d[0];
    d[1]=v.d[1];
    d[2]=v.d[2];
}

inline Vector::Vector() {
}


inline double Vector::length() const {
    return sqrt(length2());
}

inline double Vector::length2() const {
    return d[0]*d[0]+d[1]*d[1]+d[2]*d[2];
}

inline Vector& Vector::operator=(const Vector& v) {
    d[0]=v.d[0];
    d[1]=v.d[1];
    d[2]=v.d[2];
    return *this;
}



inline Vector Vector::operator*(double s) const {
    return Vector(d[0]*s, d[1]*s, d[2]*s);
}

inline Vector operator*(double s, const Vector& v) {
    return v*s;
}

inline Vector Vector::operator*(const Vector& v) const {
    return Vector(d[0]*v.d[0], d[1]*v.d[1], d[2]*v.d[2]);
}

inline Vector Vector::operator/(const Vector& v) const {
    return Vector(d[0]/v.d[0], d[1]/v.d[1], d[2]/v.d[2]);
}

inline Vector Vector::operator+(const Vector& v) const {
    return Vector(d[0]+v.d[0], d[1]+v.d[1], d[2]+v.d[2]);
}

inline Vector& Vector::operator+=(const Vector& v) {
    d[0]+=v.d[0];
    d[1]+=v.d[1];
    d[2]+=v.d[2];
    return *this;
}

inline Vector& Vector::operator*=(double s) {
    d[0]*=s;
    d[1]*=s;
    d[2]*=s;
    return *this;
}

inline Vector Vector::operator-() const {
    return Vector(-d[0], -d[1], -d[2]);
}

inline Vector Vector::operator-(const Vector& v) const {
    return Vector(d[0]-v.d[0], d[1]-v.d[1], d[2]-v.d[2]);
}


inline double Vector::normalize() {
    double l=length();
    if(l != 0)
      {
      d[0]/=l;
      d[1]/=l;
      d[2]/=l;
      }
    return l;
}

inline Vector Vector::cross(const Vector& v) const {
    return Vector(d[1]*v.d[2]-d[2]*v.d[1],
    	      d[2]*v.d[0]-d[0]*v.d[2],
    	      d[0]*v.d[1]-d[1]*v.d[0]);
}

inline double Vector::dot(const Vector& v) const {
    return d[0]*v.d[0]+d[1]*v.d[1]+d[2]*v.d[2];
}


inline double Vector::x() const {
    return d[0];
}

inline double Vector::y() const {
    return d[1];
}

inline double Vector::z() const {
    return d[2];
}

inline double Vector::minComponent() const {
    return (d[0]<d[1] && d[0]<d[2])?d[0]:d[1]<d[2]?d[1]:d[2];
}

inline bool Vector::operator != (const Vector& v) const {
    return d[0] != v.d[0] || d[1] != v.d[1] || d[2] != v.d[2];
}

inline bool Vector::operator == (const Vector& v) const {
   return d[0] == v.d[0] && d[1] == v.d[1] && d[2] == v.d[2];
}

};

#endif
