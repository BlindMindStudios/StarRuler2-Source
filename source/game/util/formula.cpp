#include <list>
#include <vector>
#include <set>
#include <string>
#include <ctype.h>
#include <math.h>
#include <unordered_map>
#include <tuple>
#include "formula.h"
#include "constants.h"
#include "main/logging.h"

#ifdef _WIN32
	#define COMPILE_FORMULAS
	#ifdef _M_AMD64
		#define FORMULA_64
	#endif
#endif
#ifdef __i386__
	#define COMPILE_FORMULAS
#endif
#ifdef __amd64__
	#define COMPILE_FORMULAS
	#define FORMULA_64
#endif

#ifdef COMPILE_FORMULAS
#include "virtual_asm.h"

assembler::CodePage* currentPage = 0;

assembler::CodePage* getCodePage() {
	if(currentPage == 0 || currentPage->getFreeSize() < 512) {
		if(currentPage) {
			currentPage->finalize();
			currentPage->drop();
		}
		currentPage = new assembler::CodePage(4000, (void*)&getCodePage);
		currentPage->grab();
	}

	currentPage->grab();
	return currentPage;
}
#endif

//Function callable by formulas, receives a pointer to the stack and the number of arguments given to the function
typedef double formulaFunc(double*,unsigned);
//Checks that the number of arguments is valid for the function
typedef bool formulaArgCheck(unsigned);

typedef double compiledCFormula(double*,double*,const std::string*,varInterpreter,void*,varIndexInterpreter);

const unsigned FormulaStackSize = 64;

double nullConverter(void*,const std::string*) {
	return 0.0;
}

typedef std::tuple<formulaFunc*,unsigned> formulaFuncDef;
std::unordered_map<std::string, formulaFuncDef> formulaFunctions;
std::unordered_map<std::string, double> formulaConstants;
void prepareFormulaFunctions();

enum TokenType {
	TT_Invalid,
	TT_Constant,
	TT_Variable,
	TT_Variable_Index,
	TT_Operator,
	TT_Bracket,
	TT_Comma,
};

enum OperatorType {
	OT_Or,
	OT_And,
	OT_Less,
	OT_LessEquals,
	OT_Greater,
	OT_GreaterEquals,
	OT_Equals,
	OT_Add,
	OT_Sub,
	OT_Mul,
	OT_Div,
	OT_Pow,
	OT_Neg,
	OT_Not,
	OT_Func,
};

struct Token {
	TokenType type;
	OperatorType op;
	union {
		double value;
		int index;
		bool open;
		unsigned args;
	};
	std::string name;

	int getStackChange() const {
		switch(type) {
		case TT_Constant: case TT_Variable: case TT_Variable_Index:
			return 1; //Pushes 1
		case TT_Operator:
			if(op == OT_Neg || op == OT_Not)
				return 0;
			else if(op == OT_Func)
				return 1 - int(args); //Pops <args>, Pushes 1
			else
				return -1; //Pops 2, Pushes 1
		default:
			throw FormulaError("Well this isn't good");
		}
	}

	int getPrecedence() const {
		switch(op) {
		case OT_Or:
			return 1;
		case OT_And:
			return 2;
		case OT_Less: case OT_LessEquals:
		case OT_Greater: case OT_GreaterEquals: case OT_Equals: 
			return 3;
		case OT_Add: case OT_Sub:
			return 5;
		case OT_Mul: case OT_Div:
		case OT_Neg: case OT_Not:
			return 10;
		case OT_Pow:
			return 15;
		case OT_Func:
			return 20;
		}
		return 0;
	}

	bool takesPrecendenceOver(const Token& other) {
		if(op == OT_Neg || op == OT_Not) {
			return getPrecedence() >= other.getPrecedence();
		}
		else {
			return getPrecedence() > other.getPrecedence();
		}
	}

	bool operator==(TokenType tokenType) const {
		return type == tokenType;
	}

	bool operator==(OperatorType opType) const {
		return type == TT_Operator && op == opType;
	}
};

class CFormula : public Formula {
#ifdef COMPILE_FORMULAS
	assembler::CodePage* page;
	compiledCFormula* formula;
#else
	std::list<Token> rpn;
#endif
	double* constants;
	const std::string* names;
	int varIndex;

