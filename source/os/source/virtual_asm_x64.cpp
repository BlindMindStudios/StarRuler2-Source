#include "virtual_asm.h"
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stack>
#include <stdio.h>
#include <unordered_set>

//See http://ref.x86asm.net/coder32.html for a list of x86 opcode bytes

namespace assembler {

enum OpExtension : byte {
	EX_0 = 0,
	EX_1 = 1,
	EX_2 = 2,
	EX_3 = 3,
	EX_4 = 4,
	EX_5 = 5,
	EX_6 = 6,
	EX_7 = 7,
};

enum ModBits : byte {
	ADR = 0,
	ADR8 = 1,
	ADR32 = 2,
	REG = 3
};

enum IndexScale : byte {
	Scale1 = 0,
	Scale2 = 1,
	Scale4 = 2,
	Scale8 = 3
};

unsigned char mod_rm(unsigned char Reg, unsigned char Mod, unsigned char RM) {
	return (Mod<<6) | (Reg<<3) | RM;
}

unsigned char sib(unsigned char ScaledIndex, unsigned char Mode, unsigned char BaseReg) {
	return (Mode<<6) | (ScaledIndex<<3) | BaseReg;
}

struct Argument {
	Register* reg;
	MemAddress* mem;
	uint64_t constant;
	bool is32;
	Argument(Register* r) : reg(r), mem(0) {}
	Argument(MemAddress* m) : reg(0), mem(m) {}
	Argument(unsigned Constant32) : reg(0), mem(0), constant(Constant32), is32(true) {}
	Argument(uint64_t Constant) : reg(0), mem(0), constant(Constant), is32(false) {}
};

void moveToUpperDWORD(MemAddress& address) {
	if(address.absolute_address == 0)
		address.offset += 4;
	else
		address.absolute_address = (byte*)address.absolute_address + 4;
}

AddrPrefix MemAddress::prefix(unsigned char further, bool defLong) {
	return AddrPrefix(*this, defLong, further);
}

template<>
MemAddress as<float>(MemAddress addr) {
	addr.bitMode = sizeof(float) * 8;
	addr.Signed = true;
	addr.Float = true;
	return addr;
}

template<>
MemAddress as<double>(MemAddress addr) {
	addr.bitMode = sizeof(double) * 8;
	addr.Signed = true;
	addr.Float = true;
	return addr;
}

unsigned Processor::pushSize() {
	return sizeof(void*);
}

void Processor::call_cdecl_prep(unsigned argBytes) {
	unsigned stackOffset = (stackDepth + argBytes) % 16;
	Register esp(*this, ESP, sizeof(void*) * 8);
	if(stackOffset != 0)
		esp -= 16 - stackOffset;
}

void Processor::call_cdecl_end(unsigned argBytes, bool returnPointer) {
	Register esp(*this, ESP, sizeof(void*) * 8);
	unsigned stackOffset = (stackDepth + argBytes) % 16;
	if(stackOffset != 0)
		argBytes += (16 - stackOffset);
#ifndef _MSC_VER
	if(returnPointer)
		argBytes -= 4;
#endif
	if(argBytes != 0)
		esp += argBytes;
}

unsigned Processor::call_cdecl_args(const char* args, va_list ap) {
	return call_thiscall_args(0, args, ap);
}

unsigned Processor::call_thiscall_args(Register* obj, const char* args, va_list ap) {
	std::stack<Argument> arg_stack;
	std::unordered_set<unsigned char> used_regs;
	Register esp(*this, ESP, sizeof(void*) * 8);

	unsigned argCount = 0, floatCount = 0, intCount = 0, regCount = 0, stackBytes = 0;

	//Set the object as first argument
	if(obj) {
		if(!isIntArg64Register(intCount, argCount))
			stackBytes += pushSize();
		++argCount;
		++intCount;
		arg_stack.push(obj);
	}

	//Read the arguments in...
	while(args && *args != '\0') {
		if(*args == 'r') {
			Register* reg = va_arg(ap,Register*);
			if(reg->xmm()) {
				if(!isFloatArg64Register(floatCount, argCount))
					stackBytes += pushSize();
				++floatCount;
			}
			else {
				if(!isIntArg64Register(intCount, argCount))
					stackBytes += pushSize();
				++intCount;
			}
			++regCount;
			arg_stack.push(reg);
		}
		else if(*args == 'm') {
			MemAddress* adr = va_arg(ap,MemAddress*);
			if(adr->Float) {
				if(!isFloatArg64Register(floatCount, argCount))
					stackBytes += pushSize();
				++floatCount;
			}
			else {
				if(!isIntArg64Register(intCount, argCount))
					stackBytes += pushSize();
				++intCount;
			}
			arg_stack.push(adr);
		}
		else if(*args == 'p') {
			if(!isIntArg64Register(intCount, argCount))
				stackBytes += pushSize();
			arg_stack.push(va_arg(ap,uint64_t));
			++intCount;
		}
		else if(*args == 'c') {
			if(!isIntArg64Register(intCount, argCount))
				stackBytes += pushSize();
			arg_stack.push(va_arg(ap,unsigned));
			++intCount;
		}
		else
			throw 0;
		++argCount;
		++args;
	}

#ifdef _MSC_VER
	if(stackBytes < 32)
		stackBytes = 32;
#endif

	call_cdecl_prep(stackBytes);

	unsigned intA = intCount - 1, floatA = floatCount - 1, a = argCount - 1;

	//Then push them in reverse order
	while(!arg_stack.empty()) {
		auto& arg = arg_stack.top();

		if(arg.reg) {
			Register reg = *arg.reg;

			if(reg.code == ESP || reg.code == R15)
				throw "Cannot use this register for cdecl call wrapper.";

			if(reg.xmm()) {
				if(isFloatArg64Register(floatA, a)) {
					Register other = floatArg64(floatA, a);
					other.bitMode = reg.bitMode;

					if(other.code != reg.code) {
						if(used_regs.find(reg.code) != used_regs.end())
							throw "Invalid out-of-order use of argument register.";
						other = reg;
					}

					used_regs.insert(other.code);
				}
				else {
					if(used_regs.find(reg.code) != used_regs.end())
						throw "Invalid out-of-order use of argument register.";
					esp -= pushSize();
					MemAddress adr = *esp;
					adr.bitMode = reg.bitMode;

					adr = reg;
				}
				--floatA;
			}
			else {
				if(isIntArg64Register(intA, a)) {
					Register other = intArg64(intA, a);
					other.bitMode = reg.bitMode;

					if(other.code != reg.code) {
						if(used_regs.find(reg.code) != used_regs.end())
							throw "Invalid out-of-order use of argument register.";
						other = reg;
					}

					used_regs.insert(other.code);
				}
				else {
					if(used_regs.find(reg.code) != used_regs.end())
						throw "Invalid out-of-order use of argument register.";
					push(reg);
				}
				--intA;
			}
		}
		else if(arg.mem) {
			MemAddress addr = *arg.mem;

			if(argCount > 1) {
				for(unsigned i = 0; i < maxIntArgs64(); ++i) {
					if(addr.code == intArg64(i, i).code)
						throw "Cannot use this register for cdecl call wrapper address.";
					if(addr.other == intArg64(i, i).code)
						throw "Cannot use this register for cdecl call wrapper address.";
					if(addr.scaleFactor != 0 && addr.scaleReg == intArg64(i, i).code)
						throw "Cannot use this register for cdecl call wrapper address.";
				}
			}
			if(addr.code == R15 || addr.other == R15 || (addr.scaleFactor != 0 && addr.scaleReg == R15))
				throw "Cannot use this register for cdecl call wrapper address.";
			if(addr.other == ESP)
				throw "Cannot use this register for cdecl call wrapper address.";
			if(addr.code == ESP) {
				addr.code = R15;
				addr.offset += pushSize();
			}

			if(addr.Float) {
				if(isFloatArg64Register(floatA, a)) {
					Register reg = floatArg64(floatA, a);
					reg.bitMode = addr.bitMode;

					reg = addr;
				}
				else {
					push(addr);
				}
				--floatA;
			}
			else {
				if(isIntArg64Register(intA, a)) {
					Register reg = intArg64(intA, a);
					reg.bitMode = addr.bitMode;

					reg = addr;
				}
				else {
					push(addr);
				}
				--intA;
			}
		}
		else {
			if(isIntArg64Register(intA, a)) {
				Register reg = intArg64(intA, a);
				if(arg.is32)
					reg.bitMode = 32;
				else
					reg.bitMode = 64;
				reg = arg.constant;
			}
			else {
				push(arg.constant);
			}
			--intA;
		}
			

		arg_stack.pop();
		--a;
	}

#ifdef _MSC_VER
	esp -= 32;
#endif

	return stackBytes;
}

void Processor::call_cdecl(void* func, const char* args, va_list ap) {
	unsigned stackBytes = call_cdecl_args(args, ap);
	call(func);
	call_cdecl_end(stackBytes);
}

unsigned Processor::call_cdecl_args(const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		unsigned r = call_cdecl_args(args, ap);
	va_end(ap);
	return r;
}

void Processor::call_cdecl(void* func, const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		call_cdecl(func, args, ap);
	va_end(ap);
}

unsigned Processor::call_thiscall_args(Register* obj, const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		unsigned r = call_thiscall_args(obj, args, ap);
	va_end(ap);
	return r;
}

void Processor::call_stdcall(void* func, const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		call_cdecl(func, args, ap);
	va_end(ap);
}

Processor::Processor(CodePage& codePage, unsigned defaultBitMode ) {
	op = codePage.getActivePage();
	pageStart = op;
	bitMode = defaultBitMode;
	lastBitMode = bitMode;
	stackDepth = pushSize();
	jumpSpace = 0;
}

void Processor::migrate(CodePage& prevPage, CodePage& newPage) {
	jump(Jump,newPage.getActivePage());
	jumpPtr = op;
	op += jumpSpace;
	prevPage.markUsedAddress((void*)op);
	op = newPage.getActivePage();
	pageStart = op;
	jumpSpace = 0;
}

template<>
Processor& Processor::operator<<(MemAddress addr) {
	if(addr.absolute_address != 0) {
		if((size_t)addr.absolute_address <= INT_MAX) {
			//Normal 32 bit address needs a none sib byte
			return *this << mod_rm(addr.other % 8, ADR, SIB) << sib(0x4, 0, ADDR) << (int)(size_t)addr.absolute_address;
		}
		else {
			//Take 64 bit absolute address from R11
			return *this << mod_rm(addr.other % 8, ADR, R11 % 8);
		}
	}

	if(addr.scaleFactor != 0) {
		IndexScale scale;
		switch(addr.scaleFactor) {
		case 1:
			scale = Scale1; break;
		case 2:
			scale = Scale2; break;
		case 4:
			scale = Scale4; break;
		case 8:
			scale = Scale8; break;
		default: throw 0;
		}

		//Can't scale with an offset from ESP
		if(addr.scaleReg % 8 == ESP)
			throw 0;

		//EBP/R13 doesn't have an ADR mode, so use ADR8 and append a 0
		if(addr.offset == 0 && addr.code % 8 != EBP)
			return *this << mod_rm(addr.other % 8, ADR, SIB) << sib(addr.scaleReg % 8, scale, addr.code % 8);
		else if(addr.offset >= CHAR_MIN && addr.offset <= CHAR_MAX)
			return *this << mod_rm(addr.other % 8, ADR8, SIB) << sib(addr.scaleReg % 8, scale, addr.code % 8) << (char)addr.offset;
		else
			return *this << mod_rm(addr.other % 8, ADR32, SIB) << sib(addr.scaleReg % 8, scale, addr.code % 8) << addr.offset;
	}

	if(addr.offset == 0 && addr.code % 8 != EBP) { //[EBP] means absolute address, so we use [EBP+0] instead
		*this << mod_rm(addr.other % 8, ADR, addr.code % 8);
		if(addr.code % 8 == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
	}
	else if(addr.offset >= CHAR_MIN && addr.offset <= CHAR_MAX) {
		*this << mod_rm(addr.other % 8, ADR8, addr.code % 8);
		if(addr.code % 8 == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
		*this << (char)addr.offset;
	}
	else {
		*this << mod_rm(addr.other % 8, ADR32, addr.code % 8);
		if(addr.code % 8 == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
		*this << addr.offset;
	}
	return *this;
}

template<>
Processor& Processor::operator<<(AddrPrefix pr) {
	MemAddress& adr = pr.adr;

	//64 bit absolute addresses need to mangle a register in order to work
	if((size_t)adr.absolute_address > (size_t)INT_MAX) {
		*this << '\x49' << '\xBB' << (uint64_t)adr.absolute_address;
		adr.code = R11;
	}

	//Further prefixes that need to be before the REX byte
	if(pr.further != 0)
		*this << pr.further;

	//64 bit prefix
	unsigned char ch = '\x40';
	if(!pr.defLong) {
		if(adr.bitMode == 64)
			ch |= '\x08';
	}
	if((adr.code % 16) > 7)
		ch |= '\x01';
	if((adr.other % 16) > 7)
		ch |= '\x04';
	if(adr.scaleReg > 7)
		ch |= '\x02';
	if(ch != '\x40')
		*this << ch;
	return *this;
}

template<>
Processor& Processor::operator<<(RegPrefix pr) {
	Register& reg = pr.reg;
	unsigned short other = pr.other;

	unsigned char ch = '\x40';
	if(!pr.defLong) {
		if(reg.getBitMode() == 64)
			ch |= '\x08';
	}
	if((reg.code % 16) > 7)
		ch |= '\x01';
	if((other % 16) > 7)
		ch |= '\x04';

	if(ch != '\x40')
		*this << ch;
	return *this;
}

void Processor::push(Register& reg) {
	*this << reg.prefix(EX_0, true) << byte(0x50u+(reg.code % 8));
}

void Processor::pop(Register& reg) {
	*this << reg.prefix(EX_0, true) << byte(0x58u+(reg.code % 8));
}

void Processor::push(MemAddress address) {
	address.other = EX_6;
	*this << address.prefix() << '\xFF' << address;
}

void Processor::pop(MemAddress address) {
	address.other = EX_0;
	*this << address.prefix() << '\x8F' << address;
}

void Processor::push(size_t value) {
	if(value <= CHAR_MAX)
		*this << '\x6A' << (byte)value;
	else
		*this << '\x48' << '\x68' << (long long)value;
}

void Processor::pop(unsigned int count) {
	Register esp(*this, ESP);
	esp += count * pushSize();
}

void Processor::call(Register& reg) {
	*this << reg.prefix() << '\xFF' << reg.modrm(EX_2);
}

void Processor::call(void* func) {
	int64_t offset = ((byte*)func - op) - 5;
	if(offset < (int64_t)INT_MIN || offset > (int64_t)INT_MAX) {
		uint64_t abs = (uint64_t)func;
		if(abs > (uint64_t)UINT_MAX)
			*this << '\x49' << '\xBB' << abs;
		else //0-extend small actual addresses
			*this << '\x41' << '\xBB' << (unsigned)abs;
		*this << '\x49' << '\xFF' << mod_rm(EX_2,REG,R11 % 8);
	}
	else {
		*this << '\xE8' << (int)offset;
	}
}

unsigned char shortJumpCodes[JumpTypeCount] = { 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0xEB};
unsigned char longJumpCodes[JumpTypeCount] = { 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0xE9 };

void* Processor::prep_short_jump(JumpType type) {
	*this << shortJumpCodes[type];
	void* ret = (void*)op;
	*this << (char)0;
	return ret;
}

void Processor::end_short_jump(void* p) {
	volatile byte* jumpFrom = (volatile byte*)p;
	int64_t offset = ((size_t)op - (size_t)jumpFrom) - 1;
	if(offset < CHAR_MIN || offset > CHAR_MAX)
		throw "Short jump too long.";
	*jumpFrom = (char)offset;
}

void* Processor::prep_long_jump(JumpType type) {
	if(type != Jump)
		*this << '\x0F';
	*this << longJumpCodes[type];
	void* ret = (void*)op;
	*this << (int)0;
	jumpSpace += 16;
	return ret;
}

void Processor::end_long_jump(void* p) {
	volatile byte* jumpFrom = (volatile byte*)p;
	bool isSamePage = (size_t)jumpFrom >= (size_t)pageStart && (size_t)jumpFrom < (size_t)op;
	int64_t offset = ((size_t)op - (size_t)jumpFrom) - 4;
	if(offset < (int64_t)INT_MIN || offset > (int64_t)INT_MAX) {
		if(isSamePage)
			throw "Inside-page long jump too long. This should never ever happen, somebody screwed the pooch.";
		Register reg(*this, R11, sizeof(void*));
		auto* prevOp = op;
		op = jumpPtr;

		reg = (void*)prevOp;
		*this << reg.prefix(EX_4) << '\xFF' << reg.modrm(EX_4);

		offset = ((size_t)jumpPtr - (size_t)jumpFrom) - 4;
		if(offset < (int64_t)INT_MIN || offset > (int64_t)INT_MAX)
			throw "Multi-page drifting! Can't recover from this.";
		*(volatile int*)jumpFrom = (int)offset;

		jumpPtr = op;
		op = prevOp;
		return;
	}
	*(volatile int*)jumpFrom = (int)offset;
	if(isSamePage)
		jumpSpace -= 16;
}

void Processor::jump(JumpType type, volatile byte* dest) {
	int64_t offset = ((size_t)dest - (size_t)op) - 2;
	if(offset >= CHAR_MIN && offset <= CHAR_MAX)
		*this << shortJumpCodes[type] << (char)offset;
	else if (offset > INT_MAX || offset < INT_MIN) {
		Register reg(*this, R11, sizeof(void*));
		reg = (void*)dest;
		jump(reg);
	}
	else if(type == Jump)
		*this << longJumpCodes[Jump] << (int)(offset-3); //Long jump is 3 bytes larger, jump is from the end of the full opcode
	else
		*this << '\x0F' << longJumpCodes[type] << (int)(offset-4); //Conditional long jump is 4 bytes larger, jump is from the end of the full opcode
}

void Processor::jump(Register& reg) {
	*this << reg.prefix(EX_4) << '\xFF' << reg.modrm(EX_4);
}

void Processor::loop(volatile byte* dest, JumpType type) {
	int64_t off = dest - op - 2;
	if(off < CHAR_MIN || off > CHAR_MAX)
		throw "Loop offset too far.";

	if(type == Jump)
		*this << '\xE2' << (char)off;
	else if(type == Zero)
		*this << '\xE1' << (char)off;
	else if(type == NotZero)
		*this << '\xE0' << (char)off;
	else
		throw "Unsupported loop type.";
}

void Processor::string_copy(unsigned size) {
	if(size == 1)
		*this << '\xA4';
	else if(size == 2)
		*this << '\x66' << '\xA5';
	else if(size == 4)
		*this << '\xA5';
	else if(size == 8)
		*this << '\x48' << '\xA5';
	else
		throw "Invalid string copy step size.";
}

void Processor::setDirFlag(bool forward) {
	if(forward)
		*this << '\xFC';
	else
		*this << '\xFD';
}

void Processor::ret() {
	*this << '\xC3';
}

void Processor::debug_interrupt() {
	*this << '\xCC';
}

MemAddress::MemAddress(Processor& CPU, void* address)
	: cpu(CPU), code(ESP), absolute_address(address), other(NONE),
	offset(0), bitMode(cpu.bitMode), Float(false), Signed(false), scaleFactor(0), scaleReg(NONE) {}

MemAddress::MemAddress(Processor& CPU, RegCode Code)
	: cpu(CPU), code(Code), absolute_address(0), other(NONE),
	offset(0), bitMode(cpu.bitMode), Float(false), Signed(false), scaleFactor(0), scaleReg(NONE) {}

MemAddress::MemAddress(Processor& CPU, RegCode Code, int Offset)
	: cpu(CPU), code(Code), absolute_address(0), other(NONE),
	offset(Offset), bitMode(cpu.bitMode), Float(false), Signed(false), scaleFactor(0), scaleReg(NONE) {}

MemAddress MemAddress::operator+(ScaledIndex scale) {
	scaleReg = scale.reg;
	scaleFactor = scale.scaleFactor;
	return *this;
}

MemAddress MemAddress::operator+(int Offset) {
	offset += Offset;
	return *this;
}

MemAddress MemAddress::operator-(int Offset) {
	offset -= Offset;
	return *this;
}

void MemAddress::operator++() {
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\xFE' << *this; break;
	case 16:
		cpu << prefix('\x66') << '\xFF' << *this; break;
	default:
		cpu << prefix() << '\xFF' << *this; break;
	}
}

void MemAddress::operator--() {
	other = EX_1;
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\xFE' << *this; break;
	case 16:
		cpu << prefix('\x66') << '\xFF' << *this; break;
	default:
		cpu << prefix() << '\xFF' << *this; break;
	}
}

void MemAddress::operator-() {
	other = EX_3;
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\xF6' << *this; break;
	case 16:
		cpu << prefix('\x66') << '\xF7' << *this; break;
	default:
		cpu << prefix() << '\xF7' << *this; break;
	}
}

void MemAddress::operator~() {
	other = EX_2;
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\xF6' << *this; break;
	case 16:
		cpu << prefix('\x66') << '\xF7' << *this; break;
	default:
		cpu << prefix() << '\xF7' << *this; break;
	}
}

