#pragma once
#include <vector>
#include <map>
#include <string>

enum GenericType {
	GT_Bool,
	GT_Integer,
	GT_Double,
	GT_Enum,
	GT_String,
	GT_Pointer,
};

struct Generic {
	GenericType type;

	union {
		bool check;
		std::string* str;
		void* ptr;
		struct {
			int num;
			int num_min;
			int num_max;
		};
		struct {
			double flt;
			double flt_min;
			double flt_max;
		};
		struct {
			std::vector<std::string>* values;
			int value;
		};
	};

	void fromString(const std::string& str);
	std::string toString();

	bool getBool();
	void setBool(bool val);

	int getInteger();
	void setInteger(int val);

	double getDouble();
	void setDouble(double val);

	std::string* getString();
	void setString(const std::string& val);

	void* getPtr();
	void setPtr(void* ptr);

	operator int();
	operator double();
	operator bool();

	void operator=(int);
	void operator=(double);
	void operator=(bool);

	Generic(bool def);
	Generic(int def);
	Generic(const std::string& def);
	Generic(double def);

	Generic();
	~Generic();
};

struct NamedGeneric : Generic {
	std::string name;

	NamedGeneric(const std::string& Name, bool def);
	NamedGeneric(const std::string& Name, int def);
	NamedGeneric(const std::string& Name, const char* def);
	NamedGeneric(const std::string& Name, const std::string& def);
	NamedGeneric(const std::string& Name, double def);

	void operator=(int);
	void operator=(double);
	void operator=(bool);

	NamedGeneric();
};