	static void convertInfix(const char* expression, std::list<Token>& rpn, varIndexConverter conv);
public:

	double evaluate(varInterpreter VarConverter, void* user, varIndexInterpreter conv) {
#ifdef COMPILE_FORMULAS
		if(formula) {
			double stack[FormulaStackSize];
			return (*formula)(stack, constants, names, VarConverter, user, conv);
		}
#else
		if(!rpn.empty()) {
			double stack[FormulaStackSize];
			return evaluateRPN(stack, VarConverter, user, conv);
		}
#endif
		else if(varIndex != -1) {
			return conv(user, varIndex);
		}
		else if(constants) {
			return constants[0];
		}
		else if(names) {
			return VarConverter(user,&names[0]);
		}
		else {
			return 0;
		}
	}

	static void validateRPN(const std::list<Token>& rpn);
	static void optimizeRPN(std::list<Token>& rpn);
	static void buildCaches(const std::list<Token>& tokens, double** constants, const std::string** names);

#ifdef COMPILE_FORMULAS
	void buildExecutable(std::list<Token>& tokens);

	CFormula(const char* expression, varIndexConverter conv) : page(0), formula(0), varIndex(-1) {
		std::list<Token> rpn;
#else
	double evaluateRPN(double* stack, varInterpreter VarConverter, void* user, varIndexInterpreter conv);

	CFormula(const char* expression, varIndexConverter conv) : varIndex(-1) {
#endif

		convertInfix(expression, rpn, conv);
		optimizeRPN(rpn);
		validateRPN(rpn);
		buildCaches(rpn, &constants, &names);

		if(rpn.size() > 1) { //Complex formulas should be implemented as a JIT
#ifdef COMPILE_FORMULAS
			buildExecutable(rpn);
#endif
		}
		else {
			if(rpn.front().type == TT_Variable_Index)
				varIndex = rpn.front().index;
#ifndef COMPILE_FORMULAS
			rpn.clear();
#endif
		}
	}

	~CFormula() {
		delete[] constants;
		delete[] names;
#ifdef COMPILE_FORMULAS
		if(page)
			page->drop();
#endif
	}
};

Formula* Formula::fromInfix(const char* expression, varIndexConverter VarConverter, bool catchErrors) {
	if(expression[0] == '\0')
		return 0;
	if(catchErrors) {
		try {
			return new CFormula(expression, VarConverter);
		}
		catch (FormulaError& err) {
			error("Error parsing formula '%s': %s.", expression, err.msg.c_str());
			return new CFormula("0", VarConverter);
		}
	}
	else {
		return new CFormula(expression, VarConverter);
	}
}

double pow_wrapper(double* base, double* exponent) {
	return pow(*base,*exponent);
}
	
#ifdef COMPILE_FORMULAS
void CFormula::buildExecutable(std::list<Token>& rpn) {
	double* nextConstant = constants;
	auto nextName = names;

	using namespace assembler;

	page = getCodePage();
	formula = (compiledCFormula*)page->getActivePage();

	Processor cpu(*page);
	FloatingPointUnit fpu(cpu);
	Register eax(cpu, EAX), ebx(cpu, EBX), ecx(cpu, ECX), edx(cpu, EDX), esp(cpu, ESP);
	Register xmm0(cpu, XMM0, sizeof(double) * 8);

	cpu.stackDepth = cpu.pushSize() * 4; //3 registers & return location

#ifdef FORMULA_64
	Register stack(cpu, R12);
	Register off(cpu, R13);

	//Push esp to align better for calling functions
	esp -= cpu.pushSize() * 8;
	cpu.push(esp);
	cpu.push(stack);
	cpu.push(off);

	Register arg1 = cpu.intArg64(0, 0);
	stack = arg1;

	size_t offset = cpu.stackDepth + cpu.pushSize() * 8;
	if(cpu.isIntArg64Register(3, 3)) {
		Register arg = as<void*>(cpu.intArg64(3, 3));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 3)) = arg;
	}
	else {
		as<void*>(eax) = as<void*>(*esp + offset + (cpu.pushSize() * 3));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 3)) = as<void*>(eax);
	}

	if(cpu.isIntArg64Register(4, 4)) {
		Register arg = as<void*>(cpu.intArg64(4, 4));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 4)) = arg;
	}
	else {
		as<void*>(eax) = as<void*>(*esp + offset + (cpu.pushSize() * 4));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 4)) = as<void*>(eax);
	}

	if(cpu.isIntArg64Register(5, 5)) {
		Register arg = as<void*>(cpu.intArg64(5, 5));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 5)) = arg;
	}
	else {
		as<void*>(eax) = as<void*>(*esp + offset + (cpu.pushSize() * 5));
		as<void*>(*esp + cpu.stackDepth + (cpu.pushSize() * 5)) = as<void*>(eax);
	}
