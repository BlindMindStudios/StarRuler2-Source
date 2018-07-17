#include <network/transport.h>
#include <network/init.h>

#ifdef _MSC_VER
#include <WinSock2.h>
#include <ws2def.h>
#include <ws2ipdef.h>
#include <WS2tcpip.h>

#include <time.h>
#elif defined(__GNUC__)
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <unistd.h>

#define INVALID_SOCKET -1
#define SOCKET_ERROR -1
#endif

#ifdef __APPLE__
#define IPV6_ADD_MEMBERSHIP IPV6_JOIN_GROUP
#endif

namespace net {

#ifdef _MSC_VER
static char zero_arg = 0;
static char true_arg = 1;
#else
static int zero_arg = 0;
static int true_arg = 1;
#endif

uint8_t IPV6_MCAST_ALL_NODES[]
	= {0xff, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01};

int Transport::RATE_LIMIT = 1024*250;

Transport::Transport(AddressType Type)
	: references(1), active(true), canBroadcast(false), type(Type), rate(RATE_LIMIT)
{
	net::prepare();
	
	int ai_family = (type == AT_IPv4) ? AF_INET : AF_INET6;
	sockfd = socket(ai_family, SOCK_DGRAM, IPPROTO_UDP);

#ifdef __GNUC__
	ioctl(sockfd, FIONBIO, &true_arg);
#elif defined(_MSC_VER)
	if(sockfd == INVALID_SOCKET) {
		netError("Failed to bind a socket", WSAGetLastError());
		close();
		return;
	}

	int result = ioctlsocket(sockfd, FIONBIO, (u_long*)&true_arg);
	if(result != 0) {
		netError("Failed to set socket state", WSAGetLastError());
		close();
		return;
	}
#endif
}

void Transport::grab() const {
	++references;
}

void Transport::drop() const {
	if(--references == 0)
		delete this;
}

Transport::~Transport() {
	close();
}

void Transport::close() {
	if(active) {
		if(sockfd != INVALID_SOCKET) {
#ifdef _MSC_VER
			closesocket(sockfd);
#else
			::close(sockfd);
#endif
			sockfd = INVALID_SOCKET;
		}

		active = false;
		net::clear();
	}
}

void Transport::listen(Address& address, bool rcvBroadcast) {
	if(!active)
		return;

	canBroadcast = rcvBroadcast;

	sockaddr_storage saddr;
	socklen_t len;

	address.to_sockaddr(saddr, &len);

	int result = bind(sockfd, (sockaddr*)&saddr, len);

	if(result != 0) {
		active = false;
#ifdef _MSC_VER
		closesocket(sockfd);
		netError("Error binding to socket", WSAGetLastError());
#else
		::close(sockfd);
		perror("Error binding socket");
#endif
	}

	if(canBroadcast) {
		if(type == AT_IPv4) {
			setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &true_arg, sizeof(true_arg));
		}
		else {
			//TODO: We gotta test ipv6 somehow
			ipv6_mreq mcast;
			memcpy(&mcast.ipv6mr_multiaddr, IPV6_MCAST_ALL_NODES, 16);
			mcast.ipv6mr_interface = 0;
			setsockopt(sockfd, SOL_SOCKET, IPV6_ADD_MEMBERSHIP, (const char*)&mcast, sizeof(mcast));
			setsockopt(sockfd, SOL_SOCKET, IPV6_MULTICAST_IF, &zero_arg, sizeof(zero_arg));
		}
	}
}

void Transport::process() {
	if(queuedSends.empty() && queuedBroadcasts.empty())
		return;

	threads::Lock queueLock(queueMutex);
	while(!queuedSends.empty()) {
		Message* msg = queuedSends.front().first;
		Address& adr = queuedSends.front().second;

		if(send(*msg, adr, false)) {
			delete msg;
			queuedSends.pop();
		}
		else
			break;
	}

	while(!queuedBroadcasts.empty()) {
		Message* msg = queuedBroadcasts.front().first;
		int port = queuedBroadcasts.front().second;

		if(broadcast(*msg, port, false)) {
			delete msg;
			queuedBroadcasts.pop();
		}
		else
			break;
	}
}