void MemAddress::operator+=(unsigned int amount) {
	if(amount == 0) return;

	if(code == EAX)
		cpu << '\x05' << amount;
	else if(amount <= CHAR_MAX)
		cpu << prefix() << '\x83' << *this << (byte)amount;
	else
		cpu << prefix() << '\x81' << *this << amount;
}

void MemAddress::operator-=(unsigned int amount) {
	if(amount == 0) return;

	other = (RegCode)EX_5;
	if(code == EAX)
		cpu << '\x2D' << amount;
	else if(amount <= CHAR_MAX)
		cpu << prefix() << '\x83' << *this << (byte)amount;
	else
		cpu << prefix() << '\x81' << *this << amount;
}

void MemAddress::operator=(unsigned int value) {
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\xC6' << *this << (byte)value; break;
	case 16:
		cpu << prefix('\x66') << '\xC7' << *this << (unsigned short)value; break;
	case 32:
	default:
		cpu << prefix() << '\xC7' << *this << value; break;
	}
}

void MemAddress::operator&=(unsigned int value) {
	other = EX_4;
	cpu << prefix() << '\x81' << *this << value;
}

void MemAddress::operator|=(unsigned int value) {
	other = EX_7;
	switch(bitMode) {
	case 8:
		cpu << prefix() << '\x80' << *this << (byte)value; break;
	case 16:
		cpu << prefix('\x66') << '\x81' << *this << (unsigned short)value; break;
	case 32:
	case 64:
		cpu << prefix() << '\x81' << *this << value; break;
	}
}

