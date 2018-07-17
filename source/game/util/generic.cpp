#include "util/generic.h"
#include "str_util.h"

Generic::Generic() : type(GT_Bool), check(false) {
}

void Generic::fromString(const std::string& val) {
	switch(type) {
		case GT_Bool:
			check = toBool(val);
		break;
		case GT_Integer:
			num = toNumber<int>(val);
		break;
		case GT_Double:
			flt = toNumber<double>(val);
		break;
		case GT_String:
			*str = val;
		break;
		case GT_Enum: {
			value = 0;
			for(unsigned i = 0; i < values->size(); ++i) {
				if(val == (*values)[i]) {
					value = i;
					break;
				}
			}
		} break;
	}
}

std::string Generic::toString() {
	switch(type) {
		default:
		case GT_Bool:
			return check ? "true" : "false";
		break;
		case GT_Integer:
			return ::toString(num);
		break;
		case GT_Double:
			return ::toString(flt,4);
		break;
		case GT_String:
			return *str;
		break;
		case GT_Enum:
			return (*values)[value];
		break;
	}
}

Generic::~Generic() {
	if(type == GT_String)
		delete str;
	else if(type == GT_Enum)
		delete values;
}

bool Generic::getBool() {
	return check;
}

void Generic::setBool(bool val) {
	if(type == GT_String)
		delete str;
	else if(type == GT_Enum)
		delete values;
	type = GT_Bool;
	check = val;
}

Generic::operator int() {
	return getInteger();
}

Generic::operator double() {
	return getDouble();
}

Generic::operator bool() {
	return getBool();
}

void Generic::operator=(int v) {
	setInteger(v);
}

void Generic::operator=(double v) {
	setDouble(v);
}

void Generic::operator=(bool v) {
	setBool(v);
}

void NamedGeneric::operator=(int v) {
	setInteger(v);
}

void NamedGeneric::operator=(double v) {
	setDouble(v);
}

void NamedGeneric::operator=(bool v) {
	setBool(v);
}

int Generic::getInteger() {
	return num;
}

void Generic::setInteger(int val) {
	if(type == GT_String)
		delete str;
	else if(type == GT_Enum)
		delete values;
	type = GT_Integer;
	num = val;
}

double Generic::getDouble() {
	return flt;
}

void Generic::setDouble(double val) {
	if(type == GT_String)
		delete str;
	else if(type == GT_Enum)
		delete values;
	type = GT_Double;
	flt = val;
}

std::string* Generic::getString() {
	if(type == GT_String)
		return str;
	return 0;
}

void Generic::setString(const std::string& val) {
	if(type == GT_String) {
		*str = val;
	}
	else {
		if(type == GT_Enum)
			delete values;
		type = GT_String;
		str = new std::string(val);
	}
}

Generic::Generic(bool def) {
	type = GT_Bool;
	check = def;
}

Generic::Generic(int def) {
	type = GT_Integer;
	num = def;
}

Generic::Generic(const std::string& def) {
	type = GT_String;
	str = new std::string(def);
}

Generic::Generic(double def) {
	type = GT_Double;
	flt = def;
}

NamedGeneric::NamedGeneric(const std::string& Name, bool def) : Generic(def), name(Name) {
}

NamedGeneric::NamedGeneric(const std::string& Name, int def) : Generic(def), name(Name) {
}

NamedGeneric::NamedGeneric(const std::string& Name, const char* def) : Generic(std::string(def)), name(Name) {
}

NamedGeneric::NamedGeneric(const std::string& Name, const std::string& def) : Generic(def), name(Name) {
}

NamedGeneric::NamedGeneric(const std::string& Name, double def) : Generic(def), name(Name) {
}

NamedGeneric::NamedGeneric() : Generic() {
}
