#include <network/sequence.h>

namespace net {

Sequence::Sequence(Connection& conn)
	: ws(conn.sequence()) {
}

Sequence::Sequence(Client& client)
	: ws(0) {
	Connection* conn = client.getConnection();
	if(conn)
		ws = conn->sequence();
}

Sequence::~Sequence() {
	if(ws)
		ws->close();
}

Sequence& Sequence::operator<<(Message& msg) {
	if(ws)
		*ws << msg;
	return *this;
}

unsigned short Sequence::id() {
	if(!ws)
		return -1;
	return ws->id;
}

OutSequence::OutSequence(Connection& connection)
	: conn(connection), id(-1), nextOutgoingID(1), nextAck(1), resendPeriod(0), closed(false) {
}

OutSequence& OutSequence::operator<<(Message& msg) {
	if(!(msg.getFlags() & MF_Sequenced))
		throw "Attempted to write non-sequenced message to sequence.";

	msg.setSeqID(id);
	queue(new Message(msg));
	return *this;
}

void OutSequence::queue(Message* msg) {
	threads::Lock lock(conn.sequenceMutex);
	queuedMessages.push_back(msg);
}

Message* OutSequence::getNextMessage() {
	if(queuedMessages.empty())
		return nullptr;
	if((unsigned short)(nextOutgoingID - nextAck) > (unsigned short)0x7D00)
		return nullptr;

	threads::Lock lock(conn.sequenceMutex);
	auto* msg = queuedMessages.front();
	queuedMessages.pop_front();
	msg->setID(nextOutgoingID++);
	waitingAcks.insert(msg->getID());
	return msg;
}

void OutSequence::handleAck(unsigned short num) {
	auto it = waitingAcks.find(num);
	if(it != waitingAcks.end())
		waitingAcks.erase(it);

	if(nextAck == num)
		++nextAck;

	while(nextAck != nextOutgoingID) {
		if(waitingAcks.find(nextAck) == waitingAcks.end())
			++nextAck;
		else
			break;
	}
}

void OutSequence::close() {
	Message msg(MT_Close_Sequence, MF_Sequenced);
	msg << id;

	*this << msg;
}

InSequence::InSequence(Connection& connection, unsigned short ID)
	: conn(connection), id(ID), closed(false), nextHandleID(1), handlingID(0) {
}

bool InSequence::preHandle(MessageHandler& handler, Message* msg) {
	unsigned short msgID = msg->getID();

	//Acknowledge the message if we haven't done so before
	if(!msg->getFlag(MF_Acknowledged)) {
		conn.queueSeqAck(id, msgID);
	}

	//Check if we should handle this message or not
	//NOTE: (msgID - nextHandleID) will only work with less than ~SHORT_MAX messages in flight
	if((short)(msgID - nextHandleID) < 0|| msgID == handlingID) {
		//This message was already handled previously
		return false;
	}
	else if(msgID == nextHandleID) {
		//Handle close sequence messages here
		if(msg->getType() == MT_Close_Sequence) {
			closed = true;
			return false;
		}

		//Yay, we can immediately handle this
		handlingID = msgID;
		return true;
	}
	else {
		//Boo, we have to queue it
		Message* qmsg = new Message();
		msg->move(*qmsg);
		msg->setFlags(msg->getFlags() | MF_Acknowledged);

		unhandledMessages[msgID] = qmsg;
		return false;
	}
}

void InSequence::postHandle(MessageHandler& handler, Message* msg) {
	nextHandleID++;

	time now;
	time_now(now);

	process(handler, now);
}

void InSequence::process(MessageHandler& handler, time& now) {
	//Check if we can handle a message from the queue
	auto it = unhandledMessages.find(nextHandleID);
	if(it != unhandledMessages.end()) {
		handler.queueMessage(&conn.transport, conn.address, it->second);
		unhandledMessages.erase(it);
	}
}

};
