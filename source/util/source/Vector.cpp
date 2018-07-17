#include "BiPatch/Vector.h"
#include <iostream>

namespace BiPatch {

Vector Vector::normal() const {
    Vector v1(*this);
    v1.normalize();
    return v1;
}

};
