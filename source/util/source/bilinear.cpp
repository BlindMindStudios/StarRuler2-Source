//created by Shaun David Ramsey and Kristin Potter (c) 20003
//email ramsey()cs.utah.edu with questions/comments
/*
The ray bilinear patch intersection software are "Open Source"  
according to the MIT License located at:
	http://www.opensource.org/licenses/mit-license.php

Copyright (c) 2003 Shaun David Ramsey, Kristin Potter, Charles Hansen

Permission is hereby granted, free of charge, to any person obtaining a 
copy of this software and associated documentation files (the "Software"), 
to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, 
and/or sel copies of the Software, and to permit persons to whom the 
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in 
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.
*/

#include "BiPatch/bilinear.h"
#include <iostream>
#include <cmath>

#ifdef _MSC_VER
#define copysign _copysign
#endif

namespace BiPatch {

//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
// Constructor
//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
BilinearPatch::BilinearPatch(Vector Pt00, Vector Pt01, Vector Pt10, Vector Pt11)
{
  P00 = Pt00;
  P01 = Pt01;
  P10 = Pt10;
  P11 = Pt11;
}

// What is the x,y,z position of a point at params u and v?
Vector BilinearPatch::SrfEval( double u, double v)
{
  Vector respt;
  respt.x( ( (1.0 - u) * (1.0 - v) * P00.x() +
	     (1.0 - u) *        v  * P01.x() + 
	     u  * (1.0 - v) * P10.x() +
	     u  *        v  * P11.x()));
  respt.y(  ( (1.0 - u) * (1.0 - v) * P00.y() +
	      (1.0 - u) *        v  * P01.y() + 
	      u  * (1.0 - v) * P10.y() +
	      u  *        v  * P11.y()));
  respt.z(  ( (1.0 - u) * (1.0 - v) * P00.z() +
	      (1.0 - u) *        v  * P01.z() + 
	      u  * (1.0 - v) * P10.z() +
	      u  *        v  * P11.z()));
  return respt;
}

//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
// Find tangent (du)
//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
Vector BilinearPatch::TanU( double v)
{
  Vector tanu;
  tanu.x( ( 1.0 - v ) * (P10.x() - P00.x()) + v * (P11.x() - P01.x()));
  tanu.y( ( 1.0 - v ) * (P10.y() - P00.y()) + v * (P11.y() - P01.y()));
  tanu.z( ( 1.0 - v ) * (P10.z() - P00.z()) + v * (P11.z() - P01.z()));
  return tanu;
}

//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
// Find tanget (dv)
//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
Vector BilinearPatch::TanV( double u)
{
  Vector tanv;
  tanv.x( ( 1.0 - u ) * (P01.x() - P00.x()) + u * (P11.x() - P10.x()) );
  tanv.y( ( 1.0 - u ) * (P01.y() - P00.y()) + u * (P11.y() - P10.y()) );
  tanv.z( ( 1.0 - u ) * (P01.z() - P00.z()) + u * (P11.z() - P10.z()) );
  return tanv;
}


//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
// Find the normal of the patch
//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
Vector BilinearPatch::Normal( double u, double v)
{
  Vector tanu,tanv;
  tanu = TanU( v );
  tanv = TanV( u );
  return tanu.cross(tanv); 
}
  
//choose between the best denominator to avoid singularities
//and to get the most accurate root possible
inline double getu(double v, double M1, double M2, double J1,double J2,
	    double K1, double K2, double R1, double R2)
{

  double denom = (v*(M1-M2)+J1-J2);
  double d2 = (v*M1+J1);
  if(fabs(denom) > fabs(d2)) // which denominator is bigger
    {
      return (v*(K2-K1)+R2-R1)/denom;
    }
  return -(v*K1+R1)/d2;
}

// compute t with the best accuracy by using the component
// of the direction that is largest
double computet(Vector dir, Vector orig, Vector srfpos)
{
  // if x is bigger than y and z
  if(fabs(dir.x()) >= fabs(dir.y()) && fabs(dir.x()) >= fabs(dir.z()))
    return (srfpos.x() - orig.x()) / dir.x();
  // if y is bigger than x and z
  else if(fabs(dir.y()) >= fabs(dir.z())) // && fabs(dir.y()) >= fabs(dir.x()))
    return (srfpos.y() - orig.y()) / dir.y();
  // otherwise x isn't bigger than both and y isn't bigger than both
  else  //if(fabs(dir.z()) >= fabs(dir.x()) && fabs(dir.z()) >= fabs(dir.y()))
    return (srfpos.z() - orig.z()) / dir.z();    
}
	    


//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
//             RayPatchIntersection
// intersect rays of the form p = r + t q where t is the parameter
// to solve for. With the patch pointed to by *this
// for valid intersections:
// place the u,v intersection point in uv[0] and uv[1] respectively.
// place the t value in uv[2]
// return true to this function
// for invalid intersections - simply return false uv values can be 
// anything
//+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+
bool BilinearPatch::RayPatchIntersection(Vector r, Vector q, Vector &uv)
{
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Equation of the patch:
  // P(u, v) = (1-u)(1-v)P00 + (1-u)vP01 + u(1-v)P10 + uvP11
  // Equation of the ray:
  // R(t) = r + tq
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  Vector pos1, pos2; //Vector pos = ro + t*rd;
  int num_sol; // number of solutions to the quadratic
  double vsol[2]; // the two roots from quadraticroot
  double t2,u; // the t values of the two roots

  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Variables for substitition
  // a = P11 - P10 - P01 + P00
  // b = P10 - P00
  // c = P01 - P00
  // d = P00  (d is shown below in the #ifdef raypatch area)
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~  

  // Find a w.r.t. x, y, z
  double ax = P11.x() - P10.x() - P01.x() + P00.x();
  double ay = P11.y() - P10.y() - P01.y() + P00.y();
  double az = P11.z() - P10.z() - P01.z() + P00.z();


  // Find b w.r.t. x, y, z
  double bx = P10.x() - P00.x();
  double by = P10.y() - P00.y();
  double bz = P10.z() - P00.z();

  // Find c w.r.t. x, y, z
  double cx = P01.x() - P00.x();
  double cy = P01.y() - P00.y();
  double cz = P01.z() - P00.z();


  double rx = r.x();
  double ry = r.y();
  double rz = r.z();

  // Retrieve the xyz of the q part of ray
  double qx = q.x();
  double qy = q.y();
  double qz = q.z();


#ifdef twoplanes
  {

    Vector p1n,p2n, dir(qx,qy,qz), orig(rx,ry,rz);
    dir.normalize();
    dir.make_ortho(p1n,p2n);

    double D1 = (p1n.x() * rx + p1n.y() * ry + p1n.z() * rz);
    double D2 = (p2n.x() * rx + p2n.y() * ry + p2n.z() * rz);
    
    Vector a(ax,ay,az);
    Vector b(bx,by,bz);
    Vector c(cx,cy,cz);
    Vector d(P00.x(),P00.y(),P00.z());
    
    
    double M1 = p1n.dot(a);
    double M2 = p2n.dot(a);
    double J1 = p1n.dot(b);
    double J2 = p2n.dot(b);
    double K1 = p1n.dot(c); 
    double K2 = p2n.dot(c); 
    double R1 = p1n.dot(d)-D1;
    double R2 = p2n.dot(d)-D2;

    double A = M1*K2-M2*K1;
    double B = M1*R2-M2*R1 -J2*K1+J1*K2;
    double C = J1*R2-R1*J2;
    
    
    uv.x(-2); uv.y(-2); uv.z(-2);
    num_sol = QuadraticRoot(A,B,C,-ray_epsilon,1+ray_epsilon,vsol);
    switch(num_sol)
      {
      case 0:
	return false; // no solutions found
	break;
      case 1:
	uv.y(vsol[0]); //the v value
	uv.x(getu(vsol[0],M1,M2,J1,J2,K1,K2,R1,R2));
	if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon) // u is valid
	  {
	    pos1 = SrfEval(uv.x(),uv.y());
	    uv.z(computet(dir,orig,pos1)); 
	    if(uv.z() > 0) //t is valid
	      return true;
	    else
	      return false;
	  }
	return false; // no other soln - so ret false
	break;
      case 2: // two solutions found
	uv.x( getu(vsol[0],M1,M2,J1,J2,K1,K2,R1,R2));
	uv.y( vsol[0]);
	pos1 = SrfEval(uv.x(),uv.y());
	uv.z( computet(dir,orig,pos1)); 
	if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon && uv.z() > 0)//valid vars?
	  {
	    u = getu(vsol[1],M1,M2,J1,J2,K1,K2,R1,R2);
	    if(u < 1+ray_epsilon && u > -ray_epsilon) // another valid u 
	      { 
		pos2 = SrfEval(u,    vsol[1]);
		t2 = computet(dir,orig,pos2); 
		if(t2 < 0 || uv.z() <= t2) // t2 not valid or t1 is better
		  return true;
		uv.x( u ); uv.y( vsol[1] ); uv.z( t2 ); //return vals
		return true;
	      }
	    else // this one was bad but the other was okay..ret true
	      return true;
	  }
	else //bad u valid, try other one
	  {
	    uv.y( vsol[1] );
	    uv.x( getu(vsol[1],M1,M2,J1,J2,K1,K2,R1,R2) );
	    pos1 = SrfEval(uv.x(),uv.y());
	    uv.z( computet(dir,orig,pos1) ); 
	    if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon
	       && uv.z() > 0) // variables are okay?
	      return true;
	    else
	      return false;
	  }
	break;
      } //end 2 root case.
    std::cout << " ERROR: We don't get here in twoplanes" << std::endl;
    return false;
  }
