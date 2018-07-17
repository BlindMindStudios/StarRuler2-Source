#ifdef WIN_MODE
#include <regex>
typedef std::regex regex;
typedef std::match_results<std::string::const_iterator> reg_result;

#define reg_compile(r, c)\
	static regex r = std::regex(c)

#define reg_match(str, m, r)\
	std::regex_match(str.cbegin(), str.cend(), m, r)

#define reg_str(str, m, i)\
	m[i]

#else
#include <regex.h>
typedef regex_t* regex;
typedef regmatch_t reg_result[16];

#define reg_compile(r, c) \
	static regex r = 0;\
	if(!r) {\
		r = new regex_t();\
		regcomp(r, c, REG_EXTENDED);\
	}

#define reg_match(str, m, r)\
	!regexec(r, str.c_str(), 16, m, 0)

#define reg_str(str, m, i)\
	str.substr(m[i].rm_so, m[i].rm_eo - m[i].rm_so)

#endif
