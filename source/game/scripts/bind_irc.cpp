#include "scripts/binds.h"
#include "threads.h"
#include <deque>
#include <string>
#include <vector>
#include <map>
#include <time.h>
#include <stdlib.h>
#include "util/refcount.h"
#include "network/init.h"
#include "libircclient.h"
#include "libirc_rfcnumeric.h"
#include "str_util.h"
#include <algorithm>
#include "main/references.h"
#include "scriptarray.h"

#ifdef _MSC_VER
#include <string.h>
#define strncasecmp _strnicmp
#else
#include <strings.h>
#endif

namespace scripts {

const unsigned MESSAGE_HISTORY_LENGTH = 100;
const std::string ircServer("irc.glacicle.org");
const unsigned ircPort = 6667;
const std::string userNick("SRPlayer");
std::string userDesc("SR2ALPHA");
static threads::threadreturn threadcall IRCThread(void* ptr);

static void _event_connect(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_join(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_part(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_quit(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_nick(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_topic(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_privmsg(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_channel(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_action(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_mode(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_umode(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count);
static void _event_numeric(irc_session_t* session, unsigned event, const char* origin, const char** params, unsigned int count);

struct caseless_less : std::binary_function<std::string, std::string, bool> {
    bool operator()(const std::string& left, const std::string& right) const {
		if(left.size() != right.size())
			return left.size() < right.size();
		return strncasecmp(left.c_str(), right.c_str(), left.size()) < 0;
	}
};

class IRC {
public:
	enum MessageType {
		MT_Join,
		MT_Part,
		MT_Action,
		MT_Message,
		MT_Nick,
		MT_Quit,
		MT_Kick,
		MT_Mode,
		MT_UMode,
		MT_Topic,
		MT_TopicIs,
		MT_Disconnect,
	};

	struct User {
		char type;
		std::string name;

		User() : type(' ') {
		}
	};

	struct Message {
		User sender;
		MessageType type;
		unsigned id;
		std::string message;
	};

	struct Channel : AtomicRefCounted {
		threads::Mutex mutex;
		std::string name;
		std::string topic;
		unsigned messageId;
		unsigned handledId;
		std::map<std::string, User, caseless_less> users;
		std::deque<Message> history;
		bool isPM;
		bool active, closed, highlight;

		Channel() : messageId(1), handledId(0), isPM(false), active(true), closed(false), highlight(false) {
		}

		std::string getTopic() {
			threads::Lock lock(mutex);
			return topic;
		}

		unsigned getMessageCount() {
			return history.size();
		}

		unsigned getUserCount() {
			return users.size();
		}

		std::string getMessage(unsigned index) {
			threads::Lock lock(mutex);
			if(index >= history.size())
				return "";
			return history[index].message;
		}

		std::string getSender(unsigned index) {
			threads::Lock lock(mutex);
			if(index >= history.size())
				return "";
			return history[index].sender.name;
		}

		MessageType getMessageType(unsigned index) {
			threads::Lock lock(mutex);
			if(index >= history.size())
				return MT_Message;
			return history[index].type;
		}

		unsigned getMessageId(unsigned index) {
			threads::Lock lock(mutex);
			if(index >= history.size())
				return (unsigned)-1;
			return history[index].id;
		}

		char getSenderType(unsigned index) {
			threads::Lock lock(mutex);
			if(index >= history.size())
				return ' ';
			return history[index].sender.type;
		}

		void getUsers(CScriptArray* arr) {
			threads::Lock lock(mutex);
			arr->Resize(users.size());

			unsigned ind = 0;
			foreach(it, users) {
				std::string* str = (std::string*)arr->At(ind);
				++ind;

				*str = it->second.type;
				*str += it->second.name;
			}
		}
	};

	threads::Mutex mutex;
	std::map<std::string, Channel*, caseless_less> channel_names;
	std::vector<Channel*> channels;
	std::string error;
	std::string currentNickname;
	bool running, connected, highlight;
	bool shouldConnect;
	bool hasNet;
	recti display;

	irc_session_t* session;
	irc_callbacks_t callbacks;

	IRC() : running(false), connected(false), highlight(false), hasNet(false), session(nullptr), shouldConnect(false) {
		memset(&callbacks, 0, sizeof(irc_callbacks_t));
		callbacks.event_connect = _event_connect;
		callbacks.event_numeric = _event_numeric;
		callbacks.event_join = _event_join;
		callbacks.event_part = _event_part;
		callbacks.event_quit = _event_quit;
		callbacks.event_nick = _event_nick;
		callbacks.event_topic = _event_topic;
		callbacks.event_mode = _event_mode;
		callbacks.event_umode = _event_umode;
		callbacks.event_privmsg = _event_privmsg;
		callbacks.event_notice = _event_privmsg;
		callbacks.event_ctcp_action = _event_action;
		callbacks.event_channel = _event_channel;
		callbacks.event_channel_notice = _event_channel;
		currentNickname = userNick;
	}

	void clear() {
		channel_names.clear();
		foreach(it, channels)
			(*it)->drop();
		channels.clear();
	}

	~IRC() {
		if(session) {
			irc_destroy_session(session);
			session = nullptr;
		}
		if(hasNet) {
			net::clear();
			hasNet = false;
		}
		clear();
	}

	void connect() {
		if(running) {
			scripts::throwException("Connecting while already connected.");
			return;
		}

		if(!hasNet) {
			net::prepare();
			hasNet = true;
		}
		if(session)
			irc_destroy_session(session);
		clear();

		session = irc_create_session(&callbacks);
		if(!session) {
			error = "Could not create session.";
			net::clear();
			return;
		}

		shouldConnect = true;
		running = true;
		threads::createThread(IRCThread, this);
	}

	Channel* join(const std::string& channel) {
		if(!connected) {
			scripts::throwException("IRC not connected.");
			return nullptr;
		}

		if(int status = irc_cmd_join(session, channel.c_str(), 0)) {
			error = irc_strerror(status);
			return nullptr;
		}

		threads::Lock lock(mutex);
		Channel* chnl = new Channel();
		chnl->name = channel;
		chnl->topic = chnl->name;

		channel_names[chnl->name] = chnl;
		channels.push_back(chnl);

		chnl->grab();
		return chnl;
	}

	bool part(Channel* chnl) {
		if(!connected) {
			scripts::throwException("IRC not connected.");
			return false;
		}

		threads::Lock lock(mutex);
		threads::Lock chnlock(chnl->mutex);

		if(chnl->isPM) {
			error = "Cannot part from private message channel.";
			return false;
		}

		if(int code = irc_cmd_part(session, chnl->name.c_str())) {
			error = irc_strerror(code);
			return false;
		}

		chnl->active = false;
		return true;
	}

	void close(Channel* chnl) {
		if(chnl->active && !chnl->isPM)
			part(chnl);

		auto it = channel_names.find(chnl->name);
		if(it != channel_names.end())
			channel_names.erase(it);

		auto ch = std::find(channels.begin(), channels.end(), chnl);
		if(ch != channels.end())
			channels.erase(ch);

		chnl->closed = true;
		chnl->drop();
	}

	void send(Channel* chnl, const std::string& message) {
		if(!connected) {
			error = "IRC not connected.";
			return;
		}

		threads::Lock lock(mutex);

		//Handle slash commands
		if(message[0] == '/' && message.size() > 1) {
			auto pos = message.find(' ');
			if(pos == std::string::npos)
				pos = message.size();

			std::string cmd = message.substr(1, pos-1);
			std::string remain;
			if(pos < message.size()-2)
				remain = message.substr(pos+1);

			if(cmd == "join") {
				if(remain.size() != 0) {
					if(!join(remain))
						_message(*chnl, ">", error.c_str());
				}
			}
			else if(cmd == "part" || cmd == "leave") {
				if(!part(chnl))
					_message(*chnl, ">", error.c_str());
			}
			else if(cmd == "close") {
				close(chnl);
			}
			else if(cmd == "me") {
				irc_cmd_me(session, chnl->name.c_str(), remain.c_str());
				_message(*chnl, currentNickname.c_str(), remain.c_str(), MT_Action);
			}
			else if(cmd == "nick") {
				setNickname(remain);
			}
			else if(cmd == "msg") {
				pos = remain.find(' ');
				if(pos == std::string::npos)
					return;

				std::string user = remain.substr(0, pos);
				std::string msg;
				if(pos < remain.size()-2)
					msg = remain.substr(pos+1);

				Channel* chan = privmsg(user);
				send(chan, msg);
				chan->drop();
			}
			else if(cmd == "kick") {
				pos = remain.find(' ');
				if(pos == std::string::npos)
					return;

				std::string user = remain.substr(0, pos);
				std::string msg;
				if(pos < remain.size()-2)
					msg = remain.substr(pos+1);

				kick(chnl, user, msg);
			}
			else if(cmd == "topic") {
				if(remain.size() == 0)
					irc_cmd_topic(session, chnl->name.c_str(), nullptr);
				else
					setTopic(chnl, remain);
			}
			else if(cmd == "mode") {
				irc_cmd_channel_mode(session, chnl->name.c_str(), remain.c_str());
			}
			else if(cmd == "umode") {
				irc_cmd_user_mode(session, remain.c_str());
			}
			else if(cmd == "names") {
				irc_cmd_names(session, chnl->name.c_str());
			}
			else if(cmd == "invite") {
				irc_cmd_invite(session, remain.c_str(), chnl->name.c_str());
			}
			else if(cmd == "disconnect") {
				irc_disconnect(session);
				return;
			}
			else {
				_message(*chnl, "HELP", devices.locale.localize("#IRC_HELP").c_str());
				return;
			}
		}
		else {
			irc_cmd_msg(session, chnl->name.c_str(), message.c_str());
			_message(*chnl, currentNickname.c_str(), message.c_str());
		}
	}

	Channel* privmsg(const std::string& user) {
		if(!connected) {
			error = "IRC not connected.";
			return nullptr;
		}

		threads::Lock lock(mutex);
		auto it = channel_names.find(user);
		if(it != channel_names.end()) {
			it->second->grab();
			return it->second;
		}

		Channel* chnl = new Channel();
		chnl->name = user;
		chnl->topic = user;
		chnl->isPM = true;

		channel_names[chnl->name] = chnl;
		channels.push_back(chnl);
		chnl->grab();

		return chnl;
	}

	void setTopic(Channel* chan, const std::string& topic) {
		if(!connected) {
			error = "IRC not connected.";
			return;
		}

		irc_cmd_topic(session, chan->name.c_str(), topic.c_str());
	}

	void kick(Channel* chan, const std::string& user, const std::string& message) {
		if(!connected) {
			error = "IRC not connected.";
			return;
		}

		irc_cmd_kick(session, user.c_str(), chan->name.c_str(), message.c_str());
		_message(*chan, currentNickname.c_str(), user.c_str(), MT_Kick);
	}

	void _message(Channel& chnl, const char* user, const char* message, MessageType type = MT_Message) {
		threads::Lock chlock(chnl.mutex);

		//Create message
		Message msg;
		msg.type = type;
		msg.id = chnl.messageId;
		if(message)
			msg.message = message;

		//Find the user in the channel that sent it
		if(user) {
			auto usr = chnl.users.find(user);
			if(usr != chnl.users.end())
				msg.sender = usr->second;
			else
				msg.sender.name = user;
		}

		//Add message to channel
		if(chnl.history.size() >= MESSAGE_HISTORY_LENGTH)
			chnl.history.pop_front();
		chnl.history.push_back(msg);
		chnl.messageId += 1;
	}

	void _message(const char* channel, const char* user, const char* message, MessageType type = MT_Message) {
		threads::Lock lock(mutex);

		//Find the channel this message is for
		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			_message(chnl, user, message, type);
		}
	}

	void _messageall(const char* user, const char* message, MessageType type = MT_Message) {
		threads::Lock lock(mutex);

		//Find the channel this message is for
		foreach(it, channels) {
			Channel& chnl = **it;
			_message(chnl, user, message, type);
		}
	}

	void _getusers(const char* channel) {
		threads::Lock lock(mutex);
		irc_cmd_names(session, channel);
	}

	void _nickchange(const char* from, const char* to) {
		threads::Lock lock(mutex);

		if(currentNickname == from)
			currentNickname = to;

		foreach(it, channels) {
			Channel& chnl = **it;
			threads::Lock chlock(chnl.mutex);

			auto usr = chnl.users.find(from);
			if(usr != chnl.users.end()) {
				chnl.users.erase(usr);

				User newusr;
				newusr.name = to;
				chnl.users[newusr.name] = newusr;

				_message(**it, from, to, MT_Nick);
			}
		}
	}

	void _name(const char* channel, const std::string& name) {
		if(name.size() == 0)
			return;

		User usr;
		if((name[0] >= 'A' && name[0] <= 'Z') || (name[0] >= 'a' && name[0] <= 'z') || name[0] == '_') {
			usr.name = name;
		}
		else {
			usr.name = name.substr(1);
			usr.type = name[0];
		}

		threads::Lock lock(mutex);
		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			chnl.users[usr.name] = usr;
		}
	}

	void _poke(const char* channel) {
		threads::Lock lock(mutex);
		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			chnl.messageId += 1;
		}
	}

	void _onquit(const char* from, const char* message) {
		threads::Lock lock(mutex);

		foreach(it, channels) {
			Channel& chnl = **it;
			threads::Lock chlock(chnl.mutex);

			auto usr = chnl.users.find(from);
			if(usr != chnl.users.end()) {
				chnl.users.erase(usr);
				_message(**it, from, message, MT_Quit);
			}
		}
	}

	void _onjoin(const char* channel, const char* from) {
		threads::Lock lock(mutex);

		Channel* chan = nullptr;
		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			chan = it->second;
		}
		else if(currentNickname == from) {
			//Add channel to our channels
			chan = new Channel();
			chan->name = channel;
			chan->topic = chan->name;

			channel_names[chan->name] = chan;
			channels.push_back(chan);
		}

		if(chan) {
			Channel& chnl = *chan;
			threads::Lock chlock(chnl.mutex);

			User usr;
			usr.name = from;
			chnl.users[usr.name] = usr;

			_message(chnl, from, nullptr, MT_Join);
		}
	}

	void _onpart(const char* channel, const char* from, const char* message) {
		threads::Lock lock(mutex);

		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			threads::Lock chlock(chnl.mutex);

			auto usr = chnl.users.find(from);
			if(usr != chnl.users.end())
				chnl.users.erase(usr);

			if(currentNickname == from)
				chnl.active = false;

			_message(chnl, from, message, MT_Part);
		}
	}

	void _onkick(const char* channel, const char* from, const char* kicked, const char* message) {
		threads::Lock lock(mutex);

		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			threads::Lock chlock(chnl.mutex);

			auto usr = chnl.users.find(from);
			if(usr != chnl.users.end())
				chnl.users.erase(usr);

			if(currentNickname == kicked)
				chnl.active = false;

			_message(chnl, from, kicked, MT_Part);
		}
	}

	void _topic_is(const char* channel, const char* topic) {
		threads::Lock lock(mutex);

		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			threads::Lock chlock(chnl.mutex);

			chnl.topic = topic;
			_message(chnl, nullptr, topic, MT_TopicIs);
		}
	}

	void _ontopic(const char* channel, const char* from, const char* message) {
		threads::Lock lock(mutex);

		auto it = channel_names.find(channel);
		if(it != channel_names.end()) {
			Channel& chnl = *it->second;
			threads::Lock chlock(chnl.mutex);

			chnl.topic = message;
			_message(chnl, from, message, MT_Topic);
		}
	}

	void _onprivmsg(const char* from, const char* message) {
		threads::Lock lock(mutex);
		auto it = channel_names.find(from);

		Channel* chnl;
		if(it == channel_names.end()) {
			chnl = new Channel();
			chnl->name = from;
			chnl->topic = from;
			chnl->isPM = true;

			channel_names[chnl->name] = chnl;
			channels.push_back(chnl);
		}
		else {
			chnl = it->second;
		}

		threads::Lock chlock(chnl->mutex);
		_message(*chnl, from, message, MT_Message);
	}

	void _onaction(const char* channel, const char* from, const char* message) {
		_message(channel, from, message, MT_Action);
	}

	void disconnect() {
		if(!running) {
			scripts::throwException("Disconnecting while not connected.");
			return;
		}

		shouldConnect = false;
		connected = false;
		irc_disconnect(session);

		while(running)
			threads::sleep(1);

		net::clear();
		hasNet = false;
		irc_destroy_session(session);
		session = nullptr;
	}

	unsigned getChannelCount() {
		return channels.size();
	}

	Channel* getChannel(unsigned index) {
		threads::Lock lock(mutex);
		if(index >= channels.size())
			return 0;
		channels[index]->grab();
		return channels[index];
	}

	Channel* getChannelByName(const std::string& name) {
		threads::Lock lock(mutex);
		auto it = channel_names.find(name);
		if(it == channel_names.end())
			return 0;
		it->second->grab();
		return it->second;
	}

	std::string getNickname() {
		threads::Lock lock(mutex);
		return currentNickname;
	}

	void setNickname(const std::string& newNick) {
		threads::Lock lock(mutex);

		std::string escaped;
		for(size_t i = 0, cnt = newNick.size(); i < cnt; ++i) {
			char chr = newNick[i];
			if(chr >= 'a' && chr <= 'z') {
				escaped += chr;
				continue;
			}
			if(chr >= 'A' && chr <= 'Z') {
				escaped += chr;
				continue;
			}
			if(i > 0 && chr >= '0' && chr <= '9') {
				escaped += chr;
				continue;
			}
			switch(chr) {
				case '-':
					if(i == 0)
						break;
				case '_':
				case '[':
				case ']':
				case '|':
				case '\\':
				case '{':
				case '}':
				case '^':
				case '`':
					escaped += chr;
					continue;
			}

			escaped += "_";
		}
		if(escaped.empty())
			escaped = "INVALID";
		if(escaped.size() > 20)
			escaped = escaped.substr(0, 20);

		currentNickname = escaped;

		if(connected)
			irc_cmd_nick(session, currentNickname.c_str());
	}
};

static threads::threadreturn threadcall IRCThread(void* ptr) {
	IRC& irc = *(IRC*)ptr;
	srand((unsigned)time(nullptr));

	std::string nickname;
	{
		threads::Lock lock(irc.mutex);
		nickname = irc.currentNickname;
	}
	irc_option_set(irc.session, LIBIRC_OPTION_STRIPNICKS);

	unsigned tries = 0;
	do {
		if(int err = irc_connect(irc.session, ircServer.c_str(), ircPort, 0, nickname.c_str(), userDesc.c_str(), userDesc.c_str())) {
			threads::Lock lock(irc.mutex);
			irc._messageall("", "", IRC::MT_Disconnect);
			irc.error = irc_strerror(err);
			irc_destroy_session(irc.session);
			irc.session = nullptr;
			net::clear();
			irc.connected = false;
			irc.running = false;
			return 0;
		}

		irc_run(irc.session);
		++tries;
	}
	while(irc.shouldConnect && tries < 20);

	irc.connected = false;
	irc.running = false;

	return 0;
}

static IRC manager;
static void _event_connect(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	manager.connected = true;
}

static void _event_join(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 1)
		manager._onjoin(params[0], origin);
	//irc_cmd_topic(session, params[0], nullptr);
	//irc_cmd_names(session, params[0]);
}

static void _event_part(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2)
		manager._onpart(params[0], origin, params[1]);
	else if(count >= 1)
		manager._onpart(params[0], origin, nullptr);
}

static void _event_quit(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 1)
		manager._onquit(origin, params[0]);
	else
		manager._onquit(origin, nullptr);
}

static void _event_nick(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 1)
		manager._nickchange(origin, params[0]);
}

