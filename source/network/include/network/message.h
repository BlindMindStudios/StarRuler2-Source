#pragma once
#include <string>
#include <cstring>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <network/message_types.h>
#include <vector>
#include <list>
#include <map>
#include <unordered_map>

namespace net {


//Message
//======
//Handles memory between the Network and Application
//
//Use 'message >> variable' to read from the Message
//Use 'message << variable' to write to the Message
//
//To send a message,
//Message msg(MessageType);
//msg << data;

class MessageReadError {
};

typedef unsigned msize_t;

struct Message {
	//Prepares a message for sending
	Message();
	Message(uint8_t type, uint8_t flags = 0);
	Message(uint8_t* data, msize_t bytes);
	Message(Message& other);

	void setType(uint8_t type);
	uint8_t getType() const;

	uint8_t getFlags() const;
	void setFlags(uint8_t flags);

	bool hasFlags() const;
	bool getFlag(uint8_t flag) const;

	bool hasID() const;
	unsigned short getID() const;
	void setID(unsigned short id);

	unsigned short getSeqID() const;
	void setSeqID(unsigned short id);

	msize_t size() const;

	//Reserve space on the message for filling in later
	msize_t reserve(size_t bytes);

	template<class T>
	msize_t reserve() {
		return reserve(sizeof(T));
	}

	template<class T>
	void fill(msize_t pos, const T& value) {
		memcpy(buffer->data() + pos, (void*)&value, sizeof(T));
	}

	template<class T>
	bool canRead() const {
		return used_bytes * 8 + used_bits >= (read_bytes + sizeof(T)) * 8 + read_bits;
	}

	//Easy write functions (msg << data)
	template<class T>
	void write(T value) {
		writeBits((uint8_t*)&value, sizeof(T) * 8);
	}

	void write(void* ptr, unsigned bytes) {
		writeBits((uint8_t*)ptr, bytes * 8);
	}

	void read(void* ptr, unsigned bytes) {
		readBits((uint8_t*)ptr, bytes * 8);
	}
	
	template<class T>
	Message& operator<<(const T& value) {
		writeBits((uint8_t*)&value, sizeof(T) * 8);
		return *this;
	}

	Message& operator<<(bool bit);
	Message& operator<<(const char* str);
	Message& operator<<(const std::string& str);

	//Easy read functions (msg >> data)
	template<class T>
	Message& operator>>(T& value) {
		readBits((uint8_t*)&value, sizeof(T) * 8);
		return *this;
	}
	
	Message& operator>>(bool& bit);
	Message& operator>>(char*& str);
	Message& operator>>(std::string& str);

	//Writing and reading vectors
	template<class T>
	Message& operator<<(const std::vector<T>& arr) {
		*this << (unsigned short)arr.size();
		for(auto it = arr.begin(), end = arr.end(); it != end; ++it)
			*this << *it;
		return *this;
	}

	template<class T>
	Message& operator>>(const std::vector<T>& arr) {
		unsigned short size;
		*this >> size;
		arr.reserve(size);

		for(unsigned short i = 0; i < size; ++i) {
			T elem;
			*this >> elem;
			arr.push_back(elem);
		}
		return *this;
	}

	//Writing and reading lists
	template<class T>
	Message& operator<<(const std::list<T>& arr) {
		*this << (unsigned short)arr.size();
		for(auto it = arr.begin(), end = arr.end(); it != end; ++it)
			*this << *it;
		return *this;
	}

	template<class T>
	Message& operator>>(const std::list<T>& arr) {
		unsigned short size;
		*this >> size;
		arr.reserve(size);

		for(unsigned short i = 0; i < size; ++i) {
			T elem;
			*this >> elem;
			arr.push_back(elem);
		}
		return *this;
	}

	//Writing and reading maps
	template<class K, class V>
	Message& operator<<(const std::map<K,V>& mp) {
		*this << (unsigned short)mp.size();
		for(auto it = mp.begin(), end = mp.end(); it != end; ++it) {
			*this << it->first;
			*this << it->second;
		}
		return *this;
	}