#endif // end two planes 
#ifdef raypatch

  // Find d w.r.t. x, y, z - subtracting r just after  
  double dx = P00.x() - r.x();
  double dy = P00.y() - r.y();
  double dz = P00.z() - r.z();
  

  // Find A1 and A2
  double A1 = ax*qz - az*qx;
  double A2 = ay*qz - az*qy;

  // Find B1 and B2
  double B1 = bx*qz - bz*qx;
  double B2 = by*qz - bz*qy;

  // Find C1 and C2
  double C1 = cx*qz - cz*qx;
  double C2 = cy*qz - cz*qy;

  // Find D1 and D2
  double D1 = dx*qz - dz*qx;
  double D2 = dy*qz - dz*qy;
 
  Vector dir(qx,qy,qz), orig(rx,ry,rz);
  double A = A2*C1 - A1*C2;
  double B = A2*D1 -A1*D2 + B2*C1 -B1*C2;
  double C = B2*D1 - B1*D2;
  
  uv.x(-2); uv.y(-2); uv.z(-2);

  num_sol = QuadraticRoot(A,B,C,-ray_epsilon,1+ray_epsilon,vsol);


  switch(num_sol)
    {
    case 0:
      return false; // no solutions found
    case 1:
		uv.y( vsol[0]);
		uv.x( getu(uv.y(),A2,A1,B2,B1,C2,C1,D2,D1));
		pos1 = SrfEval(uv.x(),uv.y());
		uv.z( computet(dir,orig,pos1) );
		if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon && uv.z() > -ray_epsilon)//vars okay?
			return true;
		else
			return false; // no other soln - so ret false
    case 2: // two solutions found
      uv.y( vsol[0]);
      uv.x( getu(uv.y(),A2,A1,B2,B1,C2,C1,D2,D1));
      pos1 = SrfEval(uv.x(),uv.y());
      uv.z( computet(dir,orig,pos1) ); 
      if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon && uv.z() > 0)
	{
	  u = getu(vsol[1],A2,A1,B2,B1,C2,C1,D2,D1);
	  if(u < 1+ray_epsilon && u > ray_epsilon)
	    {
	      pos2 = SrfEval(u,vsol[1]);
	      t2 = computet(dir,orig,pos2);
	      if(t2 < 0 || uv.z() < t2) // t2 is bad or t1 is better
		return true; 
	      // other wise both t2 > 0 and t2 < t1
	      uv.y( vsol[1]);
	      uv.x(  u );
	      uv.z( t2 );
	      return true;
	    }
	  return true; // u2 is bad but u1 vars are still okay
	}
      else // doesn't fit in the root - try other one
	{
	  uv.y( vsol[1] );
	  uv.x( getu(vsol[1],A2,A1,B2,B1,C2,C1,D2,D1) );
	  pos1 = SrfEval(uv.x(),uv.y());
	  uv.z( computet(dir,orig,pos1) ); 
	  if(uv.x() < 1+ray_epsilon && uv.x() > -ray_epsilon &&uv.z() > 0)
	    return true;
	  else
	    return false;
	}
      break;
    }
