//created by Shaun David Ramsey and Kristin Potter copyright (c) 2003
//email ramsey()cs.utah.edu with any quesitons
/*
This copyright notice is available at:
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

#include "Vector.h"
#define ray_epsilon 1e-4 // some small epsilon for flt pt
//#define twoplanes true // comment out this line to use raypatch 
#ifndef twoplanes // if we're not using patch-twoplanes intersection
    #define raypatch true //then use ray-patch intersections
#endif

#ifndef BILINEAR_H
#define BILINEAR_H 


namespace BiPatch {

//find roots of ax^2+bx+c=0  in the interval min,max.
// place the roots in u[2] and return how many roots found
int QuadraticRoot(double a, double b, double c, 
		   double min, double max,double *u);

// Bilinear patch class
class BilinearPatch
{
  // The four points defining the patch
  Vector P00, P01, P10, P11;

 public:
  
  // Constructors
  BilinearPatch(Vector Pt00, Vector Pt01, Vector Pt10, Vector Pt11);
  // Destructor
  ~BilinearPatch(){}
  Vector getP00(){return P00;}
  // Return the point P01
  Vector getP01(){return P01;}
  // Return the point P10
  Vector getP10(){return P10;}
  // Return the point P11
  Vector getP11(){return P11;}
  // Find the tangent (du)
  Vector TanU( double v);
  // Find the tangent (dv)
  Vector TanV( double u);
  // Find dudv
  Vector Normal( double u, double v);
  // Evaluate the surface of the patch at u,v
  Vector SrfEval( double u, double v);
  // Find the local closest point to spacept
  bool RayPatchIntersection( Vector r, Vector d, Vector &uv);
};

};

#endif