#else
	Register stack(cpu, ESI);
	Register off(cpu, EDI);

	cpu.push(esp);
	cpu.push(stack);
	cpu.push(off);

	stack = as<void*>(*esp+cpu.stackDepth);
#endif
	
	off ^= off;

	bool topInFPU = false;

	auto prepTop = [&] {
		if(!topInFPU) {
			--off;
			fpu.load_double(*stack+off*8);
			topInFPU = true;
		}
	};

	while(!rpn.empty()) {
		auto& token = rpn.front();
		switch(token.type) {
		case TT_Constant:
			if(topInFPU) {
				fpu.store_double(*stack+off*8);
				++off;
			}
			fpu.load_double(MemAddress(cpu,nextConstant++));
			topInFPU = true;
			break;
		case TT_Variable: {
			if(topInFPU) {
				fpu.store_double(*stack+off*8);
				++off;
			}

#ifdef FORMULA_64
			Register arg1 = cpu.intArg64(0, 0);
			Register arg2 = cpu.intArg64(1, 1);

			eax = *esp + cpu.stackDepth + (cpu.pushSize() * 3);
			as<void*>(arg1) = *esp + cpu.stackDepth + (cpu.pushSize() * 4);
			as<void*>(arg2) = (void*)nextName++;

#ifdef _MSC_VER
			cpu.call_cdecl_prep(32);
			esp -= 32;
			cpu.call(eax);
			cpu.call_cdecl_end(32);
#else
			cpu.call_cdecl_prep(0);
			cpu.call(eax);
			cpu.call_cdecl_end(0);
#endif

			as<double>(*stack+off*8) = xmm0;
			topInFPU = false;
			++off;
#else
			eax = *esp + cpu.stackDepth + (cpu.pushSize() * 3);
			ecx = *esp + cpu.stackDepth + (cpu.pushSize() * 4);
			cpu.call_cdecl_prep(2 * cpu.pushSize());
			cpu.push((size_t)nextName++);
			cpu.push(ecx);
			cpu.call(eax);
			cpu.call_cdecl_end(2 * cpu.pushSize());
			//Doubles are returned on the FPU
			topInFPU = true;
#endif
			} break;
		case TT_Variable_Index: {
			if(topInFPU) {
				fpu.store_double(*stack+off*8);
				++off;
			}

#ifdef FORMULA_64
			Register arg1 = cpu.intArg64(0, 0);
			Register arg2 = cpu.intArg64(1, 1);

			eax = *esp + cpu.stackDepth + (cpu.pushSize() * 5);
			as<void*>(arg1) = *esp + cpu.stackDepth + (cpu.pushSize() * 4);
			as<int>(arg2) = (int)token.index;
			
#ifdef _MSC_VER
			cpu.call_cdecl_prep(32);
			esp -= 32;
			cpu.call(eax);
			cpu.call_cdecl_end(32);
#else
			cpu.call_cdecl_prep(0);
			cpu.call(eax);
			cpu.call_cdecl_end(0);
#endif

			as<double>(*stack+off*8) = xmm0;
			topInFPU = false;
			++off;
#else
			eax = *esp + cpu.stackDepth + (cpu.pushSize() * 5);
			ecx = *esp + cpu.stackDepth + (cpu.pushSize() * 4);
			cpu.call_cdecl_prep(2 * cpu.pushSize());
			cpu.push((int)token.index);
			cpu.push(ecx);
			cpu.call(eax);
			cpu.call_cdecl_end(2 * cpu.pushSize());
			//Doubles are returned on the FPU
			topInFPU = true;
#endif
			} break;
		case TT_Operator:
			switch(token.op) {
			case OT_Or: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1, false);

					void* test = cpu.prep_short_jump(assembler::Below);
					fpu.exchange(FPU_1);
					fpu.pop();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.pop();
					cpu.end_short_jump(skip);
				} break;
			case OT_And: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1, false);

					void* test = cpu.prep_short_jump(assembler::Below);
					fpu.pop();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.exchange(FPU_1);
					fpu.pop();
					cpu.end_short_jump(skip);
				} break;
			case OT_Less: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1);
					fpu.pop();

					void* test = cpu.prep_short_jump(assembler::Below);
					fpu.load_const_0();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.load_const_1();
					cpu.end_short_jump(skip);
				} break;
			case OT_LessEquals: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1);
					fpu.pop();

					void* test = cpu.prep_short_jump(assembler::NotAbove);
					fpu.load_const_0();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.load_const_1();
					cpu.end_short_jump(skip);
				} break;
			case OT_Greater: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1);
					fpu.pop();

					void* test = cpu.prep_short_jump(assembler::Above);
					fpu.load_const_0();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.load_const_1();
					cpu.end_short_jump(skip);
				} break;
			case OT_GreaterEquals: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1);
					fpu.pop();

					void* test = cpu.prep_short_jump(assembler::NotBelow);
					fpu.load_const_0();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.load_const_1();
					cpu.end_short_jump(skip);
				} break;
			case OT_Equals: {
					prepTop();
					--off;
					fpu.load_double(*stack+off*8);
					fpu.compare_toCPU(assembler::FPU_1);
					fpu.pop();

					void* test = cpu.prep_short_jump(assembler::Equal);
					fpu.load_const_0();
					void* skip = cpu.prep_short_jump(assembler::Jump);
					cpu.end_short_jump(test);
					fpu.load_const_1();
					cpu.end_short_jump(skip);
				} break;

			case OT_Add:
				prepTop();
				--off;
				fpu.add_double(*stack+off*8);
				break;
			case OT_Sub:
				prepTop();
				--off;
				fpu.sub_double(*stack+off*8,true);
				break;
			case OT_Mul:
				prepTop();
				--off;
				fpu.mult_double(*stack+off*8);
				break;
			case OT_Div:
				prepTop();
				--off;
				fpu.div_double(*stack+off*8,true);
				break;
			case OT_Pow: {
				if(topInFPU) {
					fpu.store_double(*stack+off*8);
					++off;
				}

				//Stack pointer
#ifdef FORMULA_64
				Register arg0 = as<void*>(cpu.intArg64(0, 0));
				arg0.copy_address(*stack+off*8);
				cpu.call_cdecl((void*) std::get<0>(formulaFunctions["pow"]),"rc",&arg0,2);
#else
				eax.copy_address(*stack+off*8);
				cpu.call_cdecl((void*) std::get<0>(formulaFunctions["pow"]),"rc",&eax,2);
#endif


#ifdef FORMULA_64
				--off;
				as<double>(*stack+off*8-8) = xmm0;
				topInFPU = false;
#else
				off -= 2;
				topInFPU = true;
#endif
				} break;
			case OT_Neg:
				prepTop();
				fpu.negate();
				break;
			case OT_Not: {
				prepTop();
				fpu.load_const_0();
				fpu.compare_toCPU(assembler::FPU_1);
				fpu.pop();

				void* test = cpu.prep_short_jump(assembler::NotBelow);
				fpu.load_const_0();
				void* skip = cpu.prep_short_jump(assembler::Jump);
				cpu.end_short_jump(test);
				fpu.load_const_1();
				cpu.end_short_jump(skip);
				} break;
			case OT_Func:
				if(topInFPU) {
					fpu.store_double(*stack+off*8);
					++off;
				}

				//Stack pointer
