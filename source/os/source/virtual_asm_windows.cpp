#include "virtual_asm.h"
#include <Windows.h>

namespace assembler {

unsigned Processor::maxIntArgs64() {
	return 4;
}

unsigned Processor::maxFloatArgs64() {
	return 4;
}

bool Processor::isIntArg64Register(unsigned char number, unsigned char arg) {
	return arg < 4;
}

bool Processor::isFloatArg64Register(unsigned char number, unsigned char arg) {
	return arg < 4;
}

Register Processor::intArg64(unsigned char number, unsigned char arg) {
	switch(arg) {
		case 0:
			return Register(*this, ECX);
		case 1:
			return Register(*this, EDX);
		case 2:
			return Register(*this, R8);
		case 3:
			return Register(*this, R9);
		default:
			throw "Integer64 argument index out of bounds";
	}
}

Register Processor::floatArg64(unsigned char number, unsigned char arg) {
	switch(arg) {
		case 0:
			return Register(*this, XMM0);
		case 1:
			return Register(*this, XMM1);
		case 2:
			return Register(*this, XMM2);
		case 3:
			return Register(*this, XMM3);
		default:
			throw "Float64 argument index out of bounds";
	}
}

Register Processor::intArg64(unsigned char number, unsigned char arg, Register defaultReg) {
	if(isIntArg64Register(number, arg))
		return intArg64(number, arg);
	return defaultReg;
}

Register Processor::floatArg64(unsigned char number, unsigned char arg, Register defaultReg) {
	if(isFloatArg64Register(number, arg))
		return floatArg64(number, arg);
	return defaultReg;
}

Register Processor::intReturn64() {
	return Register(*this, EAX);
}

Register Processor::floatReturn64() {
	return Register(*this, XMM0);
}

CodePage::CodePage(unsigned int Size, void* requestedStart) : used(0), final(false), references(1) {
	SYSTEM_INFO info;
	GetSystemInfo(&info);

	unsigned minPageSize = info.dwPageSize;
	size_t pageStep = (size_t)info.dwAllocationGranularity * 2;
	if((size_t)Size > pageStep)
		pageStep = (size_t)Size;

	unsigned pages = Size / minPageSize;
	if(Size % minPageSize != 0)
		pages += 1;

	size = (pages * minPageSize) - 2;

	//Search for progressively more distant possible page locations, then just get any available one
	for(int i = 1; i < 256; ++i) {
		void* request = (char*)requestedStart + i*pageStep;
		page = VirtualAlloc(request, size, MEM_COMMIT|MEM_RESERVE, PAGE_EXECUTE_READWRITE);
		if(page != 0)
			return;
	}

	page = VirtualAlloc(0, size, MEM_COMMIT|MEM_RESERVE, PAGE_EXECUTE_READWRITE);
}

void CodePage::grab() {
	++references;
}

void CodePage::drop() {
	if(--references == 0)
		delete this;
}

CodePage::~CodePage() {
	VirtualFree(page,0,MEM_RELEASE);
}

void CodePage::finalize() {
	FlushInstructionCache(GetCurrentProcess(),page,size);
	DWORD oldProtect = PAGE_EXECUTE_READWRITE;
	VirtualProtect(page,size,PAGE_EXECUTE_READ,&oldProtect);
	final = true;
}

unsigned int CodePage::getMinimumPageSize() {
	SYSTEM_INFO info;
	GetSystemInfo(&info);
	return info.dwPageSize;
}


void CriticalSection::enter() {
	EnterCriticalSection((CRITICAL_SECTION*)pLock);
}

void CriticalSection::leave() {
	LeaveCriticalSection((CRITICAL_SECTION*)pLock);
}

CriticalSection::CriticalSection() {
	auto* section = new CRITICAL_SECTION;
	InitializeCriticalSection(section);
	pLock = section;
}
CriticalSection::~CriticalSection() {
	DeleteCriticalSection((CRITICAL_SECTION*)pLock);
	delete (CRITICAL_SECTION*)pLock;
}

};