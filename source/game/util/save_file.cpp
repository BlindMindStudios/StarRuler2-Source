#include "save_file.h"
#ifdef _MSC_VER
#include "zlib/zlib.h"
#else
#include "zlib.h"
#endif
#include <stdio.h>
#include "compat/misc.h"
#include "obj/object.h"
#include <unordered_map>
#include "files.h"
#include "main/logging.h"
#include "main/game_platform.h"
#include "main/references.h"
#include "scripts/context_cache.h"

const char* saveIdentifier = "$SR2";
const unsigned gzBufferSize = 128000;

class SaveFileWriter : public SaveFile {
	unsigned boundaryID;
	gzFile out;
	const std::string destName, tempName;

	std::vector<std::unordered_map<std::string,int>> identifiers;

	bool addIdentifier(unsigned type, int id, const std::string& ident) {
		if(type >= identifiers.size()) {
			identifiers.resize(type+1);
		}
		else {
			auto it = identifiers[type].find(ident);
			if(it != identifiers[type].end())
				return false;
		}

		identifiers[type][ident] = id;
		return true;
	}

	void saveIdentifiers() {
		unsigned cnt = identifiers.size();
		*this << cnt;
		for(unsigned i = 0; i < cnt; ++i) {
			auto& mp = identifiers[i];

			unsigned icnt = mp.size();
			*this << icnt;
			foreach(it, mp) {
				*this << it->first;
				*this << it->second;
			}
		}
	}

	void writeIdentifier(unsigned type, int id) {
		*this << id;
	}

	void write(const void* source, unsigned bytes) {
		if(bytes != 0)
			gzwrite(out,source,bytes);
	}

	void close() {
		std::string destTempName = destName + ".temp";

		gzclose(out); out = 0;

		//Move the existing save file to a .temp version
		int oldMoved = rename(destName.c_str(), destTempName.c_str());
		//Move our temp file to the intended destination
		int result = rename(tempName.c_str(), destName.c_str());

		if(result == 0) {
			//Saving succeeded, remove the old save file
			remove(destTempName.c_str());

			if(devices.cloud)
				devices.cloud->writeCloudFile(destName, std::string("saves/") + getBasename(destName));

			delete this;
		}
		else {
			//Saving failed, remove the temp file and replace the old save file
			remove(tempName.c_str());
			if(oldMoved == 0)
				rename(destTempName.c_str(), destName.c_str());
			delete this;
			throw SaveFileError("Could not save file");
		}
	}

	void read(void* dest, unsigned bytes) {
		throw SaveFileError("Cannot read while writing");
	}

	void boundary() {
		*this << boundaryID++;
	}

public:
	SaveFileWriter(const std::string& file) :  boundaryID(100), destName(file), tempName(getTemporaryFile()) {
		out = gzopen(tempName.c_str(),"wb1f");
		scriptVersion = 0;
		startVersion = 0;

		if(out == 0)
			throw SaveFileError("Could not open temporary file");

		gzbuffer(out, gzBufferSize);
		write(saveIdentifier, 4);

		*this << SFV_Current;
	}
};

void readSaveFileInfo(SaveFile& file, SaveFileInfo& info) {
	file >> info.version;
	if(file >= SFV_0005)
		file >> info.startVersion;
	else
		info.startVersion = info.version;

	unsigned cnt = 0;
	file >> cnt;
	info.mods.resize(cnt);
	for(unsigned i = 0; i < cnt; ++i) {
		file >> info.mods[i].id;
		if(file >= SFV_0011)
			file >> info.mods[i].version;
		else
			info.mods[i].version = 0;
	}
}

bool getSaveFileInfo(const std::string& fname, SaveFileInfo& info) {
	try {
		auto* pfile = SaveFile::open(fname, SM_Read);
		if(pfile == nullptr)
			return false;
		pfile->loadIdentifiers();
		readSaveFileInfo(*pfile, info);
		pfile->close();
		return true;
	}
	catch(SaveFileError& err) {
		error("Failed to read save '%s':\n  %s", fname.c_str(), err.text);
		return false;
	}
}

class SaveFileReader : public SaveFile {
	unsigned boundaryID;
	gzFile in;

	std::vector<std::unordered_map<std::string,int>> identifiers;
	std::vector<std::unordered_map<int,int>> identMap;
	std::vector<std::unordered_map<std::string,int>> loaded;

	bool addIdentifier(unsigned type, int id, const std::string& ident) {
		if(type >= identifiers.size()) {
			identifiers.resize(type+1);
		}
		else {
			auto it = identifiers[type].find(ident);
			if(it != identifiers[type].end())
				return false;
		}

		identifiers[type][ident] = id;
		return true;
	}