#ifdef FORMULA_64
				Register arg0 = as<void*>(cpu.intArg64(0, 0));
				arg0.copy_address(*stack+off*8);
				cpu.call_cdecl((void*) std::get<0>(formulaFunctions[token.name]),"rc",&arg0,token.args);
#else
				eax.copy_address(*stack+off*8);
				cpu.call_cdecl((void*) std::get<0>(formulaFunctions[token.name]),"rc",&eax,token.args);
#endif


#ifdef FORMULA_64
				if(token.args > 1)
					off -= token.args - 1;
				else if(token.args == 0)
					++off;
				as<double>(*stack+off*8-8) = xmm0;
				topInFPU = false;
#else
				if(token.args > 0)
					off -= token.args;
				topInFPU = true;
#endif
				break;
			}
			break;
		}
		rpn.pop_front();
	}

#ifdef FORMULA_64
	//Doubles are returned in xmm0
	if(topInFPU)
		fpu.store_double(*stack);
	xmm0 = *stack;
#else
	//Doubles are returned in the FPU
	if(!topInFPU)
		fpu.load_float(*stack);
#endif

	cpu.pop(off);
	cpu.pop(stack);
	cpu.pop(esp);
#ifdef FORMULA_64
	esp += cpu.pushSize() * 8;
#endif
	cpu.ret();

	page->markUsedAddress((void*)cpu.op);
}
#else
double CFormula::evaluateRPN(double* stack, varInterpreter VarConverter, void* user, varIndexInterpreter conv) {
	double* nextConstant = constants;
	auto nextName = names;

	--stack;
	for(auto it = rpn.begin(), end = rpn.end(); it != end; ++it) {
		auto& token = *it;
		switch(token.type) {
			case TT_Constant:
				*(++stack) = *(nextConstant++);
			break;
			case TT_Variable: {
				double value = VarConverter(user, nextName++);
				*(++stack) = value;
			} break;
			case TT_Variable_Index: {
				double value = conv(user, token.index);
				*(++stack) = value;
			} break;
			case TT_Operator: {
				switch(token.op) {
				case OT_Or: {
					double a = *(stack);
					double b = *(--stack);
					*stack = a > b ? a : b;
					} break;
				case OT_And: {
					double a = *(stack);
					double b = *(--stack);
					*stack = a < b ? a : b;
					} break;
				case OT_Less: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y < x ? 1.0 : 0.0;
					} break;
				case OT_LessEquals: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y <= x ? 1.0 : 0.0;
					} break;
				case OT_Greater: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y > x ? 1.0 : 0.0;
					} break;
				case OT_GreaterEquals: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y >= x ? 1.0 : 0.0;
					} break;
				case OT_Equals: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y == x ? 1.0 : 0.0;
					} break;
				case OT_Add: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y + x;
					} break;
				case OT_Sub: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y - x;
					} break;
				case OT_Mul: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y * x;
					} break;
				case OT_Div: {
					double x = *(stack);
					double y = *(--stack);

					*stack = y / x;
					} break;
				case OT_Pow: {
					double x = *(stack);
					double y = *(--stack);

					*stack = pow(y, x);
					} break;
				case OT_Neg: {
					double x = *(stack);
					*stack = -x;
					} break;
				case OT_Not: {
					*stack = *(stack) > 0.0 ? 0.0 : 1.0;
					} break;
				case OT_Func: {
					double r = std::get<0>(formulaFunctions[token.name])(stack, token.args);
					stack -= int(token.args) - 1;
					*stack = r;
					} break;

				}
				break;
			}
		}
	}

	return *(stack);
}
#endif