void MemAddress::operator=(void* value) {
	bitMode = 64;
	if((size_t)value < (size_t)INT_MAX) {
		cpu << prefix() << '\xC7' << *this << (unsigned)(size_t)value;
	}
	else {
		if((size_t)absolute_address > UINT_MAX - sizeof(void*) * 8) {
			bitMode = 32;
			unsigned* values = (unsigned*)&value;

			cpu << prefix() << '\xC7' << *this << values[0];
			moveToUpperDWORD(*this);
			cpu << prefix() << '\xC7' << *this << values[1];
		}
		else {
			other = R11;
			cpu << '\x49' << '\xBB' << (uint64_t)value;
			cpu << prefix() << '\x89' << *this;
		}
	}
}

void MemAddress::operator=(Register fromReg) {
	other = fromReg.code;
	if(fromReg.xmm()) {
		switch(bitMode) {
			case 32:
				cpu << prefix('\xF3') << '\x0F' << '\x11' << *this;
			break;
			case 64:
				cpu << prefix('\xF2', true) << '\x0F' << '\x11' << *this;
			break;
			default:
				throw "Unsupported bitmode for xmm register";
		}
	}
	else {
		switch(bitMode) {
		case 8:
			cpu << prefix() << '\x88' << *this; break;
		case 16:
			cpu << prefix('\x66') << '\x89' << *this; break;
		default:
			cpu << prefix() << '\x89' << *this; break;
		}
	}
}