static void _event_channel(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2)
		manager._message(params[0], origin, params[1]);
}

static void _event_topic(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2)
		manager._ontopic(params[0], origin, params[1]);
	else if(count >= 1)
		manager._ontopic(params[0], origin, nullptr);
}

static void _event_privmsg(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2)
		manager._onprivmsg(origin, params[1]);
	else if(count >= 1)
		manager._onprivmsg(origin, nullptr);
}

static void _event_action(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2)
		manager._onaction(params[0], origin, params[1]);
}

static void _event_mode(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 3) {
		std::string msg = params[1];
		msg += " ";
		msg += params[2];

		manager._message(params[0], origin, msg.c_str(), IRC::MT_Mode);
		manager._getusers(params[0]);
	}
	else if(count >= 2) {
		manager._message(params[0], origin, params[1], IRC::MT_Mode);
		manager._getusers(params[0]);
	}
}

static void _event_umode(irc_session_t* session, const char* event, const char* origin, const char** params, unsigned int count) {
	if(count >= 2) {
		manager._message(params[0], origin, params[1], IRC::MT_UMode);
		manager._getusers(params[0]);
	}
}

static void _event_numeric(irc_session_t* session, unsigned event, const char* origin, const char** params, unsigned int count) {
	//printf("numeric %d (%d args)\n", event, count);
	//for(unsigned i = 0; i < count; ++i)
	//	printf(" %d: %s\n", i, params[i]);

	switch(event) {
		case LIBIRC_RFC_ERR_NICKNAMEINUSE:
		case LIBIRC_RFC_ERR_NICKCOLLISION: {
			threads::Lock lock(manager.mutex);
			manager.currentNickname += toString(rand() % 10000);
			if (irc_is_connected(manager.session))
				irc_cmd_nick(manager.session, manager.currentNickname.c_str());
		} break;
		case LIBIRC_RFC_RPL_TOPIC:
			if(count >= 3)
				manager._topic_is(params[1], params[2]);
		break;
		case LIBIRC_RFC_RPL_NAMREPLY: {
			if(count >= 4) {
				std::string names = params[3];

				size_t start = 0;
				size_t pos = names.find(' ');
				while(pos != std::string::npos) {
					std::string name = names.substr(start, pos-start);
					manager._name(params[2], name);

					start = pos+1;
					if(start >= names.size())
						break;
					pos = names.find(' ', start);
				}

				if(start < names.size()) {
					std::string name = names.substr(start, names.size()-start);
					manager._name(params[2], name);
				}
			}
		} break;
		case LIBIRC_RFC_RPL_ENDOFNAMES: {
			manager._poke(params[1]);
		} break;
	}
}

