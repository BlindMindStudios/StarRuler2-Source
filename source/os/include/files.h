#pragma once
#include <ctime>
#include <vector>
#include <string>
#include <functional>

//Returns the current working directory
std::string getWorkingDirectory();

//Attempts to change the current working directory to <dir>, returns true if successful
bool setWorkingDirectory(const std::string& dir);

//Lists all files and folders in <dir> to <out>
// If a filter is specified, it applies only to files
bool listDirectory(const std::string& dir, std::vector<std::string>& out, const char* filter = "*");

//Get the contents of a file in a string
std::string getFileContents(const std::string& filename);

//Get the absolute real path to a file
std::string getAbsolutePath(const std::string& relpath);

//Check if a file exists
bool fileExists(const std::string& path);

//Check if a file is writable
bool fileWritable(const std::string& path);

//Check if a file exists and is a directory
bool isDirectory(const std::string& path);

//Create a directory
void makeDirectory(const std::string& path);

//Join path elements
std::string path_join(const std::string& one, const std::string& two);

//Go up a directory
std::string path_up(const std::string& path);

//Split path into elements
void path_split(const std::string& path, std::vector<std::string>& out);

//Check whether a path is inside another path
bool path_inside(const std::string& folder, const std::string& subpath);

//Get the dirname and basename of a file
std::string getBasename(const std::string& filename, bool includeExtension = true);
std::string getDirname(const std::string& filename);

//Get the root directory for storing profile data
std::string getProfileRoot();

//Get the name of a temporary file
std::string getTemporaryFile();

void watchDirectory(const std::string& path, std::function<void(std::string&)> callback);
void watchFile(const std::string& path, std::function<bool()> callback);
void clearWatches();

//Get file mtimes
time_t getModifiedTime(const std::string& filename);