void MemAddress::direct_copy(MemAddress address, Register& intermediate) {
	if(bitMode != address.bitMode)
		throw 0;
	other = intermediate.code; address.other = other;
	switch(bitMode) {
	case 8:
	case 16:
	case 32:
		address.bitMode = 32;

		intermediate = address;
		*this = intermediate;
		break;
	case 64:
		address.bitMode = 64;

		intermediate = address;
		*this = intermediate;
		break;
	}
}

Register::Register(Processor& CPU, RegCode Code) : cpu(CPU), code(Code), bitMode(0) {}

Register::Register(Processor& CPU, RegCode Code, unsigned BitModeOverride)
	: cpu(CPU), code(Code), bitMode(BitModeOverride) {
}

bool Register::xmm() {
	return code >= 16;
}

bool Register::extended() {
	return (code % 16) >= 8;
}

RegCode Register::index() {
	return (RegCode)(code % 8);
}

RegPrefix Register::prefix(unsigned short other, bool defLong) {
	return RegPrefix(*this, other, defLong);
}

RegPrefix Register::prefix(Register& other, bool defLong) {
	return RegPrefix(*this, other.code, defLong);
}

unsigned char Register::modrm(unsigned short other) {
	return mod_rm(other % 8, REG, code % 8);
}

unsigned char Register::modrm(Register& other) {
	return mod_rm(other.code % 8, REG, code % 8);
}

