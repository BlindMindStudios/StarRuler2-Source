#include "../include/network/connection.h"
#include "../include/network/transport.h"
#include "../include/network/client.h"
#include "../include/network/sequence.h"
#include "../include/network/lobby.h"
#include <threads.h>

void test_client() {
	net::Address adr("localhost", 2048, net::AT_IPv4);
	net::Client cl(adr);

	cl.handle(net::MT_Application, [](net::Client& cl, net::Message& mess) {
		char* str = 0; char num = 0;
		mess >> str;

		if(mess.readBit())
			mess >> num;

		printf("Response (%d): %s - %d\n", mess.getID(), str, num);
	});

	cl.handle(net::MT_Connect, [](net::Client& cl, net::Message& msg) {
		printf("Connection to %s\n", cl.address.toString().c_str());
	});

	cl.handle(net::MT_Disconnect, [](net::Client& cl, net::Message& msg) {
		net::DisconnectReason reason;
		msg >> reason;

		printf("Disconnection from %s (%d)\n", cl.address.toString().c_str(), reason);
	});

	net::Message msg1(net::MT_Application, net::MF_Sequenced);
	msg1 << "Test Test One";

	net::Message msg2(net::MT_Application, net::MF_Sequenced);
	msg2 << "Test Test Two";

	net::Message msg3(net::MT_Application, net::MF_Sequenced);
	msg3 << "Test Test Three";

	net::Sequence seq(cl);
	seq << msg1;
	seq << msg2;
	seq << msg3;

	cl.runThreads(4);

	threads::sleep(25000);
}

void test_lobby_heartbeat() {
	net::Address adr("localhost", 2044);
	net::LobbyHeartbeat beat(adr, 2012);

	beat.name = "Test Server";
	beat.mod = "Standard";
	beat.players = 1;
	beat.maxPlayers = 8;
	beat.address.port = 2222;
	beat.started = false;

	beat.run();

	threads::sleep(500);

	net::LobbyQuery query(adr, 2012);
	query.name = "Test";
	query.full = net::LFM_False;
	query.started = net::LFM_False;

	query.handler = [](net::Game& game) {
		printf("%s -- %s\n", game.address.toString().c_str(), game.name.c_str());
	};
	query.refresh();

	while(true)
		threads::sleep(1000);
}

void test_broadcast_client() {
	net::BroadcastClient cl(2012);
	net::Message msg(net::MT_Application);

	cl.handle(net::MT_Application + 1, [](net::BroadcastClient& cl, net::Address addr, net::Message& mess) {
		printf("Message %d received from %s\n", mess.getType(), addr.toString().c_str());
	});

	cl.broadcast(msg);
	cl.runThreads(4);

	while(cl.active)
		threads::sleep(1);
}

int main() {
	test_client();
	return 0;
}
