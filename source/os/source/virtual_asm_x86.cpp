#include "virtual_asm.h"
#include <limits.h>
#include <stdarg.h>
#include <stack>

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

void moveToUpperDWORD(MemAddress& address) {
	if(address.absolute_address == 0)
		address.offset += 4;
	else
		address.absolute_address = (byte*)address.absolute_address + 4;
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

struct Argument {
	Register* reg;
	MemAddress* mem;
	unsigned int constant;
	Argument(Register* r) : reg(r), mem(0) {}
	Argument(MemAddress* m) : reg(0), mem(m) {}
	Argument(unsigned int Constant) : reg(0), mem(0), constant(Constant) {}
};

unsigned Processor::pushSize() {
	return sizeof(void*);
}

void Processor::call_thiscall_prep(unsigned argBytes) {
#ifndef _MSC_VER
	//THISCALL on GCC passes the this pointer on the stack, and is mostly identical to cdecl
	call_cdecl_prep(argBytes + 4);
#endif
}

void Processor::call_thiscall_this(MemAddress address) {
#ifdef _MSC_VER
	Register(*this,ECX) = as<void*>(address);
#else
	push(as<void*>(address));
#endif
}

void Processor::call_thiscall_this(Register& reg) {
#ifdef _MSC_VER
	Register(*this,ECX) = reg;
#else
	push(reg);
#endif
}

void Processor::call_thiscall_this_mem(MemAddress address, Register& memreg) {
	call_thiscall_this(address);
	push(memreg);
}

void Processor::call_thiscall_this_mem(Register& reg, Register& memreg) {
	call_thiscall_this(reg);
	push(memreg);
}

void Processor::call_thiscall_end(unsigned argBytes, bool returnPointer) {
#ifndef _MSC_VER
	//THISCALL callers on GCC pops arguments and pointers
	call_cdecl_end(argBytes + 4, returnPointer);
#endif
}

void Processor::call_cdecl_prep(unsigned argBytes) {
#ifndef _MSC_VER
	//Align to 16 byte boundary if not on MSVC
	unsigned stackOffset = (stackDepth + argBytes) % 16;

	Register esp(*this, ESP);
	if(stackOffset != 0)
		esp -= 16 - stackOffset;
#endif
}

void Processor::call_cdecl_end(unsigned argBytes, bool returnPointer) {
	Register esp(*this, ESP);
#ifdef _MSC_VER
	esp += argBytes;
#else
	unsigned stackOffset = (stackDepth + argBytes) % 16;
	if(returnPointer)
		argBytes -= 4;
	if(stackOffset != 0)
		argBytes += (16 - stackOffset);
	if(argBytes != 0)
		esp += argBytes;
#endif
}

unsigned Processor::call_cdecl_args(const char* args, va_list ap) {
	return call_thiscall_args(0, args, ap);
}

unsigned Processor::call_cdecl_args(const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		unsigned r = call_cdecl_args(args, ap);
	va_end(ap);
	return r;
}

unsigned Processor::call_thiscall_args(Register* obj, const char* args, va_list ap) {
	std::stack<Argument> arg_stack;

	unsigned argCount = 0;
#ifdef _MSC_VER
	//TODO
	if(obj)
		throw "Implement this.";
#else
	if(obj) {
		arg_stack.push(obj);
		++argCount;
	}
#endif
	//Read the arguments in...
	while(args, *args != '\0') {
		++argCount;
		if(*args == 'r')
			arg_stack.push(va_arg(ap,Register*));
		else if(*args == 'm')
			arg_stack.push(va_arg(ap,MemAddress*));
		else if(*args == 'c' || *args == 'p')
			arg_stack.push(va_arg(ap,unsigned int));
		else
			throw 0;
		++args;
	}

	call_cdecl_prep(argCount * 4);

	//Then push them in reverse order
	while(!arg_stack.empty()) {
		auto& arg = arg_stack.top();
		if(arg.reg)
			push(*arg.reg);
		else if(arg.mem)
			push(*arg.mem);
		else
			push(arg.constant);
		arg_stack.pop();
	}
	return argCount * 4;
}

void Processor::call_cdecl(void* func, const char* args, va_list ap) {
	unsigned stackBytes = call_cdecl_args(args, ap);
	call(func);
	call_cdecl_end(stackBytes);
}

void Processor::call_cdecl(void* func, const char* args, ...) {
	va_list ap;
	va_start(ap, args);
		call_cdecl(func, args, ap);
	va_end(ap);
}

//STDCALL is similar to CDECL, but we don't need the call preperation or end
void Processor::call_stdcall(void* func, const char* args, ...) {
	std::stack<Argument> arg_stack;

	unsigned argCount = 0;
	if(args && *args != '\0') {
		//Read the arguments in...
		va_list list; va_start(list,args);
		while(*args != '\0') {
			++argCount;
			if(*args == 'r')
				arg_stack.push(va_arg(list,Register*));
			else if(*args == 'm')
				arg_stack.push(va_arg(list,MemAddress*));
			else if(*args == 'c' || *args == 'p')
				arg_stack.push(va_arg(list,unsigned int));
			else
				throw 0;
			++args;
		}
		va_end(list);
	}

#ifndef _MSC_VER
	//Still need to make sure the stack is aligned in GCC
	Register esp(*this, ESP);
	unsigned argBytes = argCount * sizeof(void*);
	unsigned stackOffset = (stackDepth + argBytes) % 16;
	if(stackOffset != 0)
		esp -= 16 - stackOffset;
#endif

	//Then push them in reverse order
	while(!arg_stack.empty()) {
		auto& arg = arg_stack.top();
		if(arg.reg)
			push(*arg.reg);
		else if(arg.mem)
			push(*arg.mem);
		else
			push(arg.constant);
		arg_stack.pop();
	}

	call(func);

#ifndef _MSC_VER
	if(stackOffset != 0)
		esp += 16 - stackOffset;
#endif
}

Processor::Processor(CodePage& codePage, unsigned defaultBitMode ) {
	op = codePage.getActivePage();
	pageStart = op;
	bitMode = defaultBitMode;
	lastBitMode = bitMode;
	stackDepth = 4;
	jumpSpace = 0;
}

void Processor::migrate(CodePage& prevPage, CodePage& newPage) {
	jump(Jump,newPage.getActivePage());
	prevPage.markUsedAddress((void*)op);
	op = newPage.getActivePage();
}

IndexScale factorToScale(unsigned char scale) {
	switch(scale) {
	case 1:
		return Scale1; break;
	case 2:
		return Scale2; break;
	case 4:
		return Scale4; break;
	case 8:
		return Scale8; break;
	default: throw 0;
	}
}

template<>
Processor& Processor::operator<<(MemAddress addr) {
	if(addr.absolute_address != 0) {
		if(addr.scaleFactor == 0)
			return *this << mod_rm(addr.other, ADR, ADDR) << addr.absolute_address;
		else {
			if(addr.scaleReg == ESP)
				throw 0;
			IndexScale scale = factorToScale(addr.scaleFactor);
			return *this << mod_rm(addr.other, ADR, SIB) << sib(addr.scaleReg, scale, EBP) << addr.absolute_address;
		}
	}

	if(addr.scaleFactor != 0) {
		IndexScale scale = factorToScale(addr.scaleFactor);

		//EBP can't accept a scaled index, and ESP doesn't perform scaling
		if(addr.scaleReg == ESP)
			throw 0;

		if(addr.offset == 0 && addr.code != EBP)
			return *this << mod_rm(addr.other, ADR, SIB) << sib(addr.scaleReg, scale, addr.code);
		else if(addr.offset >= CHAR_MIN && addr.offset <= CHAR_MAX)
			return *this << mod_rm(addr.other, ADR8, SIB) << sib(addr.scaleReg, scale, addr.code) << (char)addr.offset;
		else
			return *this << mod_rm(addr.other, ADR32, SIB) << sib(addr.scaleReg, scale, addr.code) << addr.offset;
	}

	if(addr.offset == 0 && addr.code != EBP) { //[EBP] means absolute address, so we use [EBP+0] instead
		*this << mod_rm(addr.other, ADR, addr.code);
		if(addr.code == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
	}
	else if(addr.offset >= CHAR_MIN && addr.offset <= CHAR_MAX) {
		*this << mod_rm(addr.other, ADR8, addr.code);
		if(addr.code == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
		*this << (char)addr.offset;
	}
	else {
		*this << mod_rm(addr.other, ADR32, addr.code);
		if(addr.code == ESP)
			*this << '\x24'; //SIB byte indicating [ESP]
		*this << addr.offset;
	}
	return *this;
}

void Processor::push(Register& reg) {
	*this << byte(0x50u+reg.code);
}

void Processor::pop(Register& reg) {
	*this << byte(0x58u+reg.code);
}

void Processor::push(MemAddress address) {
	address.other = EX_6;
	switch(address.bitMode) {
	case 8:
	case 16:
	case 32:
		*this << '\xFF' << address; break;
	case 64:
		MemAddress upper(address); moveToUpperDWORD(upper);
		*this << '\xFF' << upper;
		*this << '\xFF' << address; break;
	}
}

void Processor::pop(MemAddress address) {
	address.other = EX_0;
	switch(address.bitMode) {
	case 8:
	case 16:
	case 32:
		*this << '\x8F' << address; break;
	case 64:
		*this << '\x8F' << address;
		moveToUpperDWORD(address);
		*this << '\x8F' << address;
		break;
	}
}

void Processor::push(size_t value) {
	if(value <= CHAR_MAX)
		*this << '\x6A' << (byte)value;
	else
		*this << '\x68' << (unsigned int)value;
}

void Processor::pop(unsigned int count) {
	Register esp(*this, ESP);
	esp += count * pushSize();
}

void Processor::call(Register& reg) {
	*this << '\xFF' << mod_rm(EX_2,REG,reg.code);
}

void Processor::call(void* func) {
	int offset = ((byte*)func - op) - 5;
	*this << '\xE8' << offset;
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
	int offset = (op - jumpFrom) - 1;
	if(offset < CHAR_MIN || offset > CHAR_MAX)
		throw 0;
	*jumpFrom = (char)offset;
}

void* Processor::prep_long_jump(JumpType type) {
	if(type != Jump)
		*this << '\x0F';
	*this << longJumpCodes[type];
	void* ret = (void*)op;
	*this << (int)0;
	return ret;
}

void Processor::end_long_jump(void* p) {
	volatile byte* jumpFrom = (volatile byte*)p;
	*(volatile int*)jumpFrom = (op - jumpFrom) - 4;
}

void Processor::jump(JumpType type, volatile byte* dest) {
	int offset = (dest - op) - 2;
	if(offset >= CHAR_MIN && offset <= CHAR_MAX)
		*this << shortJumpCodes[type] << (char)offset;
	else if(type == Jump)
		*this << longJumpCodes[Jump] << offset-3; //Long jump is 3 bytes larger, jump is from the end of the full opcode
	else
		*this << '\x0F' << longJumpCodes[type] << offset-4; //Conditional long jump is 4 bytes larger, jump is from the end of the full opcode
}

void Processor::jump(Register& reg) {
	*this << '\xFF' << mod_rm(EX_4,REG,reg.code);
}

void Processor::loop(volatile byte* dest, JumpType type) {
	int off = dest - op - 2;
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
		*this << '\xA5' << '\xA5'; //Just copy twice for 8 bytes (for 64 bit compatibility)
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
	offset(0), bitMode(cpu.bitMode), Signed(false), scaleFactor(0) {}

MemAddress::MemAddress(Processor& CPU, RegCode Code)
	: cpu(CPU), code(Code), absolute_address(0), other(NONE),
	offset(0), bitMode(cpu.bitMode), Signed(false), scaleFactor(0) {}

MemAddress::MemAddress(Processor& CPU, RegCode Code, int Offset)
	: cpu(CPU), code(Code), absolute_address(0), other(NONE),
	offset(Offset), bitMode(cpu.bitMode), Signed(false), scaleFactor(0) {}


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
		cpu << '\xFE' << *this; break;
	case 16:
		cpu << '\x66' << '\xFF' << *this; break;
	case 32:
		cpu << '\xFF' << *this; break;
	case 64:
		cpu << '\xFF' << *this;
		void* p = cpu.prep_short_jump(NotOverflow);
		moveToUpperDWORD(*this);
		cpu << '\xFF' << *this;
		cpu.end_short_jump(p);
	}
}

void MemAddress::operator--() {
	other = EX_1;
	switch(bitMode) {
	case 8:
		cpu << '\xFE' << *this; break;
	case 16:
		cpu << '\x66' << '\xFF' << *this; break;
	case 32:
		cpu << '\xFF' << *this; break;
	case 64:
		cpu << '\xFF' << *this;
		void* p = cpu.prep_short_jump(NotOverflow);
		moveToUpperDWORD(*this);
		cpu << '\xFF' << *this;
		cpu.end_short_jump(p);
	}
}

void MemAddress::operator-() {
	other = EX_3;
	switch(bitMode) {
	case 8:
		cpu << '\xF6' << *this; break;
	case 16:
		cpu << '\x66' << '\xF7' << *this; break;
	case 32:
		cpu << '\xF7' << *this; break;
	case 64:
		~MemAddress(*this);
		++MemAddress(*this); break;
	}
}

void MemAddress::operator~() {
	other = EX_2;
	switch(bitMode) {
	case 8:
		cpu << '\xF6' << *this; break;
	case 16:
		cpu << '\x66' << '\xF7' << *this; break;
	case 32:
		cpu << '\xF7' << *this; break;
	case 64:
		cpu << '\xF7' << *this;
		moveToUpperDWORD(*this);
		cpu << '\xF7' << *this; break;
	}
}

void MemAddress::operator+=(unsigned int amount) {
	if(amount == 0) return;

	if(code == EAX)
		cpu << '\x05' << amount;
	else if(amount <= CHAR_MAX)
		cpu << '\x83' << *this << (byte)amount;
	else
		cpu << '\x81' << *this << amount;
}

void MemAddress::operator-=(unsigned int amount) {
	if(amount == 0) return;

	other = (RegCode)EX_5;
	if(code == EAX)
		cpu << '\x2D' << amount;
	else if(amount <= CHAR_MAX)
		cpu << '\x83' << *this << (byte)amount;
	else
		cpu << '\x81' << *this << amount;
}

void MemAddress::operator=(unsigned int value) {
	switch(bitMode) {
	case 8:
		cpu << '\xC6' << *this << (byte)value; break;
	case 16:
		cpu << '\x66' << '\xC7' << *this << (unsigned short)value; break;
	case 32:
		cpu << '\xC7' << *this << value; break;
	}
}

void MemAddress::operator&=(unsigned int value) {
	other = EX_4;
	cpu << '\x81' << *this << value;
}

void MemAddress::operator|=(unsigned int value) {
	other = EX_7;
	switch(bitMode) {
	case 8:
		cpu << '\x80' << *this << (byte)value; break;
	case 16:
		cpu << '\x66' << '\x81' << *this << (unsigned short)value; break;
	case 32:
		cpu << '\x81' << *this << value; break;
	}
}

void MemAddress::operator=(void* value) {
	cpu << '\xC7' << *this << value;
}

void MemAddress::operator=(Register fromReg) {
	other = fromReg.code;
	switch(bitMode) {
	case 8:
		cpu << '\x88' << *this; break;
	case 16:
		cpu << '\x66' << '\x89' << *this; break;
	case 32:
		cpu << '\x89' << *this; break;
	case 64:
		throw 0;
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
		intermediate = address;
		*this = intermediate;
		break;
	case 64:
		bitMode = 32; address.bitMode = 32;

		intermediate = address;
		*this = intermediate;
		moveToUpperDWORD(*this); moveToUpperDWORD(address);
		intermediate = address;
		*this = intermediate;
		break;
	}
}

Register::Register(Processor& CPU, RegCode Code) : cpu(CPU), code(Code), bitMode(0) {}

Register::Register(Processor& CPU, RegCode Code, unsigned BitModeOverride)
	: cpu(CPU), code(Code), bitMode(BitModeOverride) {
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
	else if(bitMode <= addr.bitMode)
		return bitMode;
	else
		throw 0;
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
		cpu << '\x86' << address; break;
	case 16:
		cpu << '\x66' << '\x87' << address; break;
	case 32:
		cpu << '\x87' << address; break;
	case 64:
		throw 0;
	}
}

void Register::swap(Register& other) {
	if(code == other.code)
		return;
	if(code == EAX)
		cpu << byte(0x90+other.code);
	else if(other.code == EAX)
		cpu << byte(0x90+code);
	else
		cpu << '\x87' << mod_rm(code,REG,other.code);
}

void Register::copy_address(MemAddress address) {
	address.other = code;
	cpu << '\x8D' << address;
}
	
void Register::operator<<=(Register& other) {
	if(other.code != ECX)
		throw 0;
	cpu << '\xD3' << mod_rm(EX_4,REG,code);
}

void Register::operator>>=(Register& other) {
	if(other.code != ECX)
		throw 0;
	cpu << '\xD3' << mod_rm(EX_7,REG,code);
}

void Register::rightshift_logical(Register& other) {
	if(other.code != ECX)
		throw 0;
	cpu << '\xD3' << mod_rm(EX_5,REG,code);
}

void Register::operator+=(unsigned int amount) {
	if(amount == 0) return;
	if(amount == 1) {
		++*this;
		return;
	}

	if(code == EAX)
		cpu << '\x05' << amount;
	else if(amount <= CHAR_MAX)
		cpu << '\x83' << mod_rm(EX_0,REG,code) << (byte)amount;
	else
		cpu << '\x81' << mod_rm(EX_0,REG,code) << amount;
}

void Register::operator+=(MemAddress address) {
	address.other = code;
	cpu << '\x03' << address;
}

void Register::operator+=(Register& other) {
	cpu << '\x03' << mod_rm(code,REG,other.code);
}

void Register::operator-=(unsigned int amount) {
	if(amount == 0) return;
	if(amount == 1) {
		--*this;
		return;
	}

	if(code == EAX)
		cpu << '\x2D' << amount;
	else if(amount <= CHAR_MAX)
		cpu << '\x83' << mod_rm(EX_5,REG,code) << (byte)amount;
	else
		cpu << '\x81' << mod_rm(EX_5,REG,code) << amount;
}

void Register::operator-=(Register& other) {
	cpu << '\x2B' << mod_rm(code,REG,other.code);
}

void Register::operator-=(MemAddress address) {
	address.other = code;
	cpu << '\x2B' << address;
}

void Register::operator*=(MemAddress address) {
	address.other = code;
	cpu << '\x0F' << '\xAF' << address;
}

void Register::multiply_signed(MemAddress address, int value) {
	address.other = code;
	if(cpu.bitMode == 32) {
		if(value >= CHAR_MIN && value <= CHAR_MAX)
			cpu << '\x6B' << address << (char)value;
		else
			cpu << '\x69' << address << value;
	}
	else if(cpu.bitMode == 16) {
		if(value >= CHAR_MIN && value <= CHAR_MAX)
			cpu << '\x66' << '\x6B' << address << (char)value;
		else
			cpu << '\x66' << '\x69' << address << (short)value;
	}
}

void Register::operator-() {
	cpu << '\xF7' << mod_rm(EX_3,REG,code);
}

void Register::operator--() {
	switch(getBitMode()) {
	case 8:
		cpu << '\xFE' << mod_rm(EX_1,REG,code); break;
	case 16:
		cpu << '\x66' << byte('\x48'+code); break;
	case 32:
		cpu << byte('\x48'+code); break;
	case 64:
		throw 0;
	}
}

void Register::operator++() {
	switch(getBitMode()) {
	case 8:
		cpu << '\xFE' << mod_rm(EX_0,REG,code); break;
	case 16:
		cpu << '\x66' << byte('\x40'+code); break;
	case 32:
		cpu << byte('\x40'+code); break;
	case 64:
		throw 0;
	}
}

void Register::operator~() {
	if(getBitMode() == 8) {
		cpu << '\xF6' << mod_rm(EX_2,REG,code);
	}
	else {
		cpu << '\xF7' << mod_rm(EX_2,REG,code);
	}
}
	
void Register::operator&=(MemAddress address) {
	address.other = code;
	cpu << '\x23' << address;
}

void Register::operator&=(unsigned long long mask) {
	switch(getBitMode()) {
	case 8:
		cpu << '\x80' << mod_rm(EX_4,REG,code) << (byte)mask; break;
	case 16:
		cpu << '\x66' << '\x81' << mod_rm(EX_4,REG,code) << (unsigned short)mask; break;
	case 32:
	case 64:
		if(code == EAX)
			cpu << '\x25' << (unsigned)mask;
		else
			cpu << '\x81' << mod_rm(EX_4,REG,code) << (unsigned)mask;
	}
}

void Register::operator&=(Register other) {
	switch(getBitMode()) {
	case 8:
		cpu << '\x20' << mod_rm(other.code,REG,code); break;
	case 16:
		cpu << '\x66' << '\x21' << mod_rm(other.code,REG,code); break;
	case 32:
	case 64:
		cpu << '\x21' << mod_rm(other.code,REG,code); break;
	}
}

void Register::operator^=(MemAddress address) {
	address.other = code;
	cpu << '\x33' << address;
}

void Register::operator^=(Register& other) {
	cpu << '\x31' << mod_rm(other.code,REG,code);
}

void Register::operator|=(MemAddress address) {
	address.other = code;
	cpu << '\x0B' << address;
}

void Register::operator|=(unsigned long long mask) {
	switch(getBitMode()) {
	case 8:
		cpu << '\x80' << mod_rm(EX_1,REG,code) << (byte)mask; break;
	case 16:
		cpu << '\x66' << '\x81' << mod_rm(EX_1,REG,code) << (unsigned short)mask; break;
	case 32:
	case 64:
		if(code == EAX)
			cpu << '\x0D' << (unsigned)mask;
		else
			cpu << '\x81' << mod_rm(EX_1,REG,code) << (unsigned)mask;
	}
}

void Register::operator=(void* pointer) {
	cpu << (byte)('\xB8'+code) << pointer;
}

void Register::operator=(unsigned long long value) {
	switch(getBitMode()) {
	case 8:
		cpu << (byte)('\xB0'+code) << (byte)value; break;
	case 16:
		cpu << '\x66' << (byte)('\xB8'+code) << (unsigned short)value; break;
	case 32:
		cpu << (byte)('\xB8'+code) << (unsigned int)value; break;
	case 64:
		throw 0;
	}
}

void* Register::setDeferred(unsigned long long value) {
	void* ptr = 0;
	switch(getBitMode()) {
	case 8:
		cpu << (byte)('\xB0'+code);
		ptr = (void*)cpu.op;
		cpu << (byte)value; break;
	case 16:
		cpu << '\x66' << (byte)('\xB8'+code);
		ptr = (void*)cpu.op;
		cpu << (unsigned short)value; break;
	case 32:
		cpu << (byte)('\xB8'+code);
		ptr = (void*)cpu.op;
		cpu << (unsigned int)value; break;
	case 64:
		throw 0;
	}
	return ptr;
}

void Register::operator=(Register other) {
	if(code != other.code)
		cpu << '\x89' << mod_rm(other.code,REG,code);
}

void Register::copy_expanding(MemAddress address) {
	address.other = code;
	switch(getBitMode(address)) {
	case 8:
		cpu << '\x0F' << '\xBE' << address; break;
	case 16:
		cpu << '\x0F' << '\xBF' << address; break;
	case 32:
		*this = address; break;
	case 64:
		throw 0;
	}
}

void Register::copy_zeroing(Register& other) {
	switch(getBitMode()) {
	case 8:
	case 16:
		throw 0;
	case 32:
		cpu << '\x0F' << '\xB6' << mod_rm(code,REG,other.code); break;
	case 64:
		throw 0;
	}
}

void Register::operator=(MemAddress addr) {
	addr.other = code;
	switch(getBitMode(addr)) {
	case 8:
		cpu << '\x8A' << addr; break;
	case 16:
		cpu << '\x66' << '\x8B' << addr; break;
	case 32:
		cpu << '\x8B' << addr; break;
	case 64:
		throw 0;
	}
}

void Register::operator==(Register other) {
	switch(getBitMode()) {
	case 8:
		cpu << '\x3A' << mod_rm(code,REG,other.code); break;
	case 16:
		cpu << '\x66' << '\x3B' << mod_rm(code,REG,other.code); break;
	case 32:
		cpu << '\x3B' << mod_rm(code,REG,other.code); break;
	case 64:
		throw 0;
	}
}

void Register::operator==(MemAddress addr) {
	addr.other = code;
	switch(getBitMode(addr)) {
	case 8:
		cpu << '\x3A' << addr; break;
	case 16:
		cpu << '\x66' << '\x3B' << addr; break;
	case 32:
		cpu << '\x3B' << addr; break;
	case 64:
		throw 0;
	}
}

void Register::operator==(unsigned int test) {
	switch(getBitMode()) {
	case 8:
		cpu << '\x80' << mod_rm(EX_7,REG,code) << (byte)test; break;
	case 16:
		cpu << '\x66' << '\x80' << mod_rm(EX_7,REG,code) << (unsigned short)test; break;
	case 32:
		cpu << '\x81' << mod_rm(EX_7,REG,code) << test; break;
	case 64:
		throw 0;
	}
}

unsigned char setConditions[JumpTypeCount-1] = {0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,0x9C,0x9D,0x9E,0x9F};

void Register::setIf(JumpType condition) {
	if(condition >= Jump)
		throw 0;
	cpu << '\x0F' << setConditions[condition] << mod_rm(EX_0,REG,code);
}

void Register::divide() {
	cpu << '\xF7' << mod_rm(EX_6,REG,code);
}

void Register::divide_signed() {
	cpu << '\xF7' << mod_rm(EX_7,REG,code);
}

FloatingPointUnit::FloatingPointUnit(Processor& CPU) : cpu(CPU) {}

void FloatingPointUnit::pop() {
	//FSTP ST0
	cpu << '\xDD' << '\xD8';
}
	
void FloatingPointUnit::init() {
	cpu << '\xDB' << '\xE3';
}

void FloatingPointUnit::negate() {
	cpu << '\xD9' << '\xE0';
}

void FloatingPointUnit::exchange(FloatReg reg) {
	cpu << '\xD9' << mod_rm(EX_1,REG,reg);
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
	cpu << '\xDD' << address;
}

void FloatingPointUnit::add_double(MemAddress address) {
	address.other = EX_0;
	cpu << '\xDC' << address;
}

void FloatingPointUnit::add_double(FloatReg reg, bool pop) {
	if(pop)
		cpu << '\xDE' << mod_rm(EX_0,REG,reg);
	else
		cpu << '\xDC' << mod_rm(EX_0,REG,reg);
}

void FloatingPointUnit::sub_double(MemAddress address, bool reversed) {
	address.other = reversed ? EX_5 : EX_4;
	cpu << '\xDC' << address;
}

void FloatingPointUnit::sub_double(FloatReg reg, bool reversed, bool pop) {
	if(pop)
		cpu << '\xDE' << mod_rm(reversed ? EX_5 : EX_4, REG, reg);
	else
		cpu << '\xDC' << mod_rm(reversed ? EX_5 : EX_4, REG, reg);
}

void FloatingPointUnit::mult_double(MemAddress address) {
	address.other = EX_1;
	cpu << '\xDC' << address;
}

void FloatingPointUnit::mult_double(FloatReg reg, bool pop) {
	if(pop)
		cpu << '\xDE' << mod_rm(EX_1,REG,reg);
	else
		cpu << '\xDC' << mod_rm(EX_1,REG,reg);
}

void FloatingPointUnit::div_double(MemAddress address, bool reversed) {
	address.other = reversed ? EX_7 : EX_6;
	cpu << '\xDC' << address;
}

void FloatingPointUnit::div_double(FloatReg reg, bool reversed, bool pop) {
	if(pop)
		cpu << '\xDE' << mod_rm(reversed ? EX_7 : EX_6, REG, reg);
	else
		cpu << '\xDC' << mod_rm(reversed ? EX_7 : EX_6, REG, reg);
}
	
void FloatingPointUnit::add_float(MemAddress address) {
	address.other = EX_0;
	cpu << '\xD8' << address;
}

void FloatingPointUnit::sub_float(MemAddress address) {
	address.other = EX_4;
	cpu << '\xD8' << address;
}

void FloatingPointUnit::mult_float(MemAddress address) {
	address.other = EX_1;
	cpu << '\xD8' << address;
}

void FloatingPointUnit::div_float(MemAddress address) {
	address.other = EX_6;
	cpu << '\xD8' << address;
}

void FloatingPointUnit::store_double(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << '\xDD' << address;
}

void FloatingPointUnit::load_float(MemAddress address) {
	address.other = EX_0;
	cpu << '\xD9' << address;
}

void FloatingPointUnit::store_float(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << '\xD9' << address;
}

void FloatingPointUnit::load_dword(MemAddress address) {
	address.other = EX_0;
	cpu << '\xDB' << address;
}

void FloatingPointUnit::store_dword(MemAddress address, bool pop) {
	address.other = pop ? EX_3 : EX_2;
	cpu << '\xDB' << address;
}

void FloatingPointUnit::load_qword(MemAddress address) {
	address.other = EX_5;
	cpu << '\xDF' << address;
}

void FloatingPointUnit::compare_toCPU(FloatReg floatReg, bool pop) {
	if(pop)
		cpu << '\xDF' << mod_rm(EX_5,REG,floatReg);
	else
		cpu << '\xDB' << mod_rm(EX_5,REG,floatReg);
}

void FloatingPointUnit::store_control_word(MemAddress address) {
	address.other = EX_7;
	cpu << '\xD9' << address;
}

void FloatingPointUnit::load_control_word(MemAddress address) {
	address.other = EX_5;
	cpu << '\xD9' << address;
}

};