unsigned Register::getBitMode() const {
	if(bitMode)
		return bitMode;
	else
		return cpu.bitMode;
}

unsigned Register::getBitMode(const MemAddress& addr) const {
	if(bitMode == 0)
		return addr.bitMode;
	else
		return bitMode;
}

MemAddress Register::operator*() const {
	return MemAddress(cpu,code);
}

ScaledIndex Register::operator*(unsigned char scale) const {
	return ScaledIndex(code, scale);
}

void Register::swap(MemAddress address) {
	address.other = code;
	switch(getBitMode(address)) {
	case 8:
		cpu << address.prefix() << '\x86' << address; break;
	case 16:
		cpu << address.prefix('\x66') << '\x87' << address; break;
	case 32:
	case 64:
		cpu << address.prefix() << '\x87' << address; break;
	}
}

void Register::swap(Register& other) {
	if(code == other.code)
		return;
	if(code == EAX)
		cpu << other.prefix() << byte(0x90+(other.code % 8));
	else if(other.code == EAX)
		cpu << prefix() << byte(0x90+(code % 8));
	else
		cpu << other.prefix(code) << '\x87' << other.modrm(code);
}

void Register::copy_address(MemAddress address) {
	address.bitMode = sizeof(void*) * 8;
	address.other = code;
	cpu << address.prefix() << '\x8D' << address;
}