void CFormula::validateRPN(const std::list<Token>& tokens) {
	int stackDepth = 0;

	for(auto i = tokens.begin(), end = tokens.end(); i != end; ++i) {
		stackDepth += i->getStackChange();
		if(stackDepth > (int)FormulaStackSize)
			throw FormulaError("Formula too complex");
		else if(stackDepth <= 0)
			throw FormulaError("Mismatched operator");
	}

	if(stackDepth != 1)
		throw FormulaError("Unused variables/constants");
}

void CFormula::buildCaches(const std::list<Token>& tokens, double** constants, const std::string** names) {
	std::vector<double> constantCache;
	std::vector<const std::string*> stringRefs;
	for(auto i = tokens.begin(), end = tokens.end(); i != end; ++i) {
		switch(i->type) {
		case TT_Constant:
			constantCache.push_back(i->value);
			break;
		case TT_Variable:
			stringRefs.push_back(&i->name);
			break;
		}
	}

	if(!constantCache.empty()) {
		*constants = new double[constantCache.size()];
		for(unsigned i = 0; i < constantCache.size(); ++i)
			(*constants)[i] = constantCache[i];
	}
	else {
		*constants = nullptr;
	}

	if(!stringRefs.empty()) {
		std::string* strings = new std::string[stringRefs.size()];
		for(unsigned i = 0; i < stringRefs.size(); ++i)
			strings[i] = *stringRefs[i];
		*names = strings;
	}
	else {
		*names = nullptr;
	}
}

