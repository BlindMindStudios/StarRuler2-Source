#pragma once
#include <string>

typedef double varInterpreter(void*,const std::string*);
typedef double varIndexInterpreter(void*,int);
typedef int varIndexConverter(const std::string*);
double nullConverter(void*,const std::string*);

struct FormulaError {
	std::string msg;
	FormulaError(const char* message) : msg(message) {}
	FormulaError(std::string message) : msg(message) {}
};

class Formula {
public:
	//Evaluates the formula
	//Variables in the formula will be passed to <VarConverter>, which receives
	//the name of the variable, and the <UserPointer> passed to evaluate
	virtual double evaluate(varInterpreter VarConverter = nullConverter, void* UserPointer = nullptr, varIndexInterpreter VarIndexConverter = 0) = 0;
	virtual ~Formula() {}

	//Creates a formula from infix notation
	//Can throw FormulaError if there is an error in the expression
	static Formula* fromInfix(const char* expression, varIndexConverter VarConverter = 0, bool catchErrors = true);
};
;