	template<class K, class V>
	Message& operator>>(const std::map<K,V>& mp) {
		unsigned short size;
		*this >> size;

		for(unsigned short i = 0; i < size; ++i) {
			K key; V value;
			*this >> key;
			*this >> value;

			mp[key] = value;
		}
		return *this;
	}

	//Writing and reading unordered maps
	template<class K, class V>
	Message& operator<<(const std::unordered_map<K,V>& mp) {
		*this << (unsigned short)mp.size();
		for(auto it = mp.begin(), end = mp.end(); it != end; ++it) {
			*this << it->first;
			*this << it->second;
		}
		return *this;
	}

	template<class K, class V>
	Message& operator>>(const std::unordered_map<K,V>& mp) {
		unsigned short size;
		*this >> size;

		for(unsigned short i = 0; i < size; ++i) {
			K key; V value;
			*this >> key;
			*this >> value;

			mp[key] = value;
		}
		return *this;
	}

	template<class T>
	T readIn() {
		T v;
		*this >> v;
		return v;
	}

	void writeSmall(unsigned value);
	unsigned readSmall();

	void writeSignedSmall(int value);
	int readSignedSmall();

	void writeBitValue(unsigned value, uint8_t bits);
	unsigned readBitValue(uint8_t bits);

	void writeLimited(unsigned value, unsigned limit);
	void writeLimited(unsigned value, unsigned min, unsigned max);
	unsigned readLimited(unsigned limit);
	unsigned readLimited(unsigned min, unsigned max);

	void writeFixed(double value, double min, double max, uint8_t bits = 16);
	double readFixed(double min, double max, uint8_t bits = 16);

	//Writes a vec3 to a much smaller version without sacrificing signicant quality
	void writeSmallVec3(double x, double y, double z);
	void readSmallVec3(double& x, double& y, double& z);

	//Writes a vec3 to a smaller version without sacrificing noticeable quality
	void writeMedVec3(double x, double y, double z);
	void readMedVec3(double& x, double& y, double& z);

	//Writes a direction (unit vector) in a very small size
	void writeDirection(double x, double y, double z, unsigned acc = 12);
	void readDirection(double& x, double& y, double& z, unsigned acc = 12);

	//Writes a rotation (unit quaterniond) in a very small size
	void writeRotation(double x, double y, double z, double w);
	void readRotation(double& x, double& y, double& z, double& w);

	void finalize();

	void writeAlign();
	void writeBits(uint8_t* ptr, unsigned bits);

	void readAlign();
	void readBits(uint8_t* ptr, unsigned bits);

	void writeBit(bool bit);
	void write1();
	void write0();

	bool readBit();

	~Message();

	bool hasError() const;

	void clear();
	void dump();

	void reset();

	void advance(unsigned bits);
	void rewind();
	void rewind(unsigned bytes, unsigned bits = 0);

	struct Position {
		msize_t bytes;
		uint8_t bits;
	};

	Position getReadPosition();
	Position getWritePosition();

	void setReadPosition(Position pos);
	void setWritePosition(Position pos);

	void copyTo(Message& to, msize_t fromPos = 0, msize_t toPos = 0) const;

	void move(Message& other);
	void operator=(const Message& other);
	
	uint8_t& operator[](msize_t byte);
	const uint8_t& operator[](msize_t byte) const;

	void getAsPacket(char*& pBytes, msize_t& bytes);
	void setPacket(char* pBytes, msize_t bytes);
private:

	void allocate(msize_t size);

	//Prepares the write stage for the addition of <bytes> bytes
	void _prepwrite(msize_t bytes);

	struct Buffer {
		//Values in every message
		uint8_t type : 8;

		//Not all types have flags, but most do
		uint8_t flags : 8;

		//Optional values, check the flags first
		unsigned short id : 16;
		unsigned short seqID : 16;

		uint8_t* data();

		static Buffer* create(msize_t bytes);
		static Buffer* copyPacket(uint8_t* pBytes, msize_t bytes);
		static void resize(Buffer*& buff, msize_t prevSize, msize_t bytes);
	}* buffer;

	msize_t allocated;

	msize_t used_bytes;
	uint8_t used_bits;
	msize_t read_bytes;
	uint8_t read_bits;

	bool HasID, readError;
};
	
};