void Register::operator<<=(Register& other) {
	if(other.code != ECX)
		throw "Can only rotate by ECX";
	cpu << prefix() << '\xD3' << modrm(EX_4);
}

void Register::operator>>=(Register& other) {
	if(other.code != ECX)
		throw "Can only rotate by ECX";
	cpu << prefix() << '\xD3' << modrm(EX_7);
}

void Register::rightshift_logical(Register& other) {
	if(other.code != ECX)
		throw "Can only rotate by ECX";
	cpu << prefix() << '\xD3' << modrm(EX_5);
}

void Register::operator+=(unsigned int amount) {
	if(amount == 0) return;

	if(code == EAX) {
		cpu << prefix() << '\x05' << amount;
	}
	else if(amount <= CHAR_MAX) {
		cpu << prefix() <<'\x83' << modrm(EX_0) << (byte)amount;
	}
	else {
		cpu << prefix() << '\x81' << modrm(EX_0) << amount;
	}
}

void Register::operator+=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x03' << address;
}

void Register::operator+=(Register& other) {
	cpu << other.prefix(*this) << '\x03' << other.modrm(code);
}

void Register::operator-=(unsigned int amount) {
	if(amount == 0) return;

	if(code == EAX) {
		cpu << '\x2D' << amount;
	}
	else if(amount <= CHAR_MAX) {
		cpu << prefix() <<'\x83' << modrm(EX_5) << (byte)amount;
	}
	else {
		cpu << prefix() << '\x81' << modrm(EX_5) << amount;
	}
}

void Register::operator-=(Register& other) {
	cpu << other.prefix(*this) << '\x2B' << other.modrm(code);
}

void Register::operator-=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x2B' << address;
}

void Register::operator*=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x0F' << '\xAF' << address;
}

void Register::multiply_signed(MemAddress address, int value) {
	address.other = code;
	if(cpu.bitMode == 32 || cpu.bitMode == 64) {
		if(value >= CHAR_MIN && value <= CHAR_MAX)
			cpu << address.prefix() << '\x6B' << address << (char)value;
		else
			cpu << address.prefix() << '\x69' << address << value;
	}
	else if(cpu.bitMode == 16) {
		if(value >= CHAR_MIN && value <= CHAR_MAX)
			cpu << address.prefix('\x66') << '\x6B' << address << (char)value;
		else
			cpu << address.prefix('\x66') << '\x69' << address << (short)value;
	}
}

void Register::operator-() {
	cpu << prefix(EX_3) << '\xF7' << modrm(EX_3);
}

void Register::operator--() {
	switch(getBitMode()) {
	case 8:
		cpu << prefix(EX_1) << '\xFE' << modrm(EX_1); break;
	case 16:
		cpu << '\x66' << prefix(EX_1) << byte('\x48'+(code % 8)); break;
	default:
		cpu << prefix(EX_1) << '\xFF' << modrm(EX_1); break;
	}
}

void Register::operator++() {
	switch(getBitMode()) {
	case 8:
		cpu << prefix() << '\xFE' << modrm(EX_0); break;
	case 16:
		cpu << '\x66' << prefix() << byte('\x40'+(code % 8)); break;
	default:
		cpu << prefix() << '\xFF' << modrm(EX_0); break;
	}
}

void Register::operator~() {
	if(getBitMode() == 8)
		cpu << prefix(EX_2) << '\xF6' << modrm(EX_2);
	else
		cpu << prefix(EX_2) << '\xF7' << modrm(EX_2);
}

void Register::operator&=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x23' << address;
}

void Register::operator&=(unsigned long long mask) {
	switch(getBitMode()) {
	case 8:
		cpu << prefix() << '\x80' << modrm(EX_4) << (byte)mask; break;
	case 16:
		cpu << prefix('\x66') << '\x81' << modrm(EX_4) << (unsigned short)mask; break;
	case 32:
	case 64:
		if(code == EAX)
			cpu << '\x25' << (unsigned)mask;
		else
			cpu << prefix() << '\x81' << modrm(EX_4) << (unsigned)mask;
	}
}

