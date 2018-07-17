#ifdef _MSC_VER
#include <Windows.h>
#endif
#include <string>
#include <cstdio>
#include <iostream>
#include <fstream>
#include <vector>
#include "files.h"
#include "threads.h"
#ifdef __GNUC__
#include <unistd.h>
#endif

int move(const char* oldname, const char* newname) {
	if(rename(oldname, newname) == 0)
		return 0;

	auto* source = fopen(oldname, "rb");
	if(source == nullptr)
		return 1;

	auto* dest = fopen(newname, "wb");
	if(dest == nullptr)
		return 1;

	char buffer[1024];
	size_t num;
	while((num = fread(buffer, 1, 1024, source)) > 0) {
		if(fwrite(buffer, 1, num, dest) != num)
			return 1;
	}

	fclose(source);
	fclose(dest);

	remove(oldname);

	return 0;
}

int main(int argc, char** argv) {
	std::cout << "Patching..." << std::endl;
	//Fix old mistakes
	remove("patcher.exe.tmp");

	threads::sleep(100);

	const std::string profile = path_join(getProfileRoot(), "patch/");

	int errors = 0;

	std::vector<std::string> deletions;
	{
		auto delFilename = path_join(profile, ".delete.txt");
		std::ifstream delList(delFilename, std::ios_base::in);
		if(delList.is_open()) {
			std::string line;
			while(delList.good()) {
				std::getline(delList, line);
				if(!line.empty())
					deletions.push_back(line);
			}
		}
		delList.close();
		remove(delFilename.c_str());
	}

	std::function<void(const std::string&)> transferFolder;
	transferFolder = [&](const std::string& relPath) {
		std::vector<std::string> listing;
		if(listDirectory(profile + relPath, listing)) {
			for(auto f = listing.begin(), fend = listing.end(); f != fend; ++f) {
				auto path = path_join(path_join(profile, relPath), *f);
				if(isDirectory(path)) {
					makeDirectory(relPath + *f + "/");
					transferFolder(relPath + *f + "/");
				}
				else {
					auto patchName = path_join(profile, relPath) + "/" + *f;
					auto finalName = relPath + *f;

					if(fileExists(finalName)) {
						auto tempName = finalName + ".tmp";

						bool writable = false;
						for(unsigned i = 0; i < 20; ++i) {
							if(fileWritable(finalName)) {
								writable = true;
								break;
							}

							threads::sleep(100);
						}

						if(move(finalName.c_str(), tempName.c_str()) == 0) {
							if(move(patchName.c_str(), finalName.c_str()) == 0) {
								remove(tempName.c_str());
								std::cout << "Patched " << finalName << std::endl;
							}
							else {
								move(tempName.c_str(), finalName.c_str());
								std::cout << "Failed to patch " << finalName << std::endl;
								++errors;
							}
						}
						else {
							std::cout << "Failed to patch " << finalName << std::endl;
							++errors;
						}
					}
					else {
						if(move(patchName.c_str(), finalName.c_str()) == 0) {
							std::cout << "Patched " << finalName << std::endl;
						}
						else {
							std::cout << "Failed to patch " << finalName << std::endl;
							++errors;
						}
					}
				}
			}
		}

		if(!relPath.empty()) {
			auto folder = path_join(profile, relPath);
			remove(folder.c_str());
		}
	};
	transferFolder("");

	for(auto f = deletions.begin(), fend = deletions.end(); f != fend; ++f) {
		if(remove(f->c_str()) != 0) {
			std::cout << "Failed to delete " << *f << std::endl;
			++errors;
		}
	}

	if(errors > 0) {
		std::cout << "Unabled to update " << errors << " files." << std::endl;
		std::cout << "Exiting..." << std::endl;
		threads::sleep(8000);
	}
	else {
	#ifdef _MSC_VER
		STARTUPINFOA startup;
			memset(&startup, 0, sizeof(startup));
			startup.cb = sizeof(startup);

		PROCESS_INFORMATION process;
			memset(&process, 0, sizeof(process));

		if(CreateProcessA(NULL, "\"Star Ruler 2.exe\"", NULL, NULL, FALSE, DETACHED_PROCESS, NULL, NULL, &startup, &process) != FALSE) {
			CloseHandle(process.hProcess);
			CloseHandle(process.hThread);
		}
	#else
		if(fork() == 0) {
			execlp("./StarRuler2.sh", "./StarRuler2.sh", (char*)nullptr);
			exit(1);
		}
	#endif
	}

	return errors != 0 ? 1 : 0;
}

