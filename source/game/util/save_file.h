#pragma once
#include <vector>
#include <string>
#include "network/message.h"
class Object;

//SaveFile
//
//Create with SaveFile::open("file path", SF_Read or SF_Write)
//Close with SaveFile.close()
//
//In write mode, write data via << syntax, e.g.
//   SaveFile << myVariable;
//   const char* and std::string may both be written this way
//Direct write is available via write(data, bytes)
//   write(&myVariable, sizeof(myVariable))
//
//
//In read mode, read data via >> syntax, e.g.
//   SaveFile >> myVariable;
//   Strings written via << may be read into a std::string this way
//Direct read is available via read(data, bytes)
//   read(&myVariable, sizeof(myVariable)
//
//To support different version formats, use comparison syntax, e.g.
//   if(SaveFile > SFV_0005) {}
//
//Strings may be saved as a std::string or a const char*, but only loaded as std::string
//
//Errors are thrown as SaveFileError()

enum SaveMode {
	SM_Read,
	SM_Write
};

enum SaveIdentifier {
	SI_Subsystem,
	SI_SubsystemVar,
	SI_HexVar,
	SI_ShipVar,
	SI_Hull,
	SI_Shipset,
	SI_Effector,
	SI_Effect,
	SI_SubsystemModule,
	SI_SubsystemModifier,

	SI_SCRIPT_START = 32,
};

struct SaveFileError {
	const char* text;

	SaveFileError(const char* Text) : text(Text) {}
};

struct SavedMod {
	std::string id;
	unsigned short version;
};

struct SaveFileInfo {
	unsigned version;
	unsigned startVersion;
	std::vector<SavedMod> mods;
};

enum SaveFileVersion {
	SFV_0000 = 0,
	SFV_0001 = 0,
	SFV_0002,
	SFV_0003,
	SFV_0004,
	SFV_0005,
	SFV_0006,
	SFV_0007,
	SFV_0008,
	SFV_0009,
	SFV_0010,
	SFV_0011,
	SFV_0012,
	SFV_0013,
	SFV_0014,
	SFV_0015,
	SFV_0016,
	SFV_0017,
	SFV_0018,
	SFV_0019,
	SFV_0020,
	SFV_0021,
	SFV_0022,
	
	SFV_Future,
	SFV_Current = SFV_Future - 1,

	SFV_EarliestSupported = SFV_0000
};

class SaveFile {
protected:
	virtual ~SaveFile();
	SaveFileVersion version;
public:
	unsigned scriptVersion;
	unsigned startVersion;

	//Opens a file in either read or write mode
	//Throws SaveFileError if the file cannot be accessed
	static SaveFile* open(const std::string& file, SaveMode mode);

	//Closes and deletes the SaveFile
	//Throws SaveFileError if something didn't succeed, but still deletes the SaveFile
	virtual void close() = 0;

	//Version checks
	bool operator>(SaveFileVersion Version) const {
		return version > Version;
	}

	bool operator>=(SaveFileVersion Version) const {
		return version >= Version;
	}

	bool operator<(SaveFileVersion Version) const {
		return version < Version;
	}

	bool operator<=(SaveFileVersion Version) const {
		return version <= Version;
	}

	bool operator==(SaveFileVersion Version) const {
		return version == Version;
	}

	bool operator!=(SaveFileVersion Version) const {
		return version != Version;
	}

	//Helper functions

	//Marks a boundary location; During a load, checks that the boundary is present
	virtual void boundary() = 0;

	//Write functions
	virtual void write(const void* source, unsigned bytes) = 0;

	template<class type>
	SaveFile& operator<<(const type& data) {
		write(&data, sizeof(type));
		return *this;
	}

	template<class type>
	SaveFile& operator<<(const type* data) {
		write(data, sizeof(type));
		return *this;
	}

	SaveFile& operator<<(const char* str);

	SaveFile& operator<<(char* str) {
		return *this << (const char*)str;
	}
	
	SaveFile& operator<<(const std::string& str);

	SaveFile& operator<<(std::string& str) {
		return *this << (const std::string&)str;
	}

	SaveFile& operator<<(const Object* obj);

	SaveFile& operator<<(Object* obj) {
		return *this << (const Object*)obj;
	}

	template<class type>
	SaveFile& writeConditional(bool condition, const type& data) {
		*this << condition;
		if(condition)
			*this << data;
		return *this;
	}

	//Read function
	virtual void read(void* dest, unsigned bytes) = 0;

	template<class type>
	type read() {
		type temp;
		read(&temp, sizeof(type));
		return temp;
	}

	template<class type>
	SaveFile& operator>>(type& data) {
		read(&data, sizeof(type));
		return *this;
	}

	template<class type>
	SaveFile& operator>>(const type* data) {
		read(data, sizeof(type));
		return *this;
	}

	SaveFile& operator>>(std::string& str);

	SaveFile& operator>>(Object*& obj);

	Object* readExistingObject();
	
	template<class type>
	bool readConditional(type& data) {
		bool condition;
		*this >> condition;
		if(condition)
			*this >> data;
		else
			data = type();
		return condition;
	}

	template<class type>
	operator type() {
		type temp;
		*this >> temp;
		return temp;
	}

	//Indentifier tables
	virtual bool addIdentifier(unsigned type, int id, const std::string& ident) = 0;
	virtual void addDummyLoadIdentifier(unsigned type, int id, const std::string& ident) {};
	virtual void saveIdentifiers() {};
	virtual void loadIdentifiers() {};
	virtual void finalizeIdentifiers() {};
	virtual int readIdentifier(unsigned type) { return -1; };
	virtual int getIdentifier(unsigned type, int id) { return -1; };
	virtual unsigned getPrevIdentifierCount(unsigned type) { return 0; }
	virtual unsigned getIdentifierCount(unsigned type) { return 0; }
	virtual void writeIdentifier(unsigned type, int id) {};
};

void readSaveFileInfo(SaveFile& file, SaveFileInfo& info);
bool getSaveFileInfo(const std::string& file, SaveFileInfo& info);

class SaveMessage : public net::Message {
public:
	SaveFile& file;

	SaveMessage(SaveFile& sav) : net::Message(), file(sav) {
	}

	SaveMessage(SaveMessage& other) : net::Message(other), file(other.file) {
	}

	void operator=(const SaveMessage& other) {
		net::Message::operator=(other);
	}

	bool operator>(SaveFileVersion Version) const {
		return file > Version;
	}

	bool operator>=(SaveFileVersion Version) const {
		return file >= Version;
	}

	bool operator<(SaveFileVersion Version) const {
		return file < Version;
	}

	bool operator<=(SaveFileVersion Version) const {
		return file <= Version;
	}

	bool operator==(SaveFileVersion Version) const {
		return file == Version;
	}

	bool operator!=(SaveFileVersion Version) const {
		return file != Version;
	}
};