void CFormula::optimizeRPN(std::list<Token>& rpn) {
	unsigned cnt = rpn.size();

	auto i = rpn.begin();
	unsigned index = 0;
	
	index = 0;
	//Look for <constant> <constant> <operator> to precalculate
	while(index + 2 < cnt) {
		auto c1 = i;
		auto c2 = c1; ++c2;
		auto o = c2; ++o;

		if(c1->type != TT_Constant || c2->type != TT_Constant
			|| o->type != TT_Operator) {
			++i; ++index;
			continue;
		}

		switch(o->op) {
		case OT_Or:
			c1->value = c1->value > c2->value ? c1->value : c2->value; break;
		case OT_And:
			c1->value = c1->value < c2->value ? c1->value : c2->value; break;
		case OT_Less:
			c1->value = c1->value < c2->value ? 1.0 : 0.0; break;
		case OT_LessEquals:
			c1->value = c1->value <= c2->value ? 1.0 : 0.0; break;
		case OT_Greater:
			c1->value = c1->value > c2->value ? 1.0 : 0.0; break;
		case OT_GreaterEquals:
			c1->value = c1->value >= c2->value ? 1.0 : 0.0; break;
		case OT_Equals:
			c1->value = c1->value == c2->value ? 1.0 : 0.0; break;
		case OT_Add:
			c1->value = c1->value + c2->value; break;
		case OT_Sub:
			c1->value = c1->value - c2->value; break;
		case OT_Mul:
			c1->value = c1->value * c2->value; break;
		case OT_Div:
			if(c2->value == 0.0)
				throw FormulaError("Division by 0");
			c1->value = c1->value / c2->value; break;
		case OT_Pow:
			c1->value = pow(c1->value,c2->value); break;
		default:
			//Can't handle this operator (probably a function)
			++i; ++index; continue;
		}

		rpn.erase(c2, ++o);
		cnt -= 2;

		if(index > 0) {
			--i; --index;
		}
	}

	//Look for <constant> <divide>, change to 1/<constant> <multiply>
	// Also look for division by a constant of 0
	while(index + 1 < cnt) {
		auto c1 = i;
		auto o = c1; ++o;
		if(c1->type != TT_Constant ||
			o->type != TT_Operator || o->op != OT_Div) {
			++i; ++index;
			continue;
		}

		if(c1->value == 0.0)
			throw FormulaError("Division by 0");

		c1->value = 1.0 / c1->value;
		o->op = OT_Mul;
	}
}

