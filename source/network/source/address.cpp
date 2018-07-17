#include <network/address.h>
#include <cstring>
#include <sstream>

#ifdef _MSC_VER
#include <WinSock2.h>
#include <ws2def.h>
#include <ws2ipdef.h>
#include <WS2tcpip.h>
#elif defined(__GNUC__)
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#endif

namespace net {

Address::Address() : type(AT_INVALID) {
}

Address::Address(int ip4, int port)
	: type(AT_IPv4), adr4(ip4), port(port) {
}

Address::Address(uint8_t* ip6, int port)
	: type(AT_IPv6), port(port) {
	memcpy(adr6, ip6, 16);
}

bool Address::operator<(const Address& other) const {
	if(type != other.type)
		return type < other.type;
	if(type == AT_IPv4) {
		if(adr4 < other.adr4)
			return true;
		else if(adr4 == other.adr4)
			return port < other.port;
		return false;
	}
	else if(type == AT_IPv6) {
		int lt = memcmp(&adr6, &other.adr6, sizeof(adr6));
		if(lt < 0)
			return true;
		if(lt == 0)
			return port < other.port;
		return false;
	}
	else { //All invalid addresses are equal
		return false;
	}
}

bool Address::operator==(const Address& other) const {
	if(type != other.type)
		return false;
	if(type == AT_IPv4) {
		return port == other.port && adr4 == other.adr4;
	}
	else if(type == AT_IPv6) {
		return port == other.port && memcmp(&adr6, &other.adr6, sizeof(adr6)) == 0;
	}
	else { //All invalid addresses are equal
		return true;
	}
}

bool Address::ipEquals(const Address& other) const {
	if(type != other.type)
		return false;
	if(type == AT_IPv4)
		return adr4 == other.adr4;
	else if(type == AT_IPv6)
		return memcmp(&adr6, &other.adr6, sizeof(adr6)) == 0;
	else
		return false;
}

struct addrinfo* lookup(const std::string& hostname, int port, AddressType type) {
	struct addrinfo* res;
	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));

	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_protocol = IPPROTO_UDP;

	switch(type) {
		case AT_IPv4: hints.ai_family = AF_INET; break;
		case AT_IPv6: hints.ai_family = AF_INET6; break;
		default: hints.ai_family = AF_UNSPEC; break;
	}

	char strport[64];
#ifndef _MSC_VER
	snprintf(strport, 64, "%d", port);
#else
	_snprintf(strport, 64, "%d", port);
#endif

	int code = 0;
	if(hostname.empty()) {
		hints.ai_flags = AI_PASSIVE;
		code = getaddrinfo(0, strport, &hints, &res);
	}
	else {
		code = getaddrinfo(hostname.c_str(), strport, &hints, &res);
	}

	if(code != 0) {
		fprintf(stderr, "getaddrinfo failed: %s\n", gai_strerror(code));
		return 0;
	}

	return res;
}

Address::Address(const std::string& Hostname, int Port, AddressType Type) : type(AT_INVALID) {
	struct addrinfo* res, *head;

	res = head = lookup(Hostname, Port, Type);

	if(!res) {
		fprintf(stderr, "ERROR: Could not resolve hostname \"%s\".\n", Hostname.c_str());
		return;
	}

	from_sockaddr(*(sockaddr_storage*)res->ai_addr);
	freeaddrinfo(head);
}

std::string Address::toString(bool showPort) const {
	std::stringstream out;

	switch(type) {
		case AT_IPv4: {


			struct in_addr adr;
			adr.s_addr = adr4;

#ifndef _MSC_VER
			char buf[INET_ADDRSTRLEN];
			inet_ntop(AF_INET, &adr, buf, INET_ADDRSTRLEN);
			out << buf;
#else
			out << inet_ntoa(adr);
#endif


			if(showPort) {
				out << ":";
				out << port;
			}
		} break;
		case AT_IPv6: {
			if(showPort)
				out << "[";
			
#ifndef _MSC_VER
			char buf[INET6_ADDRSTRLEN];
			struct in6_addr adr;
			memcpy(&adr, adr6, 16);
			inet_ntop(AF_INET6, &adr, buf, INET6_ADDRSTRLEN);
			out << buf;
#else
			//TODO: Actually support this, inet_ntop not reliable on Windows XP
			out << "IPv6";
#endif

			if(showPort) {
				out << "]:";
				out << port;
			}
		} break;
	}

	return out.str();
}

void Address::to_sockaddr(sockaddr_storage& adr, socklen_t* size) const {
	switch(type) {
		case AT_IPv4: {
			sockaddr_in* st = (sockaddr_in*)&adr;
			st->sin_family = AF_INET;
			st->sin_port = htons(port);
			st->sin_addr.s_addr = adr4;

			if(size)
				*size = sizeof(sockaddr_in);
		} break;
		case AT_IPv6: {
			sockaddr_in6* st = (sockaddr_in6*)&adr;
			st->sin6_family = AF_INET6;
			st->sin6_flowinfo = 0;
			st->sin6_port = htons(port);
			st->sin6_scope_id = 0;
			memcpy(&st->sin6_addr, adr6, 16);

			if(size)
				*size = sizeof(sockaddr_in6);
		} break;
	}
}

void Address::from_sockaddr(sockaddr_storage& adr) {
	switch(adr.ss_family) {
		case AF_INET: {
			sockaddr_in* ad = (sockaddr_in*)&adr;
			type = AT_IPv4;
			adr4 = ad->sin_addr.s_addr;
			port = ntohs(ad->sin_port);
		} break;
		case AF_INET6: {
			sockaddr_in6* ad = (sockaddr_in6*)&adr;
			type = AT_IPv6;
			memcpy(adr6, &(ad->sin6_addr), 16);
			port = ntohs(ad->sin6_port);
		} break;
		default:
			fprintf(stderr, "ERROR: Invalid hostname family detected.\n");
		break;
	}
}

};
