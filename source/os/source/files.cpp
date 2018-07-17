#include "files.h"
#include "str_util.h"
#include <iostream>
#include <fstream>

std::string getFileContents(const std::string& filename) {
	std::ifstream str(filename);
	return std::string((std::istreambuf_iterator<char>(str)),
						std::istreambuf_iterator<char>());
}

std::string path_up(const std::string& path) {
	char last = path[path.size() - 1];
	size_t pos;
	if(last == '/' || last == '\\')
		pos = path.substr(0, path.size() - 1).find_last_of("/\\");
	else
		pos = path.find_last_of("/\\");
	if(pos == std::string::npos)
		return "";
	return path.substr(0, pos);

}