void CFormula::convertInfix(const char* expression, std::list<Token>& rpn, varIndexConverter conv) {
	prepareFormulaFunctions();

	{
		static std::unordered_map<std::string,OperatorType> operatorTokens;
		if(operatorTokens.empty()) {
			operatorTokens["||"] = OT_Or;
			operatorTokens["&&"] = OT_And;
			operatorTokens["<"] = OT_Less;
			operatorTokens["<="] = OT_LessEquals;
			operatorTokens[">"] = OT_Greater;
			operatorTokens[">="] = OT_GreaterEquals;
			operatorTokens["=="] = OT_Equals;
			operatorTokens["+"] = OT_Add;
			operatorTokens["-"] = OT_Sub;
			operatorTokens["*"] = OT_Mul;
			operatorTokens["/"] = OT_Div;
			operatorTokens["^"] = OT_Pow;
			operatorTokens["!"] = OT_Not;
		}

		std::list<Token> tokens;
		{
			Token token; token.type = TT_Invalid;
			std::string tokenText;

			auto push = [&](TokenType newType) {
				switch(token.type) {
				case TT_Constant:
					token.value = atof(tokenText.c_str());
					if(!tokens.empty() && tokens.back() == OT_Neg) {
						tokens.pop_back();
						token.value *= -1;
					}
					break;
				case TT_Variable:
					token.name = tokenText;
					break;
				case TT_Operator:
					//Split the operator into sub-operators
					while(!tokenText.empty()) {
						Token opToken;
						opToken.type = TT_Operator;

						//Parse progressively smaller chunks to find operators, error when there are no matches
						unsigned i;
						for(i = tokenText.size(); i > 0; --i) {
							auto op = tokenText.substr(0, i);
							auto tt = operatorTokens.find(op);
							if(tt != operatorTokens.end()) {
								opToken.op = tt->second;
								tokenText = tokenText.erase(0,i);
								goto addOperator;
							}
						}

						throw FormulaError(std::string("Invalid operator: " + tokenText));
					addOperator:
						if(opToken.op == OT_Sub) {
							if(tokens.empty()) {
								opToken.op = OT_Neg;
							}
							else {
								auto& prevToken = tokens.back();
								if(	 prevToken == TT_Operator ||
									(prevToken == TT_Bracket && prevToken.open)) {
										opToken.op = OT_Neg;
								}
							}
						}
						tokens.push_back(opToken);
					}

					//We handle this in a different way, avoid pushing it
					token.type = TT_Invalid;
					break;
				case TT_Bracket:
					token.open = (tokenText == "(");

					//Convert "variable(" to function call
					if(token.open && !tokens.empty() && tokens.back() == TT_Variable) {
						auto& func = tokens.back();

						if(formulaFunctions.find(func.name) == formulaFunctions.end())
							throw FormulaError(std::string("Invalid function name: ") + func.name);
						func.type = TT_Operator;
						func.op = OT_Func;
						func.args = 0;
					}
					break;
				}

				if(token.type != TT_Invalid)
					tokens.push_back(token);

				token.type = newType;
				token.name.clear();
				token.value = 0;
				tokenText.clear();
			};

			while(char c = *expression) {
				TokenType newType = TT_Invalid;
				if(c >= '0' && c <= '9')
					newType = TT_Constant;
				else {
					switch(c) {
					case '-': case '+':
						//Handle constants like "4e-2" and "16E+3"
						if(token == TT_Constant && tolower(tokenText.back()) == 'e') {
							newType = TT_Constant;
							break;
						}
					case '/': case '*': case '^': case '<': case '>': case '=':
					case '|': case '&': case '!':
						newType = TT_Operator; break;
					case '(': case ')':
						newType = TT_Bracket; break;
					case ' ': case '\t':
						newType = TT_Invalid; break;
					case ',':
						newType = TT_Comma; break;
					case '.':
						//Support "A.B" syntax for variable names
						if(token == TT_Variable)
							newType = TT_Variable;
						else
							newType = TT_Constant;
						break;
					default:
						newType = TT_Variable;
					}
				}

				//Push tokens when the type has changed, or for each character for specific types
				if(newType != token.type || token == TT_Bracket || token == TT_Comma)
					push(newType);

				tokenText.append(1,c);

				++expression;
			}

			push(TT_Invalid);
		}

		std::list<Token> opStack;

		while(!tokens.empty()) {
			Token token = tokens.front(); tokens.pop_front();
			switch(token.type) {
			case TT_Constant:
				rpn.push_back(token);
				break;
			case TT_Variable: {
				auto it = formulaConstants.find(token.name);
				if(it != formulaConstants.end()) {
					token.type = TT_Constant;
					token.value = it->second;
				}
				else if(conv != 0) {
					int index = conv(&token.name);
					if(index != -1) {
						token.type = TT_Variable_Index;
						token.index = index;
					}
				}
				rpn.push_back(token);
			} break;
			case TT_Operator:
				while(!opStack.empty()) {
					const auto& topOp = opStack.back();
					if(topOp == TT_Operator && !token.takesPrecendenceOver(topOp)) {
						rpn.push_back(topOp);
						opStack.pop_back();
					}
					else {
						break;
					}
				}
				opStack.push_back(token);
				break;
			case TT_Bracket:
				if(token.open) {
					//Setup the function's arg count based on the presence/abscense of an immediate ')'
					if(!opStack.empty()) {
						auto& func = opStack.back();
						if(func == TT_Operator && func.op == OT_Func)
							func.args = !tokens.empty() && (tokens.front().type != TT_Bracket || tokens.front().open) ? 1 : 0;
					}
					opStack.push_back(token);
				}
				else {
					//Pop the stack to the output until we find a (
					bool foundBracket = false;
					while(!opStack.empty()) {
						auto& op = opStack.back();
						if(op == TT_Bracket) {
							opStack.pop_back();
							foundBracket = true;

							//Handle function calls (pop from stack to output)
							if(!opStack.empty() && opStack.back() == TT_Operator && opStack.back().op == OT_Func) {
								Token func = opStack.back();
								opStack.pop_back();
								rpn.push_back(func);

								unsigned expectedArgs = std::get<1>(formulaFunctions[func.name]);
								if(func.args < expectedArgs)
									throw FormulaError(std::string("Too few arguments to " + func.name));
								else if(func.args > expectedArgs)
									throw FormulaError(std::string("Too many arguments to " + func.name));
							}
							break;
						}
						rpn.push_back(op);
						opStack.pop_back();
					}
					if(!foundBracket)
						throw FormulaError("Mismatched ')'");
				}
				break;
			case TT_Comma:
				//Pop the stack to the output until we find a (
				while(!opStack.empty()) {
					auto& op = opStack.back();
					if(op == TT_Bracket) {
						//Increment the related function's argument count by 1
						if(opStack.size() == 1)
							throw FormulaError("Found ',' outside of function call");
						auto& func = *++opStack.rbegin();
						if(func.type != TT_Operator || func.op != OT_Func)
							throw FormulaError("Found ',' outside of function call");
						func.args += 1;
						break;
					}
					rpn.push_back(op);
					opStack.pop_back();
				}
				break;
			}
		}

		while(!opStack.empty()) {
			if(opStack.back().type == TT_Bracket)
				throw FormulaError("Mismatched '('");
			rpn.push_back(opStack.back());
			opStack.pop_back();
		}
	}
}

