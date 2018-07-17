#ifdef BREAKPAD
#include "client/linux/handler/exception_handler.h"

static bool dumpCallback(const char* dump_path,
		const char* minidump_id,
		void* context,
		bool succeeded) {
	printf(
	"-- NUCLEAR CRASH DETECTED --\n"
	"  Crash dump created at: %s/%s.dmp\n"
	"    Please included this file in your bug report.\n"
	"----------------------------\n",
	dump_path, minidump_id);
	return succeeded;
}

void initCrashDump() {
	google_breakpad::ExceptionHandler eh("/tmp", NULL, dumpCallback, NULL, true);
	*(int*)0 = 2;
}

#else

#include <stdio.h>
#include <execinfo.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "main/logging.h"
#include "scripts/context_cache.h"
void signal_basic(int sig) {
	void* btarray[64];
	size_t btsize;
	btsize = backtrace(btarray, 64);
	fprintf(stderr, "Error: caught signal %d:\n", sig);
	backtrace_symbols_fd(btarray, btsize, 2);
	abort();
}

void print_trace() {
	void* btarray[64];
	size_t btsize;
	btsize = backtrace(btarray, 64);
	error("\nStack trace:");
	char** symbols = backtrace_symbols(btarray, btsize);
	for(unsigned i = 0; i < btsize; ++i)
		error(" %s", symbols[i]);
}

//First try logging the stack trace and the script position
//that crashed (if applicable). Fall back on basic handler
//if this does not work.
void signal_ext(int signum, siginfo_t* info, void* arg) {
	signal(SIGSEGV, signal_basic);

	//Trace
	error("\nCaught Segfault at %p", info->si_addr);
	print_trace();

	//Script stack
	error("");
	scripts::logException();
	abort();
}

void exceptionThrown() {
	static bool first_throw = true;
	const char* exceptionText = nullptr;

	//Find the exception to try
	try {
		if(!first_throw) {
			exceptionText = "empty exception";
		}
		else {
			first_throw = false;
			throw; //Haaax
		}
	}
	catch(const char* text) {
		exceptionText = text;
	}
	catch(std::exception const& exc) {
		exceptionText = exc.what();
	}
	catch(...) {
		exceptionText = "unknown exception";
	}

	//Print exception text
	error("\nUnexpected Exception: %s", exceptionText);

	//Trace
	print_trace();

	//Script stack
	error("");
	scripts::logException();
	abort();
}

void initCrashDump() {
	struct sigaction act;
	memset(&act, 0, sizeof(struct sigaction));
	sigemptyset(&act.sa_mask);
	act.sa_sigaction = &signal_ext;
	act.sa_flags = SA_SIGINFO;
	sigaction(SIGSEGV, &act, nullptr);
	std::set_terminate(exceptionThrown);
}

#endif
