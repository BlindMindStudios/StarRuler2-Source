#pragma once
#include <stddef.h>

#include <stdio.h>

namespace assembler {

typedef unsigned char byte;

struct Register;
struct MemAddress;

enum RegCode : byte {
	EAX = 0,
	ECX = 1,
	EDX = 2,
	EBX = 3,
	ESP = 4, SIB = 4,
	EBP = 5, ADDR = 5,
	ESI = 6,
	EDI = 7,

	R8 = 8,
	R9 = 9,
	R10 = 10,
	R12 = 12,
	R13 = 13,
	R14 = 14,
	R15 = 15,

	//R11 is supervolatile. Can change in between
	//virtual asm ops (used as a temporary), so be careful
	//with using it.
	R11 = 11,

	//XMM registers have unique numbers so we can recognize them
	XMM0 = 16,
	XMM1 = 17,
	XMM2 = 18,
	XMM3 = 19,
	XMM4 = 20,
	XMM5 = 21,
	XMM6 = 22,
	XMM7 = 23,

	XMM8 = 24,
	XMM9 = 25,
	XMM10 = 26,
	XMM11 = 27,
	XMM12 = 28,
	XMM13 = 29,
	XMM14 = 30,
	XMM15 = 31,

	NONE = 0,
};

//Floating Point Register codes representing the stack registers on the FPU
// The top of the stack is always FPU_0
enum FloatReg : byte {
	FPU_0 = 0,
	FPU_1 = 1,
	FPU_2 = 2,
	FPU_3 = 3,
	FPU_4 = 4,
	FPU_5 = 5,
	FPU_6 = 6,
	FPU_7 = 7,
};

enum JumpType {
	Overflow,
	NotOverflow,
	Below, Carry = Below,
	NotBelow, NotCarry = NotBelow,
	Equal, Zero = Equal,
	NotEqual, NotZero = NotEqual,
	NotAbove,
	Above,
	Sign,
	NotSign,
	Parity,
	NotParity,
	Less,
	GreaterOrEqual,
	LessOrEqual,
	Greater,
	Jump,

	JumpTypeCount
};


//Handles thread safety for the JIT
struct CriticalSection {
	void* pLock;

	void enter();
	void leave();

	CriticalSection();
	~CriticalSection();
};

struct AddrPrefix {
	MemAddress& adr;
	bool defLong;
	unsigned char further;

	AddrPrefix(MemAddress& Adr, bool DefLong, unsigned char Further)
		: adr(Adr), defLong(DefLong), further(Further) {
	}
};

struct RegPrefix {
	Register& reg;
	unsigned short other;
	bool defLong;

	RegPrefix(Register& Reg, unsigned short Other, bool DefLong)
		: reg(Reg), other(Other), defLong(DefLong) {
	}
};

//Stores information about the code page
//	Generates an executable page in memory when created
//	Deletes the asssociated page when deleted
//Implementation in virtual_asm_<operating system>.cpp (e.g. virtual_asm_windows.cpp)
struct CodePage {
	void* page;
	unsigned int size, used, references;
	bool final;

	CodePage(unsigned int Size, void* requestedStart = 0);
	~CodePage();

	void grab();
	void drop();

	//Call finalize when done writing to the code page to guarantee that it can be executed
	//No more writing may be done to the allocated pages
	void finalize();

	//Returns the pointer to the first currently unused chunk of the page
	template<class T>
	T getFunctionPointer() {
		return reinterpret_cast<T>((byte*)page+used);
	}

	byte* getActivePage() const {
		return (byte*)page+used;
	}

	//Marks bytes as used;
	//future calls to getFunctionPointer() will not reference the location that is being marked as used
	void markBytesUsed(unsigned int count) {
		used += count;
	}

	//Marks bytes up to <address> as used
	void markUsedAddress(void* address) {
		unsigned newUsed = (unsigned)((byte*)address - (byte*)page);
		if(newUsed > used && newUsed <= size)
			used = newUsed;
	}

	//Returns the number of bytes not yet allocated to a function
	unsigned int getFreeSize() const {
		return size-used;
	}

	//Returns the smallest page (in bytes) that can be allocated by a code page (Sizes other than multiples of this size allocate an extra page)
	static unsigned int getMinimumPageSize();

private:
	CodePage() {}
};

//Stores the code pointer and provides access to various processor-level operations
// To work with the processor, create a set of 'Register' instances, each taking the RegCode of the associated register (e.g. Register eax(cpu, EAX))
//Implementation in virtual_asm_<processor instruction set>.cpp (e.g. virtual_asm_x86.cpp)
struct Processor {
	//Pointer to the location for the next opcode
	byte* op;
	byte* pageStart;
	//The current mode of operation, in bits
	// e.g. 32 bits for x86, indicating that operations should treat addresses as if they were unsigned integers
	unsigned bitMode, lastBitMode;
	//The number of bytes currently on the stack that we are responsible for
	unsigned stackDepth;
	//Reserved jump space
	unsigned jumpSpace;
	byte* jumpPtr;

