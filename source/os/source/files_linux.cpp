#ifndef WIN_MODE
#include <unistd.h>
#include <dirent.h>
#include <stdlib.h>
#include <libgen.h>
#include <sys/stat.h>
#include "limits.h"
#include "files.h"
#include "str_util.h"
#include "threads.h"
#include <unordered_map>
#ifndef __APPLE__
#include <sys/inotify.h>
#endif

std::string getWorkingDirectory() {
	char buffer[1024];
	getcwd(buffer, 1024);
	return std::string(buffer);
}

bool setWorkingDirectory(const std::string& dir) {
	return chdir(dir.c_str()) == 0;
}

bool listDirectory(const std::string& dir, std::vector<std::string>& out, const char* filter) {
	DIR* dp;
	struct dirent* de;

	if(!(dp = opendir(dir.c_str())))
		return false;

	CompiledPattern filterReqs;
	compile_pattern(filter, filterReqs);

	while((de = readdir(dp))) {
		if(de->d_name[0] == '.' && de->d_name[1] == '\0')
			continue;
		if(de->d_name[0] == '.' && de->d_name[1] == '.' && de->d_name[2] == '\0')
			continue;
		if(match(de->d_name, filterReqs))
			out.push_back(de->d_name);
	}

	closedir(dp);
	return true;
}

std::string getTemporaryFile() {
	std::string tmp = getProfileRoot();
	tmp = path_join(tmp, ".savetmp.XXXXXX");
	int fd = mkstemp((char*)tmp.c_str());
	close(fd);
	return tmp;
}

std::string getAbsolutePath(const std::string& relpath) {
	char* pth = realpath(relpath.c_str(), 0);
	if(!pth)
		return relpath;
	std::string path(pth);
	free(pth);
	return path;
}

std::string getDirname(const std::string& filename) {
	std::string fl(filename);
	char* dname = dirname(&fl[0]);

	return std::string(dname);
}

std::string getBasename(const std::string& filename, bool includeExtension) {
	std::string fl(filename);
	char* bname = basename(&fl[0]);
	std::string name(bname);

	if(!includeExtension) {
		auto ext = name.find_last_of('.');
		if(ext != name.npos)
			name = name.substr(0,ext);
	}
	return name;
}

bool fileExists(const std::string& filename) {
	struct stat st;
	return stat(filename.c_str(), &st) == 0;
}

bool fileWritable(const std::string& filename) {
	return access(filename.c_str(), W_OK) == 0;
}

bool isDirectory(const std::string& filename) {
	struct stat st;
	if(stat(filename.c_str(), &st) != 0)
		return false;
	return S_ISDIR(st.st_mode);
}

