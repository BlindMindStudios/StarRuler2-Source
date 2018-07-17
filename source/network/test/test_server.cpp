#include "../include/network/server.h"
#include "../include/network/lobby.h"
#include <threads.h>

void test_server() {
	net::Server srv(2048);

	srv.connHandle(net::MT_Connect, [](net::Server& srv, net::Connection& conn, net::Message& mess) {
		printf("Connection from %s\n", conn.address.toString().c_str());
	});

	srv.connHandle(net::MT_Disconnect, [](net::Server& srv, net::Connection& conn, net::Message& mess) {
		net::DisconnectReason reason;
		mess >> reason;

		printf("Disconnection from %s (%d)\n", conn.address.toString().c_str(), reason);
	});

	srv.connHandle(net::MT_Application, [](net::Server& srv, net::Connection& conn, net::Message& mess) {
		char* str = 0;
		mess >> str;
		printf("Message (%d) received: %s\n", mess.getID(), str);

		net::Message resp(net::MT_Application, net::MF_Reliable);
		resp << "My Reply";
		resp.write1();
		resp << (char)-18;
		conn << resp;
	});

	srv.runThreads(4);

	while(srv.active)
		threads::sleep(1);
}

void test_lobby_server() {
	net::LobbyServer srv(2044);

	srv.runThreads(4);

	while(srv.active)
		threads::sleep(1);
}

void test_broadcast_server() {
	net::Server srv(2012, "", true);

	srv.genHandle(net::MT_Application, [](net::Server& srv, net::Transport& trans,
											net::Address addr, net::Message& mess) {
		printf("Message %d received from %s\n", mess.getType(), addr.toString().c_str());

		net::Message resp(net::MT_Application + 1);
		trans.send(resp, addr);
	});

	srv.runThreads(4);

	while(srv.active)
		threads::sleep(1);
}

int main() {
	test_server();
	return 0;
}