	//Initializes the processor to point to the active page of the code page
	//Optionally takes a bitMode override (defaults to the same bitMode as the exe)
	Processor(CodePage& codePage, unsigned defaultBitMode = sizeof(void*)*8 );

	//Creates a jump to the new code page, and marks the current address as used on the old code page
	//Updates output pointer to the new code page's active page
	void migrate(CodePage& prevPage, CodePage& newPage);

	//Changes the current bitMode, and stores the previous bitMode
	void setBitMode(unsigned bits) {
		lastBitMode = bitMode;
		bitMode = bits;
	}

	//Restores the previous bitMode
	void resetBitMode() {
		bitMode = lastBitMode;
	}

	//Returns the alignment of the stack (number of bytes a push increments esp)
	static unsigned pushSize();

	//Pushes data to the opcode output
	template<class T>
	Processor& operator<<(T b) {
		*(T*)op = b; op += sizeof(T);
		return *this;
	}

	//Pushes bytes representing a memory address to the opcode output
	template<class T>
	Processor& operator<<(MemAddress addr);

	//Pushes bytes representing a prefix
	template<class T>
	Processor& operator<<(AddrPrefix pr);

	template<class T>
	Processor& operator<<(RegPrefix pr);

	//Calls the function, passing the arguments specified by 'args'
	//args is a string like "rrcmrm" which specifies arguments as sourced by a Register*, MemAddres*, or a constant
	//EBP is invalid during the call
	void call_cdecl(void* func, const char* args, va_list ap);
	void call_cdecl(void* func, const char* args, ...);

	//Use call() in between these to set up a call with an arbitrary function
	unsigned call_cdecl_args(const char* args, ...);
	unsigned call_cdecl_args(const char* args, va_list ap);
	unsigned call_thiscall_args(Register* obj, const char* args, ...);
	unsigned call_thiscall_args(Register* obj, const char* args, va_list ap);

	//Prepares for a call to manual call to a cdecl function (Do not use with call_cdecl)
	// Use before pushing arguments
	// Invalidates EBP until call_cdecl_end()
	void call_cdecl_prep(unsigned argBytes);
	//Ends a manual call to a cdecl function (Do not use with call_cdecl)
	// Use after returning from the function
	void call_cdecl_end(unsigned argBytes, bool returnPointer = false);

	//Note: stdcall is like cdecl, but does not use cdecl_end

	//Calls the function, passing the arguments specified by 'args'
	//args is a string like "rrcmrm" which specifies arguments as sourced by a Register*, MemAddres*, or a constant
	//EBP is invalid during the call
	void call_stdcall(void* func, const char* args, ...);
	
	//To call a thiscall:
	// cpu.call_thiscall_prep(total argument size)
	// cpu.push(arguments)
	// cpu.call_thiscall_this(source of 'this' pointer)
	// cpu.call(function)
	// cpu.call_thiscall_end(total argument size)
	void call_thiscall_prep(unsigned argBytes);
	void call_thiscall_this(MemAddress address);
	void call_thiscall_this(Register& reg);
	void call_thiscall_this_mem(MemAddress address, Register& memreg);
	void call_thiscall_this_mem(Register& reg, Register& memreg);
	void call_thiscall_end(unsigned argBytes, bool returnPointer = false);

	//Calls a function (push code pointer, jump to function)
	void call(Register& reg);
	void call(void* func);

	//Pushes a constant value onto the stack (Pushes are always pushSize() large, values beyond this size are an error)
	void push(size_t value);
	//Pops <count> times (Pops are always pushSize() large)
	void pop(unsigned int count);

	//Pushes the value of <reg> onto the stack
	void push(Register& reg);
	//Pops the alue of <reg> from the stack
	void pop(Register& reg);

	//Get a register corresponding to an argument on 64-bit calling convention
	unsigned maxIntArgs64();
	unsigned maxFloatArgs64();
	bool isIntArg64Register(unsigned char number, unsigned char arg);
	bool isFloatArg64Register(unsigned char number, unsigned char arg);
	Register intArg64(unsigned char number, unsigned char arg);
	Register floatArg64(unsigned char number, unsigned char arg);
	Register intArg64(unsigned char number, unsigned char arg, Register defaultReg);
	Register floatArg64(unsigned char number, unsigned char arg, Register defaultReg);
	Register floatReturn64();
	Register intReturn64();