double f_abs(double* stack, unsigned args) {
	return fabs(stack[-1]);
}

double f_ceil(double* stack, unsigned args) {
	return ceil(stack[-1]);
}

double f_floor(double* stack, unsigned args) {
	return floor(stack[-1]);
}

double f_round(double* stack, unsigned args) {
	return floor(stack[-1] + 0.5);
}

double f_sqrt(double* stack, unsigned args) {
	return sqrt(stack[-1]);
}

double f_log10(double* stack, unsigned args) {
	return log10(stack[-1]);
}

double f_log(double* stack, unsigned args) {
	return log(stack[-1]);
}

double f_exp(double* stack, unsigned args) {
	return exp(stack[-1]);
}

double f_max(double* stack, unsigned args) {
	if(stack[-1] > stack[-2])
		return stack[-1];
	else
		return stack[-2];
}

double f_min(double* stack, unsigned args) {
	if(stack[-1] < stack[-2])
		return stack[-1];
	else
		return stack[-2];
}

double f_pow(double* stack, unsigned args) {
	return pow(stack[-2], stack[-1]);
}

//interp(percent, from, to)
double f_interp(double* stack, unsigned args) {
	return stack[-3] * (stack[-1] - stack[-2]) + stack[-2];
}

double f_if(double* stack, unsigned args) {
	return stack[-3] != 0.0 ? stack[-2] : stack[-1];
}

double f_bool(double* stack, unsigned args) {
	return stack[-1] != 0.0 ? 1.0 : 0.0;
}

void prepareFormulaFunctions() {
	if(formulaFunctions.empty()) {
		formulaFunctions["abs"] = formulaFuncDef(&f_abs,1);
		formulaFunctions["ceil"] = formulaFuncDef(&f_ceil,1);
		formulaFunctions["floor"] = formulaFuncDef(&f_floor,1);
		formulaFunctions["round"] = formulaFuncDef(&f_round,1);
		formulaFunctions["sqrt"] = formulaFuncDef(&f_sqrt,1);
		formulaFunctions["log10"] = formulaFuncDef(&f_log10,1);
		formulaFunctions["log"] = formulaFuncDef(&f_log,1);
		formulaFunctions["exp"] = formulaFuncDef(&f_exp,1);
		formulaFunctions["max"] = formulaFuncDef(&f_max,2);
		formulaFunctions["min"] = formulaFuncDef(&f_min,2);
		formulaFunctions["pow"] = formulaFuncDef(&f_pow,2);
		formulaFunctions["interp"] = formulaFuncDef(&f_interp,3);
		formulaFunctions["if"] = formulaFuncDef(&f_if,3);
		formulaFunctions["bool"] = formulaFuncDef(&f_bool,1);
	}

	if(formulaConstants.empty()) {
		formulaConstants["pi"] = pi;
		formulaConstants["twopi"] = twopi;
	}
}
