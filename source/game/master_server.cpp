#define NET_IDLE_SLEEP 5

#include "network.h"
const int MS_PORT = 8892;

int main(int argc, char** argv) {
	net::LobbyServer srv(MS_PORT);
	srv.runThreads(4);
	while(srv.active)
		threads::sleep(100);
}