	//Pushes the memory at <address> onto the stack (Pushes are always pushSize() large, pushing larger values invokes multiple pushes)
	void push(MemAddress address);
	//Pops the value on the stack to the memory at <address> (Pops are always pushSize() large, popping larger values invokes multiple pops)
	void pop(MemAddress address);
	
	//Prepares a short jump (fewer than approx. 120 bytes in either direction)
	// Pass the return to a matching end_short_jump
	void* prep_short_jump(JumpType type);
	//Ends a short jump
	void end_short_jump(void* p);

	//Prepares a large jump (can jump to any location)
	// Pass the return to a matching end_long_jump
	void* prep_long_jump(JumpType type);
	//Ends a large jump
	void end_long_jump(void* p);

	//Jumps to <dest>
	void jump(JumpType type, volatile byte* dest);
	//Jumps to the address in <reg>
	void jump(Register& reg);
	//Decrements ecx and jumps if it becomes 0; Optionally conditionally jumps based on a Zero/NotZero test
	void loop(volatile byte* dest, JumpType type = Jump);

	//Copies from *esi to *edi, and adjusts them both by the data size according to the direction flag
	void string_copy(unsigned size);
	//Sets direction flag for string copy
	void setDirFlag(bool forward);

	//Returns from a function (pop code pointer, jump there)
	void ret();

	//Triggers a debug break
	void debug_interrupt();

private:
	Processor() {}
};

//Provides access to the floating point unit's state
//Implementation in virtual_asm_<processor instruction set>.cpp (e.g. virtual_asm_x86.cpp)
struct FloatingPointUnit {
	Processor& cpu;

	FloatingPointUnit(Processor& CPU);

	//Clears the FPU's state and registers
	void init();

	//Negates FPU_0
	void negate();

	//Pushes 
	void load_const_0();
	void load_const_1();

	//FPU_1 becomes FPU_0 (Pops the fpu stack)
	void pop();

	//Exchanges contents of FPU_n and FPU_0
	void exchange(FloatReg floatReg);

	//Compares FPU_0 to floatReg, setting the CPU's flags according to the values' relation
	// Optionally pops the fpu stack
	void compare_toCPU(FloatReg floatReg, bool pop = true);

	//Pushes the specified data type stored at <address> onto the FPU stack (becomes FPU_0)
	void load_float(MemAddress address);
	void load_dword(MemAddress address);
	void load_qword(MemAddress address);
	void load_double(MemAddress address);

	//Stores the value on FPU_0 to <address> according to the data type
	// Optionally pops the fpu stack
	void store_float(MemAddress address, bool pop = true);
	void store_dword(MemAddress address, bool pop = true);
	void store_double(MemAddress address, bool pop = true);

	//Control words
	void store_control_word(MemAddress address);
	void load_control_word(MemAddress address);

	//Effect: FPU_0 -= <reg>
	void operator-=(FloatReg reg);

	//Effect: FPU_0 += *(float*)address
	void add_float(MemAddress address);
	//Effect: FPU_0 -= *(float*)address
	void sub_float(MemAddress address);
	//Effect: FPU_0 *= *(float*)address
	void mult_float(MemAddress address);
	//Effect: FPU_0 /= *(float*)address
	void div_float(MemAddress address);
	
	//Effect: FPU_0 += *(double*)address
	void add_double(MemAddress address);
	void add_double(FloatReg reg, bool pop = true);
	//Effect: FPU_0 -= *(double*)address
	// If Reversed: FPU_0 = *(double*)address - FPU_0
	void sub_double(MemAddress address, bool reversed = false);
	void sub_double(FloatReg reg, bool reversed = false, bool pop = true);
	//Effect: FPU_0 *= *(double*)address
	void mult_double(MemAddress address);
	void mult_double(FloatReg reg, bool pop = true);
	//Effect: FPU_0 /= *(double*)address
	// If Reversed: FPU_0 = *(double*)address / FPU_0
	void div_double(MemAddress address, bool reversed = false);
	void div_double(FloatReg reg, bool reversed = false, bool pop = true);
};

//Temporary struct that represents an addition to a memory address, with optional scaling
struct ScaledIndex {
	RegCode reg;
	unsigned char scaleFactor;