void makeDirectory(const std::string& path) {
	mkdir(path.c_str(), S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
}

std::string getProfileRoot() {
	std::string path = getenv("HOME");
	path = path_join(path, ".starruler2");
	return path;
}

time_t getModifiedTime(const std::string& filename) {
	struct stat st;
	stat(filename.c_str(), &st);
	return st.st_mtime;
}

//Check whether a path is inside another path
bool path_inside(const std::string& folder, const std::string& subpath) {
	std::vector<std::string> subpath_parts;
	std::string suffix;
	std::string prefix;
	if(!subpath.empty() && subpath[0] != '/')
		prefix = ".";
	else
		prefix = "/";

	path_split(subpath, subpath_parts);
	unsigned cnt = subpath_parts.size();
	for(unsigned i = 0; i < cnt; ++i) {
		if(subpath_parts[i].empty())
			continue;
		if(fileExists(path_join(prefix, subpath_parts[i])))
			prefix = path_join(prefix, subpath_parts[i]);
		else
			suffix = path_join(suffix, subpath_parts[i]);
	}

	std::string check = path_join(getAbsolutePath(folder), "");
	std::string inside = path_join(getAbsolutePath(prefix), suffix);
	return inside.compare(0, check.size(), check) == 0;
}

//Split path into elements
void path_split(const std::string& path, std::vector<std::string>& out) {
	split(path, out, '/', false, true);
}

//Join path elements
std::string path_join(const std::string& one, const std::string& two) {
	if(one.empty())
		return two;

	auto endpos = one.find_last_not_of('/');
	if(endpos != std::string::npos)
		endpos += 1;
	auto startpos = two.find_first_not_of('/');
	if(startpos == std::string::npos)
		startpos = 0;

	return one.substr(0, endpos) + '/' + two.substr(startpos, std::string::npos);
}

#ifndef __APPLE__
int inotify_fd = -1;
threads::Mutex inotify_mtx;

struct DirectoryMonitor {
	std::function<void(std::string&)> dircb;
	std::unordered_map<std::string, std::function<bool()>> callbacks;
};
std::unordered_map<std::string, DirectoryMonitor*> directory_names;
std::unordered_map<int, DirectoryMonitor*> watched_directories;

const int inotify_buff_size = 16000;
const size_t inotify_name_off = (size_t)&((inotify_event*)0)->name;

threads::threadreturn threadcall inotify_thread(void* arg) {
	char buffer[inotify_buff_size];

	while(inotify_fd != -1) {
		size_t ind = 0;
		int r = read(inotify_fd, buffer, inotify_buff_size);
		if(r < 0) {
			//Just read again if interrupted
			if(errno != EINTR)
				perror("Error reading from inotify buffer");
			continue;
		}

		threads::Lock lock(inotify_mtx);
		while(ind < (size_t)r) {
			inotify_event* pevt = (inotify_event*)&buffer[ind];
			size_t size = inotify_name_off + pevt->len;

			int wd = pevt->wd;
			auto it = watched_directories.find(wd);
			if(it == watched_directories.end()) {
				inotify_rm_watch(inotify_fd, wd);
			}
			else {
				std::string filename(pevt->name);
				DirectoryMonitor* d = it->second;

				if(d->dircb)
					d->dircb(filename);
				auto f = d->callbacks.find(filename);
				if(f != d->callbacks.end()) {
					if(!f->second())
						d->callbacks.erase(f);
				}
			}

			ind += size;
		}
	}

	return 0;
}

void watchDirectory(const std::string& path, std::function<void(std::string&)> callback) {
	threads::Lock lock(inotify_mtx);
	if(inotify_fd == -1) {
		inotify_fd = inotify_init();
		threads::createThread(inotify_thread, 0);
	}

	std::string dir = getAbsolutePath(path);

	auto it = directory_names.find(dir);
	if(it == directory_names.end()) {
		int wd = inotify_add_watch(inotify_fd, dir.c_str(), IN_CLOSE_WRITE);

		DirectoryMonitor* d = new DirectoryMonitor();
		watched_directories[wd] = d;
		directory_names[dir] = d;

		d->dircb = callback;
	}
	else {
		it->second->dircb = callback;
	}
}

void watchFile(const std::string& path, std::function<bool()> callback) {
	if(!callback)
		return;

	threads::Lock lock(inotify_mtx);
	if(inotify_fd == -1) {
		inotify_fd = inotify_init();
		threads::createThread(inotify_thread, 0);
	}

	std::string dir = getAbsolutePath(getDirname(path));
	std::string file = getBasename(path);

	auto it = directory_names.find(dir);
	if(it == directory_names.end()) {
		int wd = inotify_add_watch(inotify_fd, dir.c_str(), IN_CLOSE_WRITE);

		DirectoryMonitor* d = new DirectoryMonitor();
		watched_directories[wd] = d;
		directory_names[dir] = d;

		d->callbacks[file] = callback;
	}
	else {
		it->second->callbacks[file] = callback;
	}
}

void clearWatches() {
	threads::Lock lock(inotify_mtx);
	if(inotify_fd == -1)
		return;

	for(auto d = watched_directories.begin(); d != watched_directories.end(); ++d) {
		delete d->second;
		inotify_rm_watch(inotify_fd, d->first);
	}
	directory_names.clear();
	watched_directories.clear();

	inotify_fd = -1;
	close(inotify_fd);
}

#else
void watchDirectory(const std::string& path, bool (*callback)(void), bool recursive) {
	//Not supported on Mac yet
}

void watchFile(const std::string& path, std::function<bool()> callback) {
	//Not supported on Mac yet
}

void clearWatches() {
	//Not supported on Mac yet
}
#endif

#endif
