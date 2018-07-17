#pragma once
#include <limits.h>

namespace net {

enum MessageType : unsigned char {
	//Builtin message types
	MT_Invalid = 0,
	MT_Connect,
	MT_Disconnect,
	MT_Close_Sequence,

	MT_Ping,
	MT_Pong,
	MT_Ack,
	MT_SeqAck,

	MT_Fragment,
	MT_LastFragment,
	MT_Punchthrough,

	//The application starts defining message types here
	MT_Application = 0x10,
};

enum DisconnectReason : unsigned char {
	DR_Timeout,
	DR_Error,
	DR_Close,
	DR_Kick,
	DR_Version,
	DR_Password,
	DR_NULL
};

const bool MessageHasFlags[] = {
	false, //MT_Invalid
	true, //MT_Connect
	true, //MT_Disconnect
	true, //MT_Close_Sequence
	false, //MT_Ping
	false, //MT_Pong
	false, //MT_Ack
	false, //MT_SeqAck
	true, //MT_Fragment
	true, //MT_LastFragment
	false, //MT_Punchthrough
};

const int MessageFlagsAll = sizeof(MessageHasFlags) / sizeof(bool);

enum MessageFlags : unsigned char {
	MF_Reliable = 0x1,
	MF_Sequenced = 0x2,
	MF_Acknowledged = 0x80,
	MF_Managed = MF_Reliable | MF_Sequenced,
};

};
