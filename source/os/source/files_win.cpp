#ifdef _MSC_VER
#include <Windows.h>
#include <ShlObj.h>
#include <Shlwapi.h>

#include "files.h"
#include <direct.h>
#include <io.h>
#include <stdlib.h>

#include "str_util.h"

#include "threads.h"

bool fileExists(const std::string& path) {
	return _access(path.c_str(),0) == 0;
}

bool fileWritable(const std::string& path) {
	return _access(path.c_str(),2) == 0;
}

#include <sys/stat.h>
bool isDirectory(const std::string& path) {
	struct stat info;
	if(stat(path.c_str(),&info) == 0)
		return (info.st_mode & _S_IFDIR) != 0;
	else
		return false;
}

//Join path elements
std::string path_join(const std::string& one, const std::string& two) {
	if(one.empty())
		return two;

	auto endOfPath = one.find_last_not_of("\\/");
	if(endOfPath != std::string::npos)
		endOfPath += 1;
	auto startOfPath = two.find_first_not_of("\\/");
	if(startOfPath == std::string::npos)
		startOfPath = 0;

	return one.substr(0,endOfPath) + "/" + two.substr(startOfPath, std::string::npos);
}

//Split path into elements
void path_split(const std::string& path, std::vector<std::string>& out) {
	size_t prev = path.find_first_not_of("\\/");

	while(prev != std::string::npos) {
		size_t next = path.find_first_of("\\/", prev);
		out.push_back(path.substr(prev, next - prev));
		prev = path.find_first_not_of("\\/", next);
	}
}

//Check whether a path is inside another path
bool path_inside(const std::string& folder, const std::string& subpath) {
	//NOTE: getAbsolutePath normalizes to / to \ on Windows
	std::string prefix = getAbsolutePath(folder), toPath = getAbsolutePath(subpath);
	if(toPath.size() < prefix.size())
		return false;
	for(unsigned i = 0; i < prefix.size(); ++i)
		if(prefix[i] != toPath[i])
			return false;
	return true;
}

//Create a directory
void makeDirectory(const std::string& path) {
	CreateDirectory(path.c_str(),NULL);
}

std::string getProfileRoot() {
	TCHAR path[MAX_PATH], *profile_folder = "\\My Games\\Star Ruler 2\\";
	SHGetFolderPath( NULL, CSIDL_MYDOCUMENTS, NULL, 0, path);
	PathAppend(path, profile_folder);
	return path;
}

std::string getWorkingDirectory() {
	char buffer[MAX_PATH];
	_getcwd(buffer, MAX_PATH);
	return std::string(buffer);
}

bool setWorkingDirectory(const std::string& dir) {
	return _chdir(dir.c_str()) == 0;
}

