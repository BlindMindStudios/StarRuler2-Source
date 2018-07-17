#pragma once

template <class T>
T max_(T a, T b) {
	return a > b ? a : b;
}

template <class T>
T min_(T a, T b) {
	return a > b ? b : a;
}