#endif    // end ray patch
 
  std::cout << " ERROR: We don't get here in Ray Patch Intersection" << std::endl;
  return false; 
}


// a x ^2 + b x + c = 0
// in this case, the root must be between min and max
// it returns the # of solutions found
// x = [ -b +/- sqrt(b*b - 4 *a*c) ] / 2a
// or x = 2c / [-b +/- sqrt(b*b-4*a*c)]
int QuadraticRoot(double a, double b, double c, 
		   double min, double max,double *u)
{
  u[0] = u[1] = min-min; // make it lower than min
  if(a == 0.0) // then its close to 0
    {
      if(b != 0.0) // not close to 0
	{
	  u[0] = - c / b;
	  if(u[0] > min && u[0] < max) //its in the interval
	    return 1; //1 soln found
	  else  //its not in the interval
	    return 0;
	}
      else
	return 0;
    }
  double d = b*b - 4*a*c; //discriminant
  if(d <= 0.0) // single or no root
    {
      if(d == 0.0) // close to 0
	{
	  u[0] = -b / a;
	  if(u[0] > min && u[0] < max) // its in the interval
	    return 1;
	  else //its not in the interval
	    return 0;
	}
      
      else // no root d must be below 0
	return 0;
    }

  double q = -0.5  * (b + copysign(sqrt(d),b));
  u[0] = c / q;
  u[1] = q / a;

  if(     (u[0] > min && u[0] < max)
	  &&  (u[1] > min && u[1] < max))
    return 2;
  else if(u[0] > min && u[0] < max) //then one wasn't in interval
    return 1;
  else if(u[1] > min && u[1] < max)
    {  // make it easier, make u[0] be the valid one always
      double dummy;
      dummy = u[0];
      u[0] = u[1];
      u[1] = dummy; // just in case somebody wants to check it
      return 1;
    }
  return 0;

}

};