bool listDirectory(const std::string& dir, std::vector<std::string>& out, const char* filter) {
	auto full_dir = dir + "\\*";

	CompiledPattern filterReqs;
	compile_pattern(filter, filterReqs);

	WIN32_FIND_DATA result;
	auto file = FindFirstFile(full_dir.c_str(), &result);
	if(file == INVALID_HANDLE_VALUE)
		return false;

	do {
		if(result.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
			if(strcmp(result.cFileName,".") == 0 || strcmp(result.cFileName,"..") == 0)
				continue;
		if(match(result.cFileName, filterReqs))
			out.push_back(result.cFileName);
	} while(FindNextFile(file, &result) != FALSE);

	FindClose(file);
	return true;
}

void clearTemps() {
	std::string tempPath = getProfileRoot() + "/temp/";
	std::vector<std::string> files;

	if(listDirectory(tempPath, files))
		for(auto i = files.begin(), end = files.end(); i != end; ++i)
			remove(i->c_str());

	RemoveDirectory(tempPath.c_str());

	auto backup = getProfileRoot() + "temp.TMP";
	remove(backup.c_str());
}

std::string getTemporaryFile() {
	static bool first = true;
	if(first) {
		atexit(clearTemps);
		first = false;
	}

	std::string tempPath = getProfileRoot() + "/temp/";
	CreateDirectory(tempPath.c_str(), NULL);

	char buffer[MAX_PATH];
	auto result = GetTempFileName(tempPath.c_str(), "sr2", 0, buffer);
	if(result != 0)
		return buffer;
	else
		return getProfileRoot() + "temp.TMP";
}

std::string getAbsolutePath(const std::string& relpath) {
	char buffer[MAX_PATH];
	auto len = GetFullPathName(relpath.c_str(), MAX_PATH, buffer, 0);
	return std::string(buffer, len);
}

std::string getBasename(const std::string& filename, bool includeExtension) {
	auto dir_end = filename.find_last_of("\\/");
	std::string name = (dir_end == filename.npos) ? filename : filename.substr(dir_end+1);
	if(includeExtension == false) {
		auto ext = name.find_last_of('.');
		if(ext != name.npos)
			name = name.substr(0,ext);
	}
	return name;
}

std::string getDirname(const std::string& filename) {
	auto dir_end = filename.find_last_of("\\/");
	if(dir_end == filename.npos)
		return "";
	else
		return filename.substr(0,dir_end);
}

threads::Mutex watch_mtx;
struct DirectoryMonitor {
	std::string path;
	std::function<void(std::string&)> dircb;
	std::unordered_map<std::string, std::function<bool()>> callbacks;
};
std::unordered_map<std::string, DirectoryMonitor*> directory_names;
const int watch_buff_size = 16000;

threads::threadreturn threadcall WatchDir(void* arg) {
	DirectoryMonitor* d = (DirectoryMonitor*)arg;

	HANDLE dir = CreateFile(
		d->path.c_str(),
		FILE_LIST_DIRECTORY,
		FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
		0, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);

	DWORD r = 0;
	char buffer[watch_buff_size];

	while(true) {
		ReadDirectoryChangesW(
			dir, &buffer, sizeof(buffer),
			false, FILE_NOTIFY_CHANGE_LAST_WRITE,
			&r, NULL, NULL);

		threads::Lock lock(watch_mtx);
		size_t ind = 0;
		while(ind < r) {
			FILE_NOTIFY_INFORMATION* pevt = (FILE_NOTIFY_INFORMATION*)&buffer[ind];
			std::wstring filename_w((wchar_t*)pevt->FileName, pevt->FileNameLength / 2);

			std::string filename; filename.reserve(filename_w.size());

			//Strip UTF16 to ASCII
			for(auto c = filename_w.cbegin(), end = filename_w.cend(); c != end; ++c)
				filename.push_back((char)*c & 0x7f);

			if(d->dircb)
				d->dircb(filename);
			auto f = d->callbacks.find(filename);
			if(f != d->callbacks.end()) {
				if(!f->second())
					d->callbacks.erase(f);
			}
			
			if(pevt->NextEntryOffset == 0)
				break;
			ind += pevt->NextEntryOffset;
		}
	}
}

void watchDirectory(const std::string& path, std::function<void(std::string&)> callback) {
	threads::Lock lock(watch_mtx);
	std::string dir = getAbsolutePath(path);

	auto it = directory_names.find(dir);
	if(it == directory_names.end()) {
		DirectoryMonitor* d = new DirectoryMonitor();
		d->path = dir;
		d->dircb = callback;

		directory_names[dir] = d;

		threads::createThread(WatchDir, d);
	}
	else {
		it->second->dircb = callback;
	}
}

void watchFile(const std::string& path, std::function<bool()> callback) {
	if(!callback)
		return;

	threads::Lock lock(watch_mtx);
	std::string dir = getAbsolutePath(getDirname(path));
	std::string file = getBasename(path);

	auto it = directory_names.find(dir);
	if(it == directory_names.end()) {
		DirectoryMonitor* d = new DirectoryMonitor();
		d->path = dir;
		d->callbacks[file] = callback;

		directory_names[dir] = d;

		threads::createThread(WatchDir, d);
	}
	else {
		it->second->callbacks[file] = callback;
	}
}

void clearWatches() {
	threads::Lock lock(watch_mtx);
	for(auto d = directory_names.begin(); d != directory_names.end(); ++d)
		delete d->second;
	directory_names.clear();
	//TODO: Stop threads
}


time_t getModifiedTime(const std::string& filename) {
	struct stat st;
	stat(filename.c_str(), &st);
	return st.st_mtime;
}

#endif
