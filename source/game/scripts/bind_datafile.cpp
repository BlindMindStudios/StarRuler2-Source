#include "scripts/binds.h"
#include "main/references.h"
#include "main/logging.h"
#include "util/refcount.h"
#include "str_util.h"
#include "manager.h"
#include <fstream>
#include <sstream>
#include <stdio.h>
#include <time.h>
#include "files.h"

std::set<std::string> validPaths;

namespace scripts {

//Only allow access on files inside the star ruler directory or the profile
bool isAccessible(const std::string& filename) {
	std::string workdir = getWorkingDirectory();
	if(path_inside(workdir, filename))
		return true;

	std::string profiledir = getProfileRoot();
	if(path_inside(profiledir, filename))
		return true;

	for(auto path = validPaths.begin(), end = validPaths.end(); path != end; ++path)
		if(path_inside(*path, filename))
			return true;

	return false;
}

std::string getModProfile() {
	return devices.mods.getProfile();
}

std::string getModProfileChild(const std::string& dirname) {
	return devices.mods.getProfile(dirname);
}

std::string getBaseProfileChild(const std::string& dirname) {
	return devices.mods.getGlobalProfile(dirname);
}

static void createDir(const std::string& dirname) {
	if(!isAccessible(dirname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return;
	}

	makeDirectory(dirname);
}

static long long modTime(const std::string& fname) {
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return 0;
	}

	return (long long)getModifiedTime(fname);
}

static bool isDir(const std::string& dirname) {
	if(!isAccessible(dirname))
		return false;
	return isDirectory(dirname);
}

static bool fileEx(const std::string& fname) {
	if(!isAccessible(fname))
		return false;
	return fileExists(fname);
}

class ReadFile : public DataReader {
	threads::atomic_int references;
public:
	ReadFile(const std::string& filename, bool AllowLines) : DataReader(filename, AllowLines), references(1) {
		if(!isAccessible(filename))
			scripts::throwException("Cannot access file outside game or profile directories.");
	}

	void error(const std::string& str) {
		::error("Error: %s\n  %s", position().c_str(), str.c_str());
	}

	void grab() {
		++references;
	}

	void drop() {
		if(--references == 0)
			delete this;
	}
};

static ReadFile* makeReadFile(const std::string& filename, bool allowLines) {
	return new ReadFile(filename.c_str(), allowLines);
}

static bool readNext(ReadFile& rf) {
	return rf++;
}

class WriteFile : public AtomicRefCounted {
	std::fstream file;
public:
	int curIndent;
	bool allowMultiline;
	std::string endl;

	WriteFile(const char* filename) : file(filename, std::ios_base::out | std::ios_base::binary), curIndent(0), allowMultiline(true), endl("\r\n") {
		std::string fname = filename;
		if(!isAccessible(fname))
			scripts::throwException("Cannot access file outside game or profile directories.");
	}

	bool is_open() const { return file.is_open() && file.good(); }
	bool is_atEnd() const { return file.eof(); }

	void indent(int amount = 1) {
		curIndent += amount;
	}

	void deindent(int amount = 1) {
		curIndent -= amount;
	}

	void writeLine(const std::string& line) {
		file << line << endl;
	}

	void writeKeyValue(const std::string& key, const std::string& val) {
		if(!is_open()) {
			throwException("File is not open");
			return;
		}
		for(int i = 0; i < curIndent; ++i)
			file << "	";
		if(allowMultiline) {
			size_t prev = 0;
			size_t pos = val.find('\n');
			if(pos != std::string::npos) {
				file << key << ": <<" << endl;

				do {
					std::string line = val.substr(prev, pos - prev);
					if(line.empty()) {
						file << endl;
					}
					else {
						for(int i = 0; i < curIndent+1; ++i)
							file << "	";
						file << val.substr(prev, pos - prev) << endl;
					}
					prev = pos+1;

					if(prev < val.size()) {
						pos = val.find('\n', prev);
						if(pos == std::string::npos)
							pos = val.size();
					}
					else {
						break;
					}
				}
				while(true);

				for(int i = 0; i < curIndent; ++i)
					file << "	";
				file << ">>" << endl;
				return;
			}
		}
		else {
			if(val.find('\n') != std::string::npos) {
				file << key << ": " << escape(val) << endl;
				return;
			}
		}
		file << key << ": " << val << endl;
	}

	void writeEmptyLines(unsigned char n) {
		unsigned i = n;
		while(i--)
			file << endl;
	}
};

static WriteFile* makeWriteFile(const std::string& filename) {
	return new WriteFile(filename.c_str());
}

const std::string err("ERR");
class FileList : public AtomicRefCounted {
public:
	std::vector<std::pair<std::string,std::string>> files;