void Register::operator&=(Register other) {
	switch(getBitMode()) {
	case 8:
		cpu << prefix(other) << '\x20' << modrm(other.code); break;
	case 16:
		cpu << '\x66' << prefix(other) << '\x21' << modrm(other.code); break;
	case 32:
	case 64:
		cpu << prefix(other) << '\x21' << modrm(other.code); break;
	}
}

void Register::operator^=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x33' << address;
}

void Register::operator^=(Register& other) {
	if(xmm() || other.xmm())
		throw 0;
	cpu << prefix(other) << '\x31' << modrm(other);
}

void Register::operator|=(MemAddress address) {
	address.other = code;
	cpu << address.prefix() << '\x0B' << address;
}

void Register::operator|=(unsigned long long mask) {
	switch(getBitMode()) {
	case 8:
		cpu << prefix() << '\x80' << modrm(EX_1) << (byte)mask; break;
	case 16:
		cpu << '\x66' << prefix() << '\x81' << modrm(EX_1) << (unsigned short)mask; break;
	case 32:
	case 64:
		if(code == EAX)
			cpu << '\x0D' << (unsigned)mask;
		else
			cpu << prefix() << '\x81' << modrm(EX_1) << (unsigned)mask;
	}
}

void Register::operator=(void* pointer) {
	if(pointer != (void*)0) {
		bitMode = sizeof(void*) * 8;
		cpu << prefix() << (byte)('\xB8'+(code % 8)) << pointer;
	}
	else {
		//Special case setting to a null pointer with implied sign extend
		bitMode = 32;
		*this = (unsigned long long)0;
	}
}

void Register::operator=(unsigned long long value) {
	switch(getBitMode()) {
	case 8:
		cpu << prefix() << (byte)('\xB0'+(code % 8)) << (byte)value; break;
	case 16:
		cpu << '\x66' << prefix() << (byte)('\xB8'+(code % 8)) << (unsigned short)value; break;
	case 32:
		cpu << prefix() << (byte)('\xB8'+(code % 8)) << (unsigned int)value; break;
	case 64:
		cpu << prefix() << (byte)('\xB8'+(code % 8)) << value; break;
	}
}

void* Register::setDeferred(unsigned long long value) {
	void* ptr = 0;
	switch(getBitMode()) {
	case 8:
		cpu << prefix() << (byte)('\xB0'+(code % 8)); 
		ptr = (void*)cpu.op;
		cpu << (byte)value; break;
	case 16:
		cpu << '\x66' << prefix() << (byte)('\xB8'+(code % 8));
		ptr = (void*)cpu.op;
		cpu << (unsigned short)value; break;
	case 32:
		cpu << prefix() << (byte)('\xB8'+(code % 8));
		ptr = (void*)cpu.op;
		cpu << (unsigned int)value; break;
	case 64:
		cpu << prefix() << (byte)('\xB8'+(code % 8));
		ptr = (void*)cpu.op;
		cpu << value; break;
	}
	return ptr;
}

void Register::operator=(Register other) {
	if(xmm() != other.xmm())
		throw 0;
	if(code == other.code)
		return;

	if(xmm()) {
		if(bitMode == 0 && other.getBitMode() != getBitMode())
			bitMode = other.getBitMode();
		switch(getBitMode()) {
			case 32:
				cpu << '\xF3' << prefix(other) << '\x0F' << '\x10' << modrm(other);
			break;
			case 64:
				cpu << '\xF2' << prefix(other, true) << '\x0F' << '\x10' << modrm(other);
			break;
		}
	}
	else {
		cpu << prefix(other) << '\x89' << modrm(other);
	}
}

void Register::copy_expanding(MemAddress address) {
	address.other = code;
	switch(getBitMode(address)) {
	case 8:
		cpu << address.prefix() << '\x0F' << '\xBE' << address; break;
	case 16:
		cpu << address.prefix() << '\x0F' << '\xBF' << address; break;
	case 32:
		cpu << address.prefix() << '\x63' << address; break;
	case 64:
		*this = address; break;
	}
}

void Register::copy_zeroing(Register& other) {
	switch(getBitMode()) {
	case 8:
	case 16:
		throw 0;
	case 32:
	case 64:
		cpu << other.prefix(*this) << '\x0F' << '\xB6' << other.modrm(code); break;
	}
}

void Register::operator=(MemAddress addr) {
	addr.other = code;
	if(xmm()) {
		if(bitMode == 0 && addr.bitMode != getBitMode())
			bitMode = addr.bitMode;
		switch(addr.bitMode) {
			case 32:
				cpu << addr.prefix('\xF3') << '\x0F' << '\x10' << addr;
			break;
			case 64:
				cpu << addr.prefix('\xF2', true) << '\x0F' << '\x10' << addr;
			break;
		}
	}
	else {
		switch(getBitMode(addr)) {
		case 8:
			cpu << addr.prefix() << '\x8A' << addr; break;
		case 16:
			cpu << addr.prefix('\x66') << '\x8B' << addr; break;
		default:
			cpu << addr.prefix() << '\x8B' << addr; break;
		}
	}
}