	ScaledIndex(RegCode Reg, unsigned char Scale) : reg(Reg), scaleFactor(Scale) {}
};

//Temporary struct that stores data necessary for memory access
//  Provides operations that can be performed on a memory address
//Implementation in virtual_asm_<processor instruction set>.cpp (e.g. virtual_asm_x86.cpp)
struct MemAddress {
	Processor& cpu;
	void* absolute_address;
	int offset;
	unsigned bitMode;
	RegCode code;
	RegCode scaleReg;
	unsigned char other;
	unsigned char scaleFactor;
	bool Float;
	bool Signed;

	MemAddress(Processor& CPU, void* address);
	MemAddress(Processor& CPU, RegCode Code);
	MemAddress(Processor& CPU, RegCode Code, int Offset);
	MemAddress operator+(ScaledIndex scale);
	MemAddress operator+(int Offset);
	MemAddress operator-(int Offset);

	void operator++();
	void operator--();

	void operator-();
	void operator~();

	void operator+=(unsigned int amount);
	void operator-=(unsigned int amount);
	
	void operator=(unsigned int value);
	void operator=(void* pointer);
	void operator=(Register fromReg);

	void operator&=(unsigned int value);
	void operator|=(unsigned int value);

	//Copies memory using an intermediate register
	void direct_copy(MemAddress address, Register& intermediate);
	AddrPrefix prefix(unsigned char further = 0, bool defLong = false);
};

//Converts a MemAddress from the default unsigned <cpu bit mode> to match the passed type
template<class T>
MemAddress as(MemAddress addr) {
	addr.bitMode = sizeof(T) * 8;
	addr.Signed = (T)-1 < (T)0;
	return addr;
}

template<>
MemAddress as<float>(MemAddress addr);

template<>
MemAddress as<double>(MemAddress addr);

//Structure that provides operations that can be performed on a register
//  Also provides the means to generate MemAddresses relative to a register via dereference (e.g. *eax+8)
//Implementation in virtual_asm_<processor instruction set>.cpp (e.g. virtual_asm_x86.cpp)
struct Register {
	Processor& cpu;
	RegCode code;
	unsigned bitMode;
	
	Register(Processor& CPU, RegCode Code);
	Register(Processor& CPU, RegCode Code, unsigned BitModeOverride);

	void set_regCode(Register& other) {
		code = other.code;
		bitMode = other.bitMode;
	}

	unsigned getBitMode() const;
	unsigned getBitMode(const MemAddress& addr) const;

	MemAddress operator*() const;
	ScaledIndex operator*(unsigned char scale) const;

	//Loads the address pointed to by <address> into this register
	void copy_address(MemAddress address);

	void swap(MemAddress address);
	void swap(Register& other);

	void operator<<=(Register& other);
	void operator>>=(Register& other);
	void rightshift_logical(Register& other);
	
	void operator+=(unsigned int amount);
	void operator+=(MemAddress address);
	void operator+=(Register& other);
	
	void operator-=(unsigned int amount);
	void operator-=(Register& other);
	void operator-=(MemAddress address);
	
	void operator*=(MemAddress address);

	void operator-();
	void operator~();

	void operator--();
	void operator++();
	
	void operator&=(unsigned long long mask);
	void operator&=(MemAddress address);
	void operator&=(Register other);
	
	void operator^=(MemAddress address);
	void operator^=(Register& other);

	void operator|=(MemAddress address);
	void operator|=(unsigned long long mask);

	//Copies a smaller data type, retaining the sign
	void copy_expanding(MemAddress address);
	//Copies an 8 bit register, leaving 0s in higher bytes
	void copy_zeroing(Register& other);

	void operator=(unsigned long long value);
	void operator=(void* pointer);
	void operator=(Register other);
	void operator=(MemAddress addr);
	
	void operator==(Register other);
	void operator==(MemAddress addr);
	void operator==(unsigned int test);

	void setIf(JumpType condition);
	void* setDeferred(unsigned long long def = 0);

	bool xmm();
	bool extended();
	RegCode index();

	RegPrefix prefix(unsigned short other = 0, bool defaultLong = false);
	RegPrefix prefix(Register& other, bool defaultLong = false);
	unsigned char modrm(unsigned short other);
	unsigned char modrm(Register& other);

	//Multiplies *address with value, stores the result in this register
	void multiply_signed(MemAddress address, int value);

	//Divides {eax,edx} by this register; result in eax, remainder in edx
	void divide();
	void divide_signed();
};

//Converts a MemAddress from the default unsigned <cpu bit mode> to match the passed type
template<class T>
Register as(Register reg) {
	reg.bitMode = sizeof(T) * 8;
	return reg;
}
};