	void navigate(const std::string& dirname, const std::string& filter, bool recurse, bool resolve) {
		files.clear();
		std::map<std::string, std::string> fmap;
		std::string root = getProfileRoot();

		if(!resolve || path_inside(root, dirname)) {
			listDir(dirname, filter, recurse);
		}
		else {
			devices.mods.listFiles(dirname, fmap, filter.c_str(), recurse);

			files.reserve(fmap.size());
			foreach(it, fmap)
				files.push_back(std::pair<std::string,std::string>(it->first, it->second));
		}
	}

	void listDir(const std::string& dirname, const std::string& filter, bool recurse = true) {
		std::vector<std::string> flatfiles;
		listDirectory(dirname, flatfiles, filter.c_str());

		foreach(it, flatfiles) {
			std::string abspath = path_join(dirname, *it);
			files.push_back(std::pair<std::string,std::string>(*it, abspath));
			if(recurse && ::isDirectory(abspath))
				listDir(abspath, filter);
		}
	}

	unsigned size() {
		return (unsigned)files.size();
	}

	const std::string& relative(unsigned i) {
		if(i >= files.size()) {
			throwException("File index out of range.");
			return err;
		}

		return files[i].first;
	}

	std::string basename(unsigned i) {
		if(i >= files.size()) {
			throwException("File index out of range.");
			return err;
		}

		return getBasename(files[i].first);
	}

	std::string extension(unsigned i) {
		if(i >= files.size()) {
			throwException("File index out of range.");
			return err;
		}

		auto pos = files[i].first.rfind('.');
		if(pos == std::string::npos)
			return "";
		return files[i].first.substr(pos+1);
	}

	const std::string& absolute(unsigned i) {
		if(i >= files.size()) {
			throwException("File index out of range.");
			return err;
		}

		return files[i].second;
	}

	bool isDirectory(unsigned i) {
		if(i >= files.size()) {
			throwException("File index out of range.");
			return false;
		}

		return ::isDirectory(files[i].second);
	}
};

FileList* makeFileList(const std::string& dirname, const std::string& filter, bool recurse, bool resolve) {
	FileList* flist = new FileList();
	flist->navigate(dirname, filter, recurse, resolve);
	return flist;
}

FileList* makeFileList_e() {
	return new FileList();
}

static std::string resolveFilename(const std::string& fname) {
	return devices.mods.resolve(fname);
}

//TODO: Restrict to the active mod?
static void deleteFile(const std::string& fname) {
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return;
	}
	if(isDirectory(fname)) {
		std::vector<std::string> inside;
		listDirectory(fname, inside);

		foreach(it, inside)
			deleteFile(path_join(fname, *it));
	}
	remove(fname.c_str());
}

static long long systemTime() {
	time_t t;
	::time(&t);
	return (long long)t;
}

static std::string strftime_wrap(const std::string& format, long long stamp) {
	time_t time = (time_t)stamp;
	struct tm* timeinfo;
	timeinfo = localtime(&time);
	char buffer[120];
	unsigned cnt = strftime(buffer, 120, format.c_str(), timeinfo);
	return std::string(buffer, cnt);
}

