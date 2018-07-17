#pragma once
#include <string>
#include <stdint.h>
#include <functional>

#ifdef _MSC_VER
//Yay more shitty compiler implementation
//assumptions because windows sucks.
struct sockaddr;
struct sockaddr_storage;
struct addrinfo;
typedef int socklen_t;
#else
#include <sys/socket.h>
#include <netdb.h>
#endif

namespace net {

enum AddressType {
	AT_IPv4,
	AT_IPv6,
	AT_INVALID,
};

struct Address {
	AddressType type;
	int port;
	union {
		int adr4;
		uint8_t adr6[16];
		size_t adr6Hash;
	};

	Address();
	Address(const std::string& hostname, int port, AddressType type = AT_IPv4);
	Address(int ip4, int port);
	Address(uint8_t* ip6, int port);

	std::string toString(bool showPort = true) const;

	void to_sockaddr(sockaddr_storage& adr, socklen_t* size = 0) const;
	void from_sockaddr(sockaddr_storage& adr);
	
	bool operator<(const Address& other) const;
	bool operator==(const Address& other) const;
	bool ipEquals(const Address& other) const;
};

struct addrinfo* lookup(const std::string& hostname, int port = 0, AddressType type = AT_IPv4);
	
};

namespace std {
template<>
struct hash<net::Address> {
	size_t operator() (const net::Address& addr) const {
		return addr.type == net::AT_IPv4 ? (size_t)addr.adr4 : addr.adr6Hash;
	}
};
	
};