bool Transport::send(Message& msg, Address& address, bool queue) {
	if(!active)
		return false;

	sockaddr_storage saddr;
	socklen_t len;

	address.to_sockaddr(saddr, &len);

	char* pBytes; msize_t byteCount;
	msg.finalize();
	msg.getAsPacket(pBytes, byteCount);

	int bytes = sendto(sockfd, pBytes, byteCount, 0, (sockaddr*)&saddr, len);

	if(bytes == SOCKET_ERROR) {
#ifdef _MSC_VER
		if(WSAGetLastError() == WSAEWOULDBLOCK) {
#else
		if(errno == EAGAIN) {
#endif
			if(queue) {
				threads::Lock queueLock(queueMutex);
				Message* q = new Message(msg);
				queuedSends.push(std::pair<Message*,Address>(q, address));
			}
			return false;
		}

#ifdef _MSC_VER
		netError("Socket write failed", WSAGetLastError());
#else
		perror("Error writing to socket");
#endif
		close();
		return false;
	}
	return true;
}

bool Transport::broadcast(Message& msg, int port, bool queue) {
	if(!active)
		return false;

	if(!canBroadcast) {
		if(type == AT_IPv4)
			setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &true_arg, sizeof(true_arg));
		else
			setsockopt(sockfd, SOL_SOCKET, IPV6_MULTICAST_IF, &zero_arg, sizeof(zero_arg));
		canBroadcast = true;
	}

	sockaddr_storage saddr;
	socklen_t len;

	switch(type) {
		case AT_IPv4: {
			sockaddr_in* st = (sockaddr_in*)&saddr;
			st->sin_family = AF_INET;
			st->sin_port = htons(port);
			st->sin_addr.s_addr = INADDR_BROADCAST;

			len = sizeof(sockaddr_in);
		} break;
		case AT_IPv6: {
			sockaddr_in6* st = (sockaddr_in6*)&saddr;
			st->sin6_family = AF_INET6;
			st->sin6_flowinfo = 0;
			st->sin6_port = htons(port);
			st->sin6_scope_id = 0;
			memcpy(&st->sin6_addr, IPV6_MCAST_ALL_NODES, 16);

			len = sizeof(sockaddr_in6);
		} break;
#ifdef _MSC_VER
		default:
			__assume(0);
#elif defined(__GNUC__)
		default:
			__builtin_unreachable();
#endif
	}

	char* pBytes; msize_t byteCount;
	msg.finalize();
	msg.getAsPacket(pBytes, byteCount);

	int bytes = sendto(sockfd, pBytes, byteCount, 0, (sockaddr*)&saddr, len);

	if(bytes == SOCKET_ERROR) {
#ifdef _MSC_VER
		if(WSAGetLastError() == WSAEWOULDBLOCK) {
#else
		if(errno == EAGAIN) {
#endif
			if(queue) {
				threads::Lock queueLock(queueMutex);
				Message* q = new Message(msg);
				queuedBroadcasts.push(std::pair<Message*,int>(q, port));
			}
			return false;
		}

#ifdef _MSC_VER
		netError("Socket write failed", WSAGetLastError());
#else
		perror("Error writing to socket");
#endif
		close();
	}

	return true;
}

bool Transport::receive(Message& msg, Address& adr) {
	if(!active)
		return false;

	char buffer[USHRT_MAX];
	sockaddr_storage saddr;
	socklen_t len = sizeof(saddr);

	int bytes = recvfrom(sockfd, buffer, USHRT_MAX, 0, (sockaddr*)&saddr, &len);
#ifdef _MSC_VER
	int error = (bytes == SOCKET_ERROR ? WSAGetLastError() : -1);
#endif

	if(bytes > 0) {
		msg.setPacket(buffer, bytes);
		adr.from_sockaddr(saddr);
		return true;
	}
#ifdef _MSC_VER
	else if(error == WSAEWOULDBLOCK || error == WSAECONNRESET) {
#else
	else if(errno == EAGAIN) {
#endif
		return false;
	}
	else {
		close();

#ifdef __GNUC__
		perror("Error reading from socket");
#else
		netError("Error reading from socket", WSAGetLastError());
#endif
		return false;
	}
}
	
};