void RegisterDatafiles() {
	bind("string get_profileRoot()", asFUNCTION(getProfileRoot))
		doc("", "Path to the game's global profile folder.");
	bind("string get_modProfile()", asFUNCTION(getModProfile))
		doc("", "Path to the current mod's profile folder.");
	bind("string get_modProfile(const string&in folder)", asFUNCTION(getModProfileChild))
		doc("Get the path to a child directory in the mod's profile.",
				"Child directory", "Path to the folder.");
	bind("string get_baseProfile(const string&in folder)", asFUNCTION(getBaseProfileChild))
		doc("Get the path to a child directory in the base profile.",
				"Child directory", "Path to the folder.");
	bind("string resolve(const string&in filename)", asFUNCTION(resolveFilename))
		doc("Resolves the filename to an absolute path to an overriden file. "
			"The top-most mod with a file in the same relative path is used.",
			"Relative filename to resolve.", "");
	bind("void deleteFile(const string&in filename)", asFUNCTION(deleteFile))
		doc("Deletes the specified file. Must be within the profile or game folders.", "");
	bind("void makeDirectory(const string&in dirname)", asFUNCTION(createDir))
		doc("Create a new directory.", "Name of the directory to create.");
	bind("bool isDirectory(const string&in path)", asFUNCTION(isDir))
		doc("Check whether a particular path is a directory.", "Path of the directory to check.",
				"Whether a directory exists at that path.");
	bind("int64 getModifiedTime(const string&in path)", asFUNCTION(modTime))
		doc("Get the timestamp a file was last modified at.", "Path of file.",
				"Last modification time of file.");
	bind("bool fileExists(const string&in path)", asFUNCTION(fileEx))
		doc("Check whether a particular file exists.", "Path of the file to check.",
				"Whether a file exists at that path.");
	bind("string path_join(const string&in first, const string&in second)", asFUNCTION(path_join))
		doc("Concatenate two file paths.", "First path.", "Second path.", "Concatenated path.");
	bind("string path_up(const string&in path)", asFUNCTION(path_up))
		doc("Go up one directory from a path.", "Path to go up from.", "Parent path.");
	bind("bool path_inside(const string&in dirname, const string&in fname)", asFUNCTION(path_inside))
		doc("Check whether a filename is inside a directory.", "Folder name.", "Filename"., "Whether the file is inside the folder.");
	bind("string getBasename(const string&in path, bool includeExtension = true)", asFUNCTION(getBasename))
		doc("Get the basename of a path.", "Path to get basename from.", "Whether to include the extension in the basename.",
			"Path basename.");
	bind("int64 getSystemTime()", asFUNCTION(systemTime));
	bind("string strftime(const string& format, int64 time)", asFUNCTION(strftime_wrap));

	ClassBind read("ReadFile", asOBJ_REF);
	read.addFactory("ReadFile@ f(const string &in filename, bool allowLines = false)", asFUNCTION(makeReadFile))
		doc("Opens a text datafile for reading.", "Path to the file to open. Must be within the profile or game folders.", "", "");
	read.setReferenceFuncs(asMETHOD(ReadFile,grab), asMETHOD(ReadFile,drop));

	read.addMember("int indent", offsetof(ReadFile, indent))
		doc("Number of indents for the current line. Each space or tab counts as one indent.");
	read.addMember("bool allowLines", offsetof(ReadFile, allowLines));
	read.addMember("bool fullLine", offsetof(ReadFile, fullLine));
	read.addMember("bool allowMultiline", offsetof(ReadFile, allowMultiline));
	read.addMember("bool skipComments", offsetof(ReadFile, skipComments));
	read.addMember("bool skipEmpty", offsetof(ReadFile, skipEmpty));
	read.addMember("string line", offsetof(ReadFile, line))
		doc("Full (trimmed) line.");
	read.addMember("string key", offsetof(ReadFile, key))
		doc("Key from a Key:Value pair line.");
	read.addMember("string value", offsetof(ReadFile, value))
		doc("Value from a Key:Value pair line.");

	read.addMethod("void error(const string& message)", asMETHOD(ReadFile, error))
		doc("Display an error message sourced from this file.", "Error message.");
	read.addMethod("string position()", asMETHOD(ReadFile, position))
		doc("Returns a formatted representation of the position in the file.", "A string like 'data/states.txt | Line 80'");
	read.addExternMethod("bool opPostInc()", asFUNCTION(readNext))
		doc("Advances to the next non-empty line.", "Returns true if there was a line to advance to.");


	ClassBind write("WriteFile", asOBJ_REF);
	write.addFactory("WriteFile@ f(const string &in)", asFUNCTION(makeWriteFile));
	write.setReferenceFuncs(asMETHOD(WriteFile,grab), asMETHOD(WriteFile,drop));
	write.addMember("bool allowMultiline", offsetof(WriteFile, allowMultiline))
		doc("Whether multi-line values should be written in multiline format or squashed into a single line.");
	
	write.addMethod("bool get_open() const", asMETHOD(WriteFile,is_open));
	write.addMethod("bool get_atEnd() const", asMETHOD(WriteFile,is_atEnd));
	
	write.addMethod("void indent(int amount = 1)", asMETHOD(WriteFile, indent));
	write.addMethod("void deindent(int amount = 1)", asMETHOD(WriteFile, deindent));
	write.addMethod("void writeLine(const string &in)", asMETHOD(WriteFile, writeLine));
	write.addMethod("void writeKeyValue(const string &in, const string &in)", asMETHOD(WriteFile, writeKeyValue));
	write.addMethod("void writeEmptyLines(uint8 count = 1)", asMETHOD(WriteFile, writeEmptyLines));


	ClassBind flist("FileList", asOBJ_REF);
	flist.addFactory("FileList@ f(const string &in dirname, const string &in filter, bool recurse = false, bool resolve = true)", asFUNCTION(makeFileList));
	flist.addFactory("FileList@ f()", asFUNCTION(makeFileList_e));
	flist.setReferenceFuncs(asMETHOD(FileList,grab), asMETHOD(FileList,drop));

	flist.addMethod("void navigate(const string&in dirname, const string&in filter, bool recurse = false, bool resolve = true)", asMETHOD(FileList, navigate));
	flist.addMethod("uint get_length()", asMETHOD(FileList, size));
	flist.addMethod("const string& get_relativePath(uint num)", asMETHOD(FileList, relative));
	flist.addMethod("string get_basename(uint num)", asMETHOD(FileList, basename));
	flist.addMethod("string get_extension(uint num)", asMETHOD(FileList, extension));
	flist.addMethod("const string& get_path(uint num)", asMETHOD(FileList, absolute));
	flist.addMethod("bool get_isDirectory(uint num)", asMETHOD(FileList, isDirectory));
}

};
