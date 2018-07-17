#pragma once
#include "angelscript.h"
#include <vector>
#include <map>

namespace assembler {
struct CodePage;
struct CriticalSection;
};

enum JITSettings {
	//Should the JIT attempt to suspend? (Slightly faster, but makes suspension very rare if it occurs at all)
	JIT_NO_SUSPEND = 0x01,
	//Should the JIT reset the FPU entering System calls? (Slightly faster, may not work on all platforms)
	JIT_SYSCALL_FPU_NORESET = 0x02,
	//Should the JIT support error events from System calls? (Faster, but exceptions will generally be ignored, possibly leading to crashes)
	JIT_SYSCALL_NO_ERRORS = 0x04,
	//Do allocation/deallocation functions inspect the script context? (Faster, but won't work correctly if you try to get information about the script system during allocations)
	JIT_ALLOC_SIMPLE = 0x08,
	//Fall back to AngelScript to perform switch logic? (Slower, but uses less memory)
	JIT_NO_SWITCHES = 0x10,
	//Fall back to AngelScript to perform script calls
	// Slower, but can be used as a temporary workaround for angelscript changes
	JIT_NO_SCRIPT_CALLS = 0x20,
	//Make calling reference counting functions faster in common situations
	// Reference counting functions which access the script context will produce undefined results
	JIT_FAST_REFCOUNT = 0x40,
};

class asCJITCompiler : public asIJITCompiler {
	assembler::CodePage* activePage;
	std::multimap<asJITFunction,assembler::CodePage*> pages;

	assembler::CriticalSection* lock;

	unsigned flags;

	std::multimap<asJITFunction,unsigned char**> jumpTables;
	unsigned char** activeJumpTable;
	unsigned currentTableSize;

	struct DeferredCodePointer {
		void** jitFunction;
		void** jitEntry;
	};
	std::multimap<asIScriptFunction*,DeferredCodePointer> deferredPointers;
public:
	asCJITCompiler(unsigned Flags = 0);
	~asCJITCompiler();
	int CompileFunction(asIScriptFunction *function, asJITFunction *output);
    void ReleaseJITFunction(asJITFunction func);
	void finalizePages();
};
