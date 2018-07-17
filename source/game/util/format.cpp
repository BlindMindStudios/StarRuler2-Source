#include "format.h"
#include <stdio.h>

#ifdef _MSC_VER
#define snprintf _snprintf
#endif

void format(std::string& arg, const char* fmt, unsigned argn, FormatArg* argv) {
	char buffer[2048];

	unsigned left = 2048;
	char* start = buffer;

	while(*fmt != '\0' && left != 0) {
		if(*fmt == '$') {
			++fmt;
			if(*fmt == '\0')
				break;
			if(*fmt >= '1' && *fmt <= '9') {
				unsigned arg = *fmt - '1';
				if(arg < argn) {
					unsigned printed = argv[arg].print(start, left);
					start += printed;
					left -= printed;
				}
				else {
					//Print nothing (safe error)
				}
				++fmt;
			}
			else {
				*start = '$';
				++start; --left;
				if(left != 0) {
					*start = *fmt;
					++start;
					--left;
					++fmt;
				}
			}
		}
		else {
			*start = *fmt;
			++start; ++fmt; --left;
		}
	}

	arg.assign(buffer, 2048 - left);
};

std::string format(const char* fmt, FormatArg a1) {
	std::string output;
	format(output, fmt, 1, &a1);
	return output;
}

std::string format(const char* fmt, FormatArg a1, FormatArg a2) {
	std::string output;
	FormatArg args[2] = { a1, a2 };
	format(output, fmt, 2, args);
	return output;
}

std::string format(const char* fmt, FormatArg a1, FormatArg a2, FormatArg a3) {
	std::string output;
	FormatArg args[3] = { a1, a2, a3 };
	format(output, fmt, 3, args);
	return output;
}

std::string format(const char* fmt, FormatArg a1, FormatArg a2, FormatArg a3, FormatArg a4) {
	std::string output;
	FormatArg args[4] = { a1, a2, a3, a4 };
	format(output, fmt, 4, args);
	return output;
}

std::string format(const char* fmt, FormatArg a1, FormatArg a2, FormatArg a3, FormatArg a4, FormatArg a5) {
	std::string output;
	FormatArg args[5] = { a1, a2, a3, a4, a5 };
	format(output, fmt, 5, args);
	return output;
}

FormatArg::FormatArg() : type(Arg_int), i(0) {}
FormatArg::FormatArg(float F) : type(Arg_float), f(F) {}
FormatArg::FormatArg(double D) : type(Arg_double), d(D) {}
FormatArg::FormatArg(unsigned U) : type(Arg_unsigned), u(U) {}
FormatArg::FormatArg(int I) : type(Arg_int), i(I) {}
FormatArg::FormatArg(const char* C) : type(Arg_cstr), c(C) {}
FormatArg::FormatArg(const std::string& S) : type(Arg_string), s(&S) {}

unsigned FormatArg::print(char* buffer, unsigned space) {
	int printed = 0;
	switch(type) {
	case Arg_float:
		printed = snprintf(buffer, space, "%f", f);
		break;
	case Arg_double:
		printed = snprintf(buffer, space, "%g", d);
		break;
	case Arg_unsigned:
		printed = snprintf(buffer, space, "%u", u);
		break;
	case Arg_int:
		printed = snprintf(buffer, space, "%i", i);
		break;
	case Arg_cstr:
		printed = snprintf(buffer, space, "%s", c);
		break;
	case Arg_string:
		if(s)
			printed = snprintf(buffer, space, "%s", s->c_str());
		break;
	}

	if(printed > 0)
		return printed;
	else
		return 0;
}
