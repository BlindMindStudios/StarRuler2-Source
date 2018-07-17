#include <Windows.h>
#include <string>

typedef BOOL (WINAPI *LPFN_ISWOW64PROCESS) (HANDLE, PBOOL);
LPFN_ISWOW64PROCESS fnIsWow64Process;

int main(int argn, char** argc) {
	fnIsWow64Process = (LPFN_ISWOW64PROCESS) GetProcAddress(
    GetModuleHandle(TEXT("kernel32")),"IsWow64Process");

	BOOL is64bit = false;
    if(fnIsWow64Process != NULL)
		fnIsWow64Process(GetCurrentProcess(),&is64bit);

	for(int i = 1; i < argn; ++i) {
		std::string arg = argc[i];
		if(arg == "-64bit")
			is64bit = true;
		else if(arg == "-32bit")
			is64bit = false;
	}

	//Create command, passing all of our arguments
	std::string command;
	if(is64bit) {
		command = "\"bin\\win64\\Star Ruler 2.exe\" ";
	}
	else {
		command = "\"bin\\win32\\Star Ruler 2.exe\" ";
	}

	for(int i = 1; i < argn; ++i) {
		command += "\"";
		command += argc[i];
		command += "\" ";
	}

	char commandBuffer[32768];

	size_t cmdBuffSize = min(32767,command.size());
	memcpy(commandBuffer, command.c_str(), cmdBuffSize);
	commandBuffer[cmdBuffSize] = '\0';

	STARTUPINFO startup;
		memset(&startup, 0, sizeof(startup));
		startup.cb = sizeof(startup);

	PROCESS_INFORMATION process;
		memset(&process, 0, sizeof(process));

	if(CreateProcess(NULL, commandBuffer, NULL, NULL, FALSE, DETACHED_PROCESS, NULL, NULL, &startup, &process) != FALSE) {
		CloseHandle(process.hProcess);
		CloseHandle(process.hThread);
	}
	return 0;
}