void Register::operator==(Register other) {
	switch(getBitMode()) {
	case 8:
		cpu << other.prefix(*this) << '\x3A' << other.modrm(code); break;
	case 16:
		cpu << '\x66' << other.prefix(*this) << '\x3B' << other.modrm(code); break;
	case 32:
	case 64:
		cpu << other.prefix(*this) << '\x3B' << other.modrm(code); break;
	}
}

void Register::operator==(MemAddress addr) {
	addr.other = code;
	switch(getBitMode(addr)) {
	case 8:
		cpu << addr.prefix() << '\x3A' << addr; break;
	case 16:
		cpu << addr.prefix('\x66') << '\x3B' << addr; break;
	case 32:
	case 64:
		cpu << addr.prefix() << '\x3B' << addr; break;
	}
}

void Register::operator==(unsigned int test) {
	switch(getBitMode()) {
	case 8:
		cpu << prefix(EX_7) << '\x80' << modrm(EX_7) << (byte)test; break;
	case 16:
		cpu << '\x66' << prefix(EX_7) << '\x80' << modrm(EX_7) << (unsigned short)test; break;
	case 32:
	case 64:
		cpu << prefix(EX_7) << '\x81' << modrm(EX_7) << test; break;
	}
}

unsigned char setConditions[JumpTypeCount-1] = {0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,0x9C,0x9D,0x9E,0x9F};

void Register::setIf(JumpType condition) {
	if(condition >= Jump)
		throw 0;
	cpu << prefix() << '\x0F' << setConditions[condition] << modrm(EX_0);
}

void Register::divide() {
	cpu << prefix() << '\xF7' << modrm(EX_6);
}

void Register::divide_signed() {
	cpu << prefix() << '\xF7' << modrm(EX_7);
}

FloatingPointUnit::FloatingPointUnit(Processor& CPU) : cpu(CPU) {}

void FloatingPointUnit::pop() {
	//FSTP ST0
	cpu << '\xDD' << '\xD8';
}

void FloatingPointUnit::exchange(FloatReg reg) {
	cpu << '\xD9' << mod_rm(EX_1,REG,reg);
}
	
void FloatingPointUnit::init() {
	cpu << '\xDB' << '\xE3';
}

void FloatingPointUnit::negate() {
	cpu << '\xD9' << '\xE0';
}

void FloatingPointUnit::load_const_0() {
	cpu << '\xD9' << '\xEE';
}

void FloatingPointUnit::load_const_1() {
	cpu << '\xD9' << '\xE8';
}

void FloatingPointUnit::operator-=(FloatReg reg) {
	cpu << '\xDC' << mod_rm(EX_4,REG,reg);
}

void FloatingPointUnit::load_double(MemAddress address) {
	address.other = EX_0;
	cpu << address.prefix() << '\xDD' << address;
}

void FloatingPointUnit::add_double(MemAddress address) {
	address.other = EX_0;
	cpu << address.prefix() << '\xDC' << address;
}

void FloatingPointUnit::mult_double(MemAddress address) {
	address.other = EX_1;
	cpu << address.prefix() <<'\xDC' << address;
}

void FloatingPointUnit::div_double(MemAddress address, bool reversed) {
	address.other = reversed ? EX_7 : EX_6;
	cpu << address.prefix() <<'\xDC' << address;
}

void FloatingPointUnit::sub_double(MemAddress address, bool reversed) {
	address.other = reversed ? EX_5 : EX_4;
	cpu << address.prefix() <<'\xDC' << address;
}
	
void FloatingPointUnit::add_float(MemAddress address) {
	address.other = EX_0;
	cpu << address.prefix() <<'\xD8' << address;
}

void FloatingPointUnit::sub_float(MemAddress address) {
	address.other = EX_4;
	cpu << address.prefix() <<'\xD8' << address;
}

void FloatingPointUnit::mult_float(MemAddress address) {
	address.other = EX_1;
	cpu << address.prefix() <<'\xD8' << address;
}

void FloatingPointUnit::div_float(MemAddress address) {
	address.other = EX_6;
	cpu << address.prefix() <<'\xD8' << address;
}

void FloatingPointUnit::store_double(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << address.prefix() <<'\xDD' << address;
}

void FloatingPointUnit::load_float(MemAddress address) {
	address.other = EX_0;
	cpu << address.prefix() <<'\xD9' << address;
}

void FloatingPointUnit::store_float(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << address.prefix() <<'\xD9' << address;
}

void FloatingPointUnit::load_dword(MemAddress address) {
	address.other = EX_0;
	cpu << address.prefix() <<'\xDB' << address;
}

void FloatingPointUnit::store_dword(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << address.prefix() <<'\xDB' << address;
}

void FloatingPointUnit::load_qword(MemAddress address) {
	address.other = EX_5;
	cpu << address.prefix() <<'\xDF' << address;
}

void FloatingPointUnit::compare_toCPU(FloatReg floatReg, bool pop) {
	if(pop)
		cpu << '\xDF' << mod_rm(EX_5,REG,floatReg);
	else
		cpu << '\xDB' << mod_rm(EX_5,REG,floatReg);
}

void FloatingPointUnit::store_control_word(MemAddress address) {
	address.other = EX_7;
	cpu << address.prefix() <<'\xD9' << address;
}

void FloatingPointUnit::load_control_word(MemAddress address) {
	address.other = EX_5;
	cpu << address.prefix() <<'\xD9' << address;
}

};