void RegisterIRCBinds() {
	EnumBind mtype("IRCMessageType");
	mtype["IMT_Message"] = IRC::MT_Message;
	mtype["IMT_Join"] = IRC::MT_Join;
	mtype["IMT_Part"] = IRC::MT_Part;
	mtype["IMT_Quit"] = IRC::MT_Quit;
	mtype["IMT_Action"] = IRC::MT_Action;
	mtype["IMT_Nick"] = IRC::MT_Nick;
	mtype["IMT_Kick"] = IRC::MT_Kick;
	mtype["IMT_Topic"] = IRC::MT_Topic;
	mtype["IMT_TopicIs"] = IRC::MT_TopicIs;
	mtype["IMT_Mode"] = IRC::MT_Mode;
	mtype["IMT_UMode"] = IRC::MT_UMode;
	mtype["IMT_Disconnect"] = IRC::MT_Disconnect;

	ClassBind chan("IRCChannel", asOBJ_REF);
	chan.setReferenceFuncs(asMETHOD(IRC::Channel, grab), asMETHOD(IRC::Channel, drop));
	chan.addMember("Mutex mutex", offsetof(IRC::Channel, mutex));
	chan.addMember("string name", offsetof(IRC::Channel, name));
	chan.addMember("bool isPM", offsetof(IRC::Channel, isPM));
	chan.addMember("bool active", offsetof(IRC::Channel, active));
	chan.addMember("bool closed", offsetof(IRC::Channel, closed));
	chan.addMember("bool highlight", offsetof(IRC::Channel, highlight));
	chan.addMember("uint messageId", offsetof(IRC::Channel, messageId));
	chan.addMember("uint handledId", offsetof(IRC::Channel, handledId));

	chan.addMethod("string get_topic()", asMETHOD(IRC::Channel, getTopic));
	chan.addMethod("uint get_messageCount()", asMETHOD(IRC::Channel, getMessageCount));
	chan.addMethod("string get_messages(uint index)", asMETHOD(IRC::Channel, getMessage));
	chan.addMethod("string get_message_senders(uint index)", asMETHOD(IRC::Channel, getSender));
	chan.addMethod("uint8 get_message_sender_types(uint index)", asMETHOD(IRC::Channel, getSenderType));
	chan.addMethod("uint get_message_ids(uint index)", asMETHOD(IRC::Channel, getMessageId));
	chan.addMethod("IRCMessageType get_message_types(uint index)", asMETHOD(IRC::Channel, getMessageType));
	chan.addMethod("void getUsers(array<string>& data)", asMETHOD(IRC::Channel, getUsers));
	chan.addMethod("uint getUserCount()", asMETHOD(IRC::Channel, getUserCount));

	ClassBind irc("IRCManager", asOBJ_REF | asOBJ_NOCOUNT);
	irc.addMember("Mutex mutex", offsetof(IRC, mutex));
	irc.addMember("bool running", offsetof(IRC, running));
	irc.addMember("bool connected", offsetof(IRC, connected));
	irc.addMember("bool highlight", offsetof(IRC, highlight));
	irc.addMember("string error", offsetof(IRC, error));
	irc.addMember("recti display", offsetof(IRC, display));

	irc.addMethod("void connect()", asMETHOD(IRC, connect));
	irc.addMethod("void disconnect()", asMETHOD(IRC, disconnect));
	irc.addMethod("bool part(IRCChannel& channel)", asMETHOD(IRC, part));
	irc.addMethod("void close(IRCChannel& channel)", asMETHOD(IRC, close));
	irc.addMethod("bool send(IRCChannel& channel, const string&in message)", asMETHOD(IRC, send));
	irc.addMethod("void kick(IRCChannel& channel, const string&in user, const string&in message)", asMETHOD(IRC, send));
	irc.addMethod("void setTopic(IRCChannel& channel, const string&in topic)", asMETHOD(IRC, setTopic));
	irc.addMethod("IRCChannel@ join(const string&in channel)", asMETHOD(IRC, join));
	irc.addMethod("IRCChannel@ privmsg(const string&in user)", asMETHOD(IRC, privmsg));

	irc.addMethod("string get_nickname()", asMETHOD(IRC, getNickname));
	irc.addMethod("void set_nickname(const string&in name)", asMETHOD(IRC, setNickname));

	irc.addMethod("uint get_channelCount()", asMETHOD(IRC, getChannelCount));
	irc.addMethod("IRCChannel@ get_channels(uint index)", asMETHOD(IRC, getChannel));
	irc.addMethod("IRCChannel@ getChannel(const string&in name)", asMETHOD(IRC, getChannelByName));

	bindGlobal("IRCManager IRC", &manager);
	bindGlobal("string IRC_HOSTNAME", &userDesc);
}

};
