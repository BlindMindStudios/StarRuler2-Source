#include <network/message.h>
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <algorithm>
#include <stdint.h>

#if defined(_MSC_VER)
#include <intrin.h>
#define GET_MSB(var, x) do{ unsigned long _index_; _BitScanReverse(&_index_, x); var = _index_ + 1; } while(false)
#elif defined(__GNUC__)
#define GET_MSB(var, x) do { var = (32 - __builtin_clz(x)); } while(false)
#else
unsigned _get_msb(unsigned v) {
	unsigned index = 0;
	while((1 << index) <= v)
		++index;
	return index;
}
#define GET_MSB(var, x) do { var = _get_msb(x); } while(false)
#endif

namespace net {

static uint8_t bitmasks[8] = {
	0,
	254,
	252,
	248,
	240,
	224,
	192,
	128,
};

#ifdef _DEBUG
#define check_read(read_size) \
	if(size() < read_bytes + read_size) {\
		readError = true;\
		throw MessageReadError();\
	}
#else
#define check_read(read_size) \
	if(size() < read_bytes + read_size) {\
		readError = true;\
	}
#endif

uint8_t* Message::Buffer::data() {
	return (uint8_t*)this;
}

Message::Buffer* Message::Buffer::create(msize_t bytes) {
	Buffer* b = (Buffer*)malloc(bytes);
	b->type = 0;
	return b;
}

Message::Buffer* Message::Buffer::copyPacket(uint8_t* pBytes, msize_t bytes) {
	Buffer* b = (Buffer*)malloc(bytes);
	memcpy(b, pBytes, bytes);
	return b;
}

void Message::Buffer::resize(Buffer*& buff, msize_t prevSize, msize_t bytes) {
	Buffer* newBuff = (Buffer*)realloc(buff, bytes);
	if(newBuff) {
		buff = newBuff;
	}
	else {
		newBuff = (Buffer*)malloc(bytes);
		if(newBuff == 0)
			throw MessageReadError();
		memcpy(newBuff, buff, prevSize <= bytes ? prevSize : bytes);
		free(buff);
		buff = newBuff;
	}
}

void Message::getAsPacket(char*& pBytes, msize_t& bytes) {
	pBytes = (char*)buffer->data();
	bytes = size();
}

void Message::setPacket(char* pBytes, msize_t bytes) {
	if(!buffer) {
		buffer = Buffer::copyPacket((uint8_t*)pBytes, bytes);
	}
	else {
		Buffer::resize(buffer, allocated, bytes);
		memcpy(buffer, pBytes, bytes);
	}

	used_bytes = bytes;
	used_bits = 0;
	allocated = bytes;

	if(hasFlags()) {
		if(buffer->flags & MF_Sequenced)
			read_bytes = 6;
		else if(buffer->flags & MF_Reliable)
			read_bytes = 4;
		else
			read_bytes = 2;
	}
	else {
		read_bytes = 1;
	}
}
	
uint8_t& Message::operator[](msize_t byte) {
	assert(byte < size());
	return buffer->data()[byte];
}

const uint8_t& Message::operator[](msize_t byte) const {
	assert(byte < size());
	return buffer->data()[byte];
}

void Message::_prepwrite(msize_t bytes) {
	msize_t newUsed = used_bytes + bytes;
	assert(newUsed > used_bytes);

	if(newUsed > allocated) {
		if(allocated == 0) {
			//Always make sure the message has a type
			unsigned alloc = 16;
			if(bytes+1 > alloc)
				alloc = bytes + 1;
			buffer = Buffer::create(alloc);
			buffer->type = MT_Invalid;
			used_bytes = 1;
			read_bytes = 1;
			allocated = alloc;
		}
		else {
			//Make the message bigger
			auto newSize = allocated;

			do {
				newSize = (newSize+1) * 2;
			} while(newSize < newUsed);

			allocate(newSize);
		}
	}
}

Message::Message()
	: buffer(0), allocated(0), used_bytes(0), used_bits(0), read_bytes(0), read_bits(0), HasID(false), readError(false) {
}

Message::Message(uint8_t* data, unsigned bytes)
	: buffer(0), allocated(0), used_bytes(0), used_bits(0), read_bytes(0), read_bits(0), HasID(false), readError(false)
{
	setPacket((char*)data, bytes);
}

Message::Message(uint8_t type, uint8_t flags)
	: buffer(Buffer::create(64)), allocated(64), used_bytes(0), used_bits(0), read_bytes(0), read_bits(0), HasID(false), readError(false)
{
	buffer->type = type;

	if(hasFlags()) {
		buffer->flags = flags;

		if(flags & MF_Sequenced)
			used_bytes = 6;
		else if(flags & MF_Reliable)
			used_bytes = 4;
		else
			used_bytes = 2;

		memset(((char*)buffer)+2, 0, used_bytes-2);
	}
	else {
		used_bytes = 1;
	}

	read_bytes = used_bytes;
}

Message::Message(Message& other) {
	//Copy over all message data
	memcpy(this, &other, sizeof(Message));
	buffer = Buffer::create(other.size());

	//Copy over buffer
	msize_t bytes;
	char* pBytes;
	other.getAsPacket(pBytes, bytes);

	memcpy(buffer, pBytes, bytes);
}

Message::~Message() {
	if(buffer)
		free(buffer);
}

void Message::allocate(msize_t size) {
	if(size <= allocated)
		return;

	if(buffer)
		Buffer::resize(buffer, allocated, size);
	else
		buffer = Buffer::create(size);
	allocated = size;
}

void Message::clear() {
	if(buffer) {
		free(buffer);
		buffer = 0;
	}
	allocated = 0;
	used_bytes = 0;
	used_bits = 0;
	read_bytes = 0;
	read_bits = 0;
	readError = false;
}

void Message::move(Message& other) {
	other.buffer = buffer;
	other.allocated = allocated;
	other.used_bytes = used_bytes;
	other.used_bits = used_bits;
	other.read_bytes = read_bytes;
	other.read_bits = read_bits;
	other.readError = readError;

	buffer = 0;
	clear();
}

void Message::reset() {
	if(buffer == 0)
		return;

	//Reset write to the beginning of the message
	if(hasFlags()) {
		if(buffer->flags & MF_Sequenced)
			used_bytes = 6;
		else if(buffer->flags & MF_Reliable)
			used_bytes = 4;
		else
			used_bytes = 2;

		memset(((char*)buffer)+2, 0, used_bytes-2);
	}
	else {
		used_bytes = 1;
	}
	used_bits = 0;
}

void Message::operator=(const Message& other) {
	used_bytes = other.used_bytes;
	used_bits = other.used_bits;
	read_bytes= other.read_bytes;
	read_bits = other.read_bits;
	readError = other.readError;

	allocate(other.allocated);
	memcpy(buffer, other.buffer, allocated);
}

bool Message::hasError() const {
	return readError;
}

void Message::setType(uint8_t type) {
	buffer->type = type;
}

uint8_t Message::getType() const {
	if(!buffer)
		return MT_Invalid;
	else
		return buffer->type;
}

uint8_t Message::getFlags() const {
	if(!hasFlags())
		return 0;
	else
		return buffer->flags;
}

bool Message::getFlag(uint8_t flag) const {
	if(!hasFlags())
		return false;
	else
		return (buffer->flags & flag) != 0;
}

bool Message::hasFlags() const {
	if(!buffer)
		return false;
	if(buffer->type >= MessageFlagsAll)
		return true;
	return MessageHasFlags[buffer->type];
}

void Message::setFlags(uint8_t flags) {
	if(!hasFlags())
		return;
	buffer->flags = flags;
}

bool Message::hasID() const {
	return HasID;
}

void Message::setID(unsigned short id) {
	if(!buffer || !getFlag(MF_Reliable | MF_Sequenced))
		return;
	buffer->id = id;
	HasID = true;
}

unsigned short Message::getID() const {
	if(!buffer || !getFlag(MF_Reliable | MF_Sequenced))
		return 0;
	return buffer->id;
}

void Message::setSeqID(unsigned short id) {
	if(!buffer || !getFlag(MF_Sequenced))
		return;
	buffer->seqID = id;
}

unsigned short Message::getSeqID() const {
	if(!buffer || !getFlag(MF_Sequenced))
		return 0;
	return buffer->seqID;
}

msize_t Message::size() const {
	if(!buffer)
		return 0;
	else if(used_bits > 0)
		return used_bytes + 1;
	else
		return used_bytes;
}

void Message::finalize() {
	writeAlign();
}

void Message::writeAlign() {
	if(used_bits != 0) {
		_prepwrite(1);
		used_bits = 0;
		used_bytes += 1;
	}
}

void Message::readAlign() {
	if(read_bits != 0) {
		check_read(1);
		if(readError)
			return;
		read_bits = 0;
		read_bytes += 1;
	}
}

void Message::dump() {
	unsigned i = 0, cnt = size();
	uint8_t* data = buffer->data();
	for(; i < cnt; ++i) {
		printf("0x%x ", data[i]);
	}
	printf("\n");
}

void Message::rewind() {
	//Rewind read message
	if(hasFlags()) {
		if(buffer->flags & MF_Sequenced)
			read_bytes = 6;
		else if(buffer->flags & MF_Reliable)
			read_bytes = 4;
		else
			read_bytes = 2;
	}
	else {
		read_bytes = 1;
	}

	read_bits = 0;
}

void Message::rewind(unsigned bytes, unsigned bits) {
	read_bits -= bits;
	while(read_bits < 0) {
		read_bits += 8;
		bytes += 1;
	}

	if(bytes < read_bytes)
		read_bytes -= bytes;
	else
		read_bytes = 0;
}

void Message::advance(unsigned bits) {
	unsigned bytes = bits / 8;
	bits = bits % 8;
	read_bits += bits;
	if(read_bits >= 8) {
		read_bits -= 8;
		bytes += 1;
	}

	read_bytes += bytes;
}

Message::Position Message::getReadPosition() {
	Position pos;
	pos.bytes = read_bytes;
	pos.bits = read_bits;
	return pos;
}

Message::Position Message::getWritePosition() {
	Position pos;
	pos.bytes = used_bytes;
	pos.bits = used_bits;
	return pos;
}

void Message::setReadPosition(Position pos) {
	readError = false;
	if(pos.bytes >= read_bytes) {
		if(pos.bits != 0) {
			check_read(pos.bytes + 1 - read_bytes);
		}
		else if(pos.bytes != read_bytes) {
			check_read(pos.bytes - read_bytes);
		}

		if(readError)
			return;
	}
	read_bytes = pos.bytes;
	read_bits = pos.bits;
}

void Message::setWritePosition(Position pos) {
	if(pos.bytes >= used_bytes) {
		if(pos.bits != 0)
			_prepwrite(pos.bytes + 1 - used_bytes);
		else if(pos.bytes != used_bytes)
			_prepwrite(pos.bytes - used_bytes);
	}
	used_bytes = pos.bytes;
	used_bits = pos.bits;
}

void Message::copyTo(Message& to, msize_t fromPos, msize_t toPos) const {
	auto sz = size();
	if(fromPos >= sz || toPos > sz)
		throw MessageReadError();
	if(toPos == 0) {
		if(used_bits == 0)
			to.writeBits(buffer->data() + fromPos, (used_bytes - fromPos) * 8);
		else
			to.writeBits(buffer->data() + fromPos, (used_bytes - fromPos) * 8 + used_bits);
	}
	else {
		to.writeBits(buffer->data() + fromPos, (toPos - fromPos) * 8);
	}
}

msize_t Message::reserve(size_t bytes) {
	if(used_bits != 0)
		throw "Message needs to be aligned before reserving space";

	_prepwrite(bytes);
	msize_t pos = used_bytes;
	used_bytes += bytes;
	return pos;
}

void Message::writeBits(uint8_t* ptr, unsigned bits) {
	unsigned bytes = bits / 8;
	bits = bits % 8;

	if(used_bits == 0) {
		if(bits == 0) {
			if(bytes == 0)
				return;
			_prepwrite(bytes);

			memcpy(buffer->data() + used_bytes, ptr, bytes);
			used_bytes += bytes;
			return;
		}
		else {
			_prepwrite(bytes + 1);

			memcpy(buffer->data() + used_bytes, ptr, bytes + 1);
			used_bytes += bytes;
			used_bits = bits;
		}
	}
	else {
		if(used_bits + bits <= 8) {
			_prepwrite(bytes + 1);
		}
		else {
			_prepwrite(bytes + 2);
		}

		uint8_t* data = buffer->data();

		uint8_t* pBuffer = (uint8_t*)alloca(bytes+1);
		//Set to upper portion of input data
		for(unsigned i = 0; i < bytes; ++i)
			pBuffer[i] = ptr[i] >> used_bits;
		pBuffer[bytes] = 0;

		//Overlay existing bits
		pBuffer[0] |= data[used_bytes] & (0xff00 >> used_bits);
		//Overlay lower portion of input data
		for(unsigned i = 0; i < bytes; ++i)
			pBuffer[i+1] |= ptr[i] << (8 - used_bits);
		memcpy(data + used_bytes, pBuffer, bytes+1);

		used_bytes += bytes;

		if(bits != 0) {
			uint8_t front_mask = bitmasks[used_bits];
			uint8_t back_mask = ~front_mask;
			uint8_t rev_bits = (8 - used_bits);
			uint8_t ex_mask = bitmasks[rev_bits];

			uint8_t source = ptr[bytes];

			if(used_bits + bits <= 8) {
				data[used_bytes] = (data[used_bytes] & ex_mask) | (source >> used_bits);

				if(used_bits + bits == 8) {
					used_bytes += 1;
					used_bits = 0;
				}
				else
					used_bits += bits;
			}
			else {
				uint8_t front = source & front_mask;
				uint8_t back = source & back_mask;

				data[used_bytes] = (data[used_bytes] & ex_mask) | (front >> used_bits);
				used_bytes += 1;
				data[used_bytes] = back << rev_bits;
				used_bits = (used_bits + bits) % 8;
			}
		}
	}
}

void Message::readBits(uint8_t* ptr, unsigned bits) {
	unsigned bytes = bits / 8;
	bits = bits % 8;

	if(read_bits == 0) {
		if(bits == 0) {
			check_read(bytes);
			if(readError)
				return;
			memcpy(ptr, buffer->data() + read_bytes, bytes);
			read_bytes += bytes;
		}
		else {
			check_read(bytes + 1);
			if(readError)
				return;
			memcpy(ptr, buffer->data() + read_bytes, bytes + 1);
			read_bytes += bytes;
			read_bits = bits;
		}
	}
	else {
		if(read_bits + bits <= 8) {
			check_read(bytes + 1);
		}
		else {
			check_read(bytes + 2);
		}
		if(readError)
			return;
		
		uint8_t* data = buffer->data();

		for(unsigned i = 0; i < bytes; ++i) {
			ptr[i] = (data[read_bytes] << read_bits) | (data[read_bytes+1] >> (8 - read_bits));
			read_bytes += 1;
		}

		if(bits != 0) {
			uint8_t rev_bits = (8 - read_bits);
			uint8_t back_mask = bitmasks[rev_bits];
			uint8_t front_mask = ~back_mask;

			if(read_bits + bits <= 8) {
				ptr[bytes] = (data[read_bytes] & front_mask) << read_bits;

				if(read_bits + bits == 8) {
					read_bytes += 1;
					read_bits = 0;
				}
				else
					read_bits += bits;
			}
			else {
				uint8_t front = data[read_bytes] & front_mask;
				read_bytes += 1;
				uint8_t back = data[read_bytes] & back_mask;

				ptr[bytes] = (front << read_bits) | (back >> rev_bits);
				read_bits = (read_bits + bits) % 8;
			}
		}
	}
}

void Message::writeBit(bool bit) {
	if(bit)
		write1();
	else
		write0();
}

void Message::write1() {
	if(used_bits == 0) {
		_prepwrite(1);
		buffer->data()[used_bytes] = 128;
		used_bits = 1;
	}
	else if (used_bits == 7) {
		buffer->data()[used_bytes] |= 1;
		used_bits = 0;
		used_bytes += 1;
	}
	else {
		buffer->data()[used_bytes] |= 128 >> used_bits;
		used_bits += 1;
	}
}

void Message::write0() {
	if(used_bits == 0) {
		_prepwrite(1);
		buffer->data()[used_bytes] = 0;
		used_bits = 1;
	}
	else if (used_bits == 7) {
		buffer->data()[used_bytes] &= 254;
		used_bits = 0;
		used_bytes += 1;
	}
	else {
		buffer->data()[used_bytes] &= ~(128 >> used_bits);
		used_bits += 1;
	}
}

bool Message::readBit() {
	if(read_bits == 0) {
		check_read(1);
		if(readError)
			return false;
		read_bits = 1;
		return (buffer->data()[read_bytes] & 128) != 0;
	}
	else if(read_bits == 7) {
		bool res = (buffer->data()[read_bytes] & 1) != 0;
		read_bytes += 1;
		read_bits = 0;
		return res;
	}
	else {
		bool res = (buffer->data()[read_bytes] & (128 >> read_bits)) != 0;
		read_bits += 1;
		return res;
	}
}

Message& Message::operator<<(bool bit) {
	writeBit(bit);
	return *this;
}

Message& Message::operator<<(const char* str) {
	writeAlign();

	int len = strlen(str) + 1;
	_prepwrite(len);

	memcpy(buffer->data() + used_bytes, str, len);
	used_bytes += len;
	return *this;
}

Message& Message::operator<<(const std::string& str) {
	writeAlign();

	_prepwrite(str.size() + 1);
	memcpy(buffer->data() + used_bytes, str.c_str(), str.size() + 1);
	used_bytes += str.size() + 1;
	return *this;
}

Message& Message::operator>>(bool& bit) {
	bit = readBit();
	return *this;
}

Message& Message::operator>>(char*& str) {
	readAlign();

	int maxlen = used_bytes - read_bytes;
	int len = strnlen((char*)(buffer->data() + read_bytes), maxlen) + 1;
	if(len > maxlen) {
		str = nullptr;
		throw MessageReadError();
	}

	str = (char*)malloc(len);
	memcpy(str, buffer->data() + read_bytes, len);
	read_bytes += len;
	return *this;
}

Message& Message::operator>>(std::string& str) {
	readAlign();

	int maxlen = used_bytes - read_bytes;
	int len = strnlen((char*)(buffer->data() + read_bytes), maxlen);
	if(len >= maxlen)
		throw MessageReadError();

	str.assign((char*)(buffer->data() + read_bytes), len);
	read_bytes += len + 1;
	return *this;
}

void Message::writeSmall(unsigned value) {
	if(value <= 0x7f) {
		unsigned char chr = ((unsigned char)value) | 0x80;
		writeBits((uint8_t*)&chr, 8);
	}
	else if(value <= 0x3fff) {
		unsigned short chr = ((unsigned short)value);
		uint8_t* ptr = (uint8_t*)&chr;
		//ptr[1] &= ~0x80;
		ptr[1] |= 0x40;
		writeBits(&ptr[1], 8);
		writeBits(&ptr[0], 8);
	}
	else if(value <= 0x1fffffff) {
		unsigned chr = value;
		uint8_t* ptr = (uint8_t*)&chr;
		//ptr[3] &= ~0x80;
		//ptr[3] &= ~0x40;
		ptr[3] |= 0x20;
		writeBits(&ptr[3], 8);
		writeBits(&ptr[2], 8);
		writeBits(&ptr[1], 8);
		writeBits(&ptr[0], 8);
	}
	else {
		write0();
		write0();
		write0();
		writeBits((uint8_t*)&value, 32);
	}
}

unsigned Message::readSmall() {
	if(readBit()) {
		unsigned char chr;
		readBits((uint8_t*)&chr, 7);
		return chr >> 1;
	}
	else if(readBit()){
		unsigned short chr;
		uint8_t* ptr = (uint8_t*)&chr;
		readBits(&ptr[1], 6);
		readBits(&ptr[0], 8);
		ptr[1] >>= 2;
		return chr;
	}
	else if(readBit()){
		unsigned chr;
		uint8_t* ptr = (uint8_t*)&chr;
		readBits(&ptr[3], 5);
		readBits(&ptr[2], 8);
		readBits(&ptr[1], 8);
		readBits(&ptr[0], 8);
		ptr[3] >>= 3;
		return chr;
	}
	else {
		unsigned chr;
		readBits((uint8_t*)&chr, 32);
		return chr;
	}
}

void Message::writeSignedSmall(int value) {
	unsigned absValue;
	bool sign;
	if(value < 0) {
		absValue = (unsigned)(value * -1);
		sign = true;
	}
	else {
		absValue = (unsigned)value;
		sign = false;
	}

	if(absValue <= 0x3f) {
		unsigned char chr = ((unsigned char)absValue) | 0x80;
		if(sign)
			chr |= 0x40;
		writeBits((uint8_t*)&chr, 8);
	}
	else if(absValue <= 0x1fff) {
		unsigned short chr = ((unsigned short)absValue);
		uint8_t* ptr = (uint8_t*)&chr;
		//ptr[1] &= ~0x80;
		ptr[1] |= 0x40;
		if(sign)
			ptr[1] |= 0x20;
		// else
		//  ptr[1] &= ~0x20;
		writeBits(&ptr[1], 8);
		writeBits(&ptr[0], 8);
	}
	else if(absValue <= 0x0fffffff) {
		unsigned chr = absValue;
		uint8_t* ptr = (uint8_t*)&chr;
		//ptr[3] &= ~0x80;
		//ptr[3] &= ~0x40;
		ptr[3] |= 0x20;
		if(sign)
			ptr[3] |= 0x10;
		// else
		//  ptr[3] &= ~0x10;
		writeBits(&ptr[3], 8);
		writeBits(&ptr[2], 8);
		writeBits(&ptr[1], 8);
		writeBits(&ptr[0], 8);
	}
	else {
		write0();
		write0();
		write0();
		writeBits((uint8_t*)&value, 32);
	}
}

int Message::readSignedSmall() {
	if(readBit()) {
		bool sign = readBit();
		unsigned char chr = 0;
		readBits((uint8_t*)&chr, 6);
		chr >>= 2;
		if(sign)
			return -1 * (char)chr;
		return (char)chr;
	}
	else if(readBit()){
		bool sign = readBit();
		short chr = 0;
		uint8_t* ptr = (uint8_t*)&chr;
		readBits(&ptr[1], 5);
		readBits(&ptr[0], 8);
		ptr[1] >>= 3;
		if(sign)
			chr *= -1;
		return chr;
	}
	else if(readBit()){
		bool sign = readBit();
		int chr = 0;
		uint8_t* ptr = (uint8_t*)&chr;
		readBits(&ptr[3], 4);
		readBits(&ptr[2], 8);
		readBits(&ptr[1], 8);
		readBits(&ptr[0], 8);
		ptr[3] >>= 4;
		if(sign)
			chr *= -1;
		return chr;
	}
	else {
		int chr = 0;
		readBits((uint8_t*)&chr, 32);
		return chr;
	}
}

void Message::writeBitValue(unsigned value, uint8_t bits) {
	uint8_t* ptr = (uint8_t*)&value;

	uint8_t index = 0;
	while(bits >= 8 && index <= 3) {
		writeBits(&ptr[index], 8);
		bits -= 8;
		++index;
	}

	if(bits != 0 && index <= 3) {
		ptr[index] <<= (8 - bits);
		writeBits(&ptr[index], bits);
	}
}

unsigned Message::readBitValue(uint8_t bits) {
	int value = 0;
	uint8_t* ptr = (uint8_t*)&value;

	uint8_t index = 0;
	while(bits >= 8 && index <= 3) {
		readBits(&ptr[index], 8);
		bits -= 8;
		++index;
	}

	if(bits != 0 && index <= 3) {
		readBits(&ptr[index], bits);
		ptr[index] >>= (8 - bits);
	}
	return value;
}

void Message::writeLimited(unsigned value, unsigned limit) {
	if(limit == 0)
		return;
	int msb = 0;
	GET_MSB(msb, limit);
	writeBitValue(value, msb);
}

void Message::writeLimited(unsigned value, unsigned min, unsigned max) {
	writeLimited(value, max-min);
}

unsigned Message::readLimited(unsigned limit) {
	if(limit == 0)
		return 0;
	int msb = 0;
	GET_MSB(msb, limit);
	return readBitValue(msb);
}

unsigned Message::readLimited(unsigned min, unsigned max) {
	return readLimited(max-min) + min;
}

void Message::writeSmallVec3(double x, double y, double z) {
	unsigned mode = 0;
	double primaryDim;

	double xa = abs(x), ya = abs(y), za = abs(z);

	if(xa > ya) {
		if(xa > za) {
			//mode = 0;
			primaryDim = x;
		}
		else {
			mode = 2;
			primaryDim = z;
		}
	}
	else if(ya > za) {
		mode = 1;
		primaryDim = y;
	}
	else if(za > 0) {
		mode = 2;
		primaryDim = z;
	}
	else {
		mode = 3;
	}
	writeBitValue(mode, 2);
	if(mode == 3)
		return;

	bool flip;
	double secondaryDim, tertiaryDim;

	if(mode == 0) {
		flip = za > ya;
		secondaryDim = y;
		tertiaryDim = z;
	}
	else if(mode == 1) {
		flip = xa > za;
		secondaryDim = z;
		tertiaryDim = x;
	}
	else if(mode == 2) {
		flip = ya > xa;
		secondaryDim = x;
		tertiaryDim = y;
	}

	writeBit(flip);
	if(flip)
		std::swap(secondaryDim, tertiaryDim);
	writeFixed(secondaryDim / primaryDim, -1.0, 1.0, 18);
	if(secondaryDim != 0.0)
		writeFixed(tertiaryDim / secondaryDim, -1.0, 1.0, 15);
	else
		writeFixed(0.0, -1.0, 1.0, 15);

	float fPrimaryDim = primaryDim;
	unsigned floatBits = *(unsigned*)&fPrimaryDim;
	writeBitValue(floatBits >> 4, 28);
}

void Message::readSmallVec3(double& x, double& y, double& z) {
	unsigned mode = readBitValue(2);
	if(mode == 3) {
		x = y = z = 0;
		return;
	}

	bool flip = readBit();
	
	double minorDims[2];
	minorDims[0] = readFixed(-1.0, 1.0, 18);
	minorDims[1] = readFixed(-1.0, 1.0, 15) * minorDims[0];

	unsigned floatBits = readBitValue(28) << 4;
	double primaryDim = *(float*)&floatBits;

	if(flip)
		std::swap(minorDims[0], minorDims[1]);

	switch(mode) {
	case 0:
		x = primaryDim;
		y = primaryDim * minorDims[0];
		z = primaryDim * minorDims[1];
		break;
	case 1:
		y = primaryDim;
		z = primaryDim * minorDims[0];
		x = primaryDim * minorDims[1];
		break;
	case 2:
		z = primaryDim;
		x = primaryDim * minorDims[0];
		y = primaryDim * minorDims[1];
		break;
	}
}

void Message::writeMedVec3(double x, double y, double z) {
	unsigned mode = 0;
	double primaryDim;

	double xa = abs(x), ya = abs(y), za = abs(z);

	if(xa > ya) {
		if(xa > za) {
			//mode = 0;
			primaryDim = x;
		}
		else {
			mode = 2;
			primaryDim = z;
		}
	}
	else if(ya > za) {
		mode = 1;
		primaryDim = y;
	}
	else if(za > 0) {
		mode = 2;
		primaryDim = z;
	}
	else {
		mode = 3;
	}
	writeBitValue(mode, 2);
	if(mode == 3)
		return;

	bool flip;
	double secondaryDim, tertiaryDim;

	if(mode == 0) {
		flip = za > ya;
		secondaryDim = y;
		tertiaryDim = z;
	}
	else if(mode == 1) {
		flip = xa > za;
		secondaryDim = z;
		tertiaryDim = x;
	}
	else if(mode == 2) {
		flip = ya > xa;
		secondaryDim = x;
		tertiaryDim = y;
	}

	writeBit(flip);
	if(flip)
		std::swap(secondaryDim, tertiaryDim);
	writeFixed(secondaryDim / primaryDim, -1.0, 1.0, 32);
	if(secondaryDim != 0.0)
		writeFixed(tertiaryDim / secondaryDim, -1.0, 1.0, 29);
	else
		writeFixed(0.0, -1.0, 1.0, 29);

	*this << (float)primaryDim;
}

void Message::readMedVec3(double& x, double& y, double& z) {
	unsigned mode = readBitValue(2);
	if(mode == 3) {
		x = y = z = 0;
		return;
	}

	bool flip = readBit();
	
	double minorDims[2];
	minorDims[0] = readFixed(-1.0, 1.0, 32);
	minorDims[1] = readFixed(-1.0, 1.0, 29) * minorDims[0];
	float fPrimaryDim;
	*this >> fPrimaryDim;
	double primaryDim = fPrimaryDim;

	if(flip)
		std::swap(minorDims[0], minorDims[1]);

	switch(mode) {
	case 0:
		x = primaryDim;
		y = primaryDim * minorDims[0];
		z = primaryDim * minorDims[1];
		break;
	case 1:
		y = primaryDim;
		z = primaryDim * minorDims[0];
		x = primaryDim * minorDims[1];
		break;
	case 2:
		z = primaryDim;
		x = primaryDim * minorDims[0];
		y = primaryDim * minorDims[1];
		break;
	}
}

//Slightly larger than pi to avoid checking for bounds
const double _pi = 3.141593;

void Message::writeDirection(double x, double y, double z, unsigned acc) {
	writeFixed(acos(z),0.0,_pi,acc-1);
	writeFixed(atan2(y,x),-_pi,_pi,acc+1);
}

void Message::readDirection(double& x, double& y, double& z, unsigned acc) {
	z = cos(readFixed(0.0,_pi,acc-1));
	double ang = readFixed(-_pi,_pi,acc+1);

	double l = sqrt(1.0 - z*z);
	x = cos(ang) * l;
	y = sin(ang) * l;

	l = sqrt(x*x + y*y + z*z);
	x /= l;
	y /= l;
	z /= l;
}

void Message::writeRotation(double x, double y, double z, double w) {
	writeFixed(acos(x),0.0,_pi,11);
	double l = sqrt(y*y + z*z + w*w);
	writeFixed(acos(y/l),0.0,_pi,11);
	writeFixed(atan2(w,z),-_pi,_pi,10);
}

void Message::readRotation(double& x, double& y, double& z, double& w) {
	x = cos(readFixed(0.0,_pi,11));

	double l = sqrt(1.0 - std::min(x*x,1.0));
	y = cos(readFixed(0.0,_pi,11)) * l;

	double ang = readFixed(-_pi,_pi,10);
	l = sqrt(1.0 - std::min(x*x+y*y,1.0));
	z = cos(ang) * l;
	w = sin(ang) * l;

	l = sqrt(x*x + y*y + z*z + w*w);

	x /= l;
	y /= l;
	z /= l;
	w /= l;
}

void Message::writeFixed(double value, double min, double max, uint8_t bits) {
	if(bits > 32)
		bits = 32;
	else if(bits < 2)
		bits = 2;

	double step = (max - min) / (double)(((int64_t)1 << bits) - 1);
	double halfStep = step * 0.5;

	if(value <= min) {
		writeBitValue(0, bits);
		return;
	}
	else if(value >= max - halfStep) {
		writeBitValue(0xffffffff, bits);
		return;
	}

	unsigned x = (unsigned)((value - min + halfStep) / step);
	writeBitValue(x, bits);
}

double Message::readFixed(double min, double max, uint8_t bits) {
	if(bits > 32)
		bits = 32;
	else if(bits < 2)
		bits = 2;

	double step = (max - min) / (double)(((int64_t)1 << bits) - 1);
	unsigned x = (unsigned)readBitValue(bits);
	return min + (step * (double)x);
}

};