	void addDummyLoadIdentifier(unsigned type, int id, const std::string& ident) {
		if(type >= loaded.size())
			loaded.resize(type+1);
		loaded[type][ident] = id;
	}

	void loadIdentifiers() {
		unsigned cnt = *this;
		loaded.resize(cnt);
		for(unsigned i = 0; i < cnt; ++i) {
			auto& table = loaded[i];

			unsigned icnt = *this;
			std::string ident;
			int id;

			for(unsigned j = 0; j < icnt; ++j) {
				*this >> ident;
				*this >> id;
				table[ident] = id;
			}
		}
	}

	void finalizeIdentifiers() {
		unsigned cnt = (unsigned)loaded.size();
		identMap.resize(cnt);
		if(cnt > identifiers.size())
			identifiers.resize(cnt);
		for(unsigned i = 0; i < cnt; ++i) {
			auto& mp = identifiers[i];
			auto& table = identMap[i];

			foreach(it, loaded[i]) {
				auto ft = mp.find(it->first);
				if(ft != mp.end())
					table[it->second] = ft->second;
			}
		}
	}

	unsigned getPrevIdentifierCount(unsigned type) {
		if(type >= identMap.size())
			return 0;
		return identMap[type].size();
	}

	unsigned getIdentifierCount(unsigned type) {
		if(type >= identifiers.size())
			return 0;
		return identifiers[type].size();
	}

	int getIdentifier(unsigned type, int id) {
		if(type >= identMap.size())
			return -1;
		auto ft = identMap[type].find(id);
		if(ft == identMap[type].end())
			return -1;
		return ft->second;
	}

	int readIdentifier(unsigned type) {
		int id;
		*this >> id;

		if(type >= identMap.size())
			return -1;

		auto ft = identMap[type].find(id);
		if(ft == identMap[type].end())
			return -1;

		return ft->second;
	}

	void read(void* dest, unsigned bytes) {
		if(bytes != 0) {
			int readBytes = gzread(in, dest, bytes);
			if(readBytes < int(bytes)) {
				scripts::logException();
				throw SaveFileError("Unexpected end of file");
			}
		}
	}

	void write(const void* source, unsigned bytes) {
		throw SaveFileError("Cannot write while reading");
	}

	void close() {
		gzclose(in);
		delete this;
	}

	void boundary() {
		unsigned checkID = *this;
		if(checkID != boundaryID)
			throw SaveFileError("Boundary did not match");
		++boundaryID;
	}
public:
	SaveFileReader(const std::string& file) : boundaryID(100) {
		scriptVersion = 0;
		startVersion = 0;
		in = gzopen(file.c_str(), "rb");
		if(in == 0)
			throw SaveFileError("Could not open save file");

		gzbuffer(in, gzBufferSize);

		char buff[5]; buff[4] = '\0';
		read(buff, 4);

		if(strcmp(buff, saveIdentifier) != 0)
			throw SaveFileError("Not a Star Ruler save");

		*this >> version;
		if(version < SFV_EarliestSupported)
			throw SaveFileError("Save file version no longer supported");
		else if(version >= SFV_Future)
			throw SaveFileError("Save file from a newer version, please update");
	}
};

SaveFile* SaveFile::open(const std::string& file, SaveMode mode) {
	if(mode == SM_Read)
		return new SaveFileReader(file);
	else if(mode == SM_Write)
		return new SaveFileWriter(file);
	else
		throw SaveFileError("Invalid save file mode");
}

SaveFile& SaveFile::operator<<(const char* str) {
	size_t len = strlen(str);
	if(len > 0xffff)
		throw SaveFileError("String too long");
	unsigned short shortLen = (unsigned short)len;
	write(&shortLen,2);
	write(str,shortLen);
	return *this;
}

SaveFile& SaveFile::operator<<(const std::string& str) {
	size_t len = str.size();
	if(len > 0xffff)
		throw SaveFileError("String too long");
	unsigned short shortLen = (unsigned short)len;
	write(&shortLen,2);
	if(shortLen > 0)
		write(str.c_str(),shortLen);
	return *this;
}

SaveFile& SaveFile::operator>>(std::string& str) {
	unsigned short length;
	read(&length,2);
	if(length > 0) {
		void* temp = alloca(length);
		read(temp,length);
		str.assign((const char*)temp, length);
	}
	return *this;
}

SaveFile& SaveFile::operator>>(Object*& obj) {
	obj = getObjectByID(read<int>(), true);
	return *this;
}

Object* SaveFile::readExistingObject() {
	return getObjectByID(read<int>());
}

SaveFile& SaveFile::operator<<(const Object* obj) {
	int id = obj ? obj->id : 0;
	return *this << id;
}

SaveFile::~SaveFile() {}
