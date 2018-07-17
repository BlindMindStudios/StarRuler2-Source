#include <network/connection.h>
#include <network/sequence.h>
#include <stdlib.h>
#include <algorithm>

const unsigned UDP_Header_IPv4 = 28;
const unsigned UDP_Header_IPv6 = 48;

namespace net {

Connection::Connection(Transport& trans, Address addr)
	: references(1), nextOutgoingID(1), nextAck(1), nextSequenceID(1), nextReliablePeriod(0), 
		pingPongWait(rand() % NET_PING_INTERVAL), pingSent(false),
		transport(trans), active(true), address(addr), id(-1), inBytes(0), outBytes(0), availBytes(0),
		windowBytes(500000), windowLength(1.0), windowUpdate(1.0), windowUsed(0)
{
	transport.grab();
	time_now(lastMessageReceived);
	time_now(lastProcessTime);
}

Connection::~Connection() {
	transport.drop();
}

void Connection::grab() const {
	++references;
}

void Connection::drop() const {
	if(--references == 0)
		delete this;
}

void Connection::queueReliable(Message* msg, bool immediate) {
	threads::Lock lock(reliableMutex);
	if(immediate)
		queuedReliable.push_front(msg);
	else
		queuedReliable.push_back(msg);
}

OutSequence* Connection::sequence() {
	threads::Lock lock(sequenceMutex);

	OutSequence* ws = new OutSequence(*this);
	ws->id = nextSequenceID++;
	outSequences[ws->id] = ws;

	return ws;
}

void Connection::queueSeqAck(unsigned short sequenceID, unsigned short messageID) {
	threads::Lock lock(ackMutex);
	SeqAck ack = {sequenceID, messageID};
	queuedSeqAcks.push_back(ack);
}

void Connection::queue(Message* msg) {
	threads::Lock lock(msgQueueLock);
#ifdef _DEBUG
	if(msg->getFlag(MF_Reliable) && !msg->hasID())
		return;
#endif
	queuedMessages.push_back(msg);
}

Connection& Connection::operator<<(Message& msg) {
	if(msg.getFlag(MF_Reliable))
		queueReliable(new Message(msg));
	else
		queue(new Message(msg));
	return *this;
}

bool Connection::split(Message& msg) {
	if(msg.size() <= NET_FRAGMENT_LIMIT)
		return false;
	//Send the message in fragments
	unsigned fragId = nextFragmentID++;

	msize_t startAt = 0;
	msize_t size = msg.size();
	unsigned short index = 0;

	msize_t maxPerFrag = (NET_FRAGMENT_LIMIT - NET_FRAGMENT_OVERHEAD);

	msize_t frags = (size + maxPerFrag - 1) / maxPerFrag;
	msize_t bytesPerFrag = (size / frags) + (frags - 1);
	if(bytesPerFrag > maxPerFrag)
		bytesPerFrag = maxPerFrag;

	while(startAt < size) {
		msize_t fragSize = size - startAt;
		bool lastFragment = true;
		if(fragSize > bytesPerFrag) {
			fragSize = bytesPerFrag;
			lastFragment = false;
		}

		Message* fragment = new Message(lastFragment ? MT_LastFragment : MT_Fragment, msg.getFlag(MF_Reliable) ? MF_Reliable : 0);

		*fragment << fragId;
		*fragment << index;

		msg.copyTo(*fragment, startAt, startAt+fragSize);
			
		{
			threads::Lock lock(reliableMutex);
			queueReliable(fragment);
		}

		startAt += fragSize;
		index += 1;
	}

	//Fragments are reliable if the message is, so the original message no longer needs acked
	if(msg.getFlag(MF_Sequenced)) {
		threads::Lock lock(sequenceMutex);
		auto seq = outSequences.find(msg.getSeqID());
		if(seq != outSequences.end())
			seq->second->handleAck(msg.getID());
	}
	else if(msg.getFlag(MF_Reliable)) {
		handleAck(msg.getID());
	}

	return true;
}

bool Connection::send(Message& msg, bool isResend) {
	if((isResend || !msg.getFlag(MF_Reliable)) && availBytes < 0)
		return false;

	if(msg.getFlag(MF_Reliable) && !msg.hasID()) {
		threads::Lock lock(reliableMutex);
		queueReliable(new Message(msg));
		return false;
	}

	auto attemptSend = [this](int size) -> bool {
		if(availBytes < 0)
			return false;
		availBytes -= size;
		return true;
	};

	if(attemptSend(UDP_Header_IPv4 + msg.size())) {
		outBytes += UDP_Header_IPv4 + msg.size();
		transport.send(msg, address);
		return true;
	}

	return false;
}

void Connection::process(MessageHandler& handler) {
	time now;
	time_now(now);

	double time;
	{
		auto ms = time_diff(lastProcessTime, now);
		if(ms > 0) {
			time_now(lastProcessTime);
			availBytes = std::min(availBytes + (int)((double)transport.rate * (double)ms / 1000.0), (int)transport.rate / 10);
		}

		time = (double)ms / 1000.0;
	}

	//Check if our transport is still active
	if(!transport.active) {
		active = false;
		return;
	}

	//Check if the last received message was long ago
	if(time_diff(lastMessageReceived, now) > NET_PING_INTERVAL) {
		if(pingSent) {
			if(time_diff(firstPingSent, now) > NET_PING_TIMEOUT) {
				//Disconnect if we don't hear any messages for a while
				if(time_diff(lastMessageReceived, now) > NET_PING_TIMEOUT) {
					active = false;
					return;
				}
			}
			else if(time_diff(lastPingSent, now) > pingPongWait) {
				sendPing();
			}
		}
		else {
			sendPing();
		}
	}

	//Network window
	//1. Check for out of date messages (messages sent at least windowLength seconds ago)
	//   If any packet was out of date, reduce window bytes by a %
	//   If no packets are behind, and our window was full, expand the window by a fixed amount.
	//2. Transmit any queued acks as bandwidth is available.
	//3. Append and transmit any packet that fits in our network window.
	//4. Retransmit each front packet we can, moving it to the end, based on estimated available bandwidth.

	windowUpdate -= time;
	if(windowUpdate <= 0.0) { //Check for out of date packets
		windowUpdate = 1.0;
		bool congested = false;

		unsigned packets = 0, late = 0;
		threads::Lock lock(windowMutex);
		uint64_t winLen_ms = (uint64_t)(windowLength * 1000.0);
		for(auto i = window.begin(), end = window.end(); i != end; ++i) {
			auto& packet = *i;
			if(!packet.msg->getFlag(MF_Reliable))
				continue;

			++packets;

			auto ms = time_diff(packet.added, now);
			if(ms > winLen_ms) {
				++late;
				packet.added = now;
			}
		}

		if((double)late / (double)(packets + 8) > 0.2)
			congested = true;

		//Scale our window based on the response
		if(congested) {
			windowBytes = std::max<size_t>(1000, (size_t)(double(windowBytes) * 0.8));
			windowLength = std::min<double>(windowLength + 0.1, 3.0);
		}
		else {
			if(!queuedMessages.empty()) {
				windowBytes += 50000;
				windowLength = std::max<double>(windowLength * 0.9, 0.5);
			}
		}

		transport.rate = (int)(1.1 * (double)std::max(windowBytes, windowUsed) / windowLength);
	}

	//Send any acks queued since the last process tick
	if(availBytes > 0) {
		std::vector<Message*> acks;

		auto transmitAck = [&acks](Message& msg) {
			acks.push_back(new Message(msg));
		};

		//Batch acks into small groups and duplicate the message to improve the chances the acks are received
		if(!queuedAcks.empty()) {
			std::vector<unsigned short> ackIDs;

			threads::Lock lock(ackMutex);
			auto it = queuedAcks.begin(), end = queuedAcks.end();
			unsigned readied = 0;
		
			Message ack(MT_Ack);
			for(; it != end; ++it) {
				ack << *it;
				ackIDs.push_back(*it);
				++readied;
			
				if(readied >= 20) {
					transmitAck(ack);
					readied = 0;
					ack.reset();
				}
			}

			if(readied != 0)
				transmitAck(ack);

			queuedAcks.clear();
		}

		if(!queuedSeqAcks.empty()) {
			std::vector<unsigned> ackIndexes;
			unsigned readied = 0;

			threads::Lock lock(ackMutex);
		
			Message ack(MT_SeqAck);
			for(unsigned i = 0; i < queuedSeqAcks.size(); ++i) {
				auto& seqAck = queuedSeqAcks[i];
				ack << seqAck.seqID << seqAck.msgID;
				ackIndexes.push_back(i);
				++readied;
			
				if(readied >= 10) {
					transmitAck(ack);
					readied = 0;
					ack.reset();
				}
			}

			if(readied != 0)
				transmitAck(ack);

			queuedSeqAcks.clear();
		}

		if(!acks.empty()) {
			threads::Lock lock(windowMutex);
			for(unsigned i = 0; i < acks.size(); ++i) {
				WindowPacket packet;
				packet.msg = new Message(*acks[i]);
				packet.added = now;
				packet.sent = now;
				time_add(packet.sent, -10000);
				window.push_front(packet);
				windowUsed += packet.msg->size();
			}
			for(unsigned i = 0; i < acks.size(); ++i) {
				WindowPacket packet;
				packet.msg = acks[i];
				packet.added = now;
				packet.sent = now;
				time_add(packet.sent, -10000);
				window.push_front(packet);
				windowUsed += packet.msg->size();
			}
		}
	}

	{ //Ask sequences to be queued
		threads::Lock lock(sequenceMutex);

		//Check for resending outgoing sequenced messages
		{
			auto it = outSequences.begin(), end = outSequences.end();
			while(it != end) {
				OutSequence* seq = it->second;

				if(seq->closed) {
					delete seq;
					it = outSequences.erase(it);
					continue;
				}

				while(Message* msg = seq->getNextMessage()) {
					//Split the message if necessary
					if(!split(*msg))
						queue(msg);
					else
						delete msg;
				}

				++it;
			}
		}

		//Check for requeueing ingoing sequenced messages
		{
			auto it = inSequences.begin(), end = inSequences.end();
			while(it != end) {
				InSequence* seq = it->second;

				if(seq->closed) {
					delete seq;
					it = inSequences.erase(it);
					continue;
				}

				seq->process(handler, now);
				++it;
			}
		}
	}

	{ //Queue reliables
		std::deque<Message*> addQueue;
		{
			threads::Lock lock(reliableMutex);
			while(!queuedReliable.empty() && (unsigned short)(nextOutgoingID - nextAck) <= (unsigned short)0x7D00) {
				auto* msg = queuedReliable.front();
				queuedReliable.pop_front();
				msg->setID(nextOutgoingID++);
				if(!split(*msg))
					addQueue.push_back(msg);
				else
					delete msg;
			}
		}

		if(!addQueue.empty()) {
			threads::Lock lock(msgQueueLock);
			while(!addQueue.empty()) {
				queuedMessages.push_front(addQueue.front());
				addQueue.pop_front();
			}
		}
	}

	{ //If we have available bytes in our window, queue packets. We also transmit them if we have available bytes.
		std::deque<WindowPacket> addQueue;
		if(!queuedMessages.empty()) {
			threads::Lock lock(msgQueueLock);
			size_t addedBytes = 0;
			while(windowUsed + addedBytes < windowBytes && !queuedMessages.empty()) {
				WindowPacket packet;
				packet.added = now;
				packet.sent = now;
				time_add(packet.sent, -10000);
				packet.msg = queuedMessages.front();
				queuedMessages.pop_front();

				addQueue.push_back(packet);
				addedBytes += packet.msg->size();
			}
		}
		
		if(!addQueue.empty()) {
			threads::Lock lock(windowMutex);
			while(!addQueue.empty()) {
				window.push_back(addQueue.front());
				windowUsed += window.back().msg->size();
				addQueue.pop_front();
			}
		}
	}

	//If we have available transmit bytes, resend anything in the window, cycling packets
	if(!window.empty()) {
		threads::Lock lock(windowMutex);
		unsigned count = window.size();
		while(availBytes > 0 && count > 0) {
			--count;

			WindowPacket packet = window.front();
			window.pop_front();

			if(time_diff(packet.sent, now) > (unsigned)(windowLength * 0.2 * 1000.0)) {
				send(*packet.msg, false);
				packet.sent = now;
			}
			
			if(packet.msg->getFlag(MF_Reliable)) {
				window.push_back(packet);
			}
			else {
				windowUsed -= packet.msg->size();
				delete packet.msg;
			}
		}
	}
}

bool Connection::shouldHandleID(unsigned short id) {
	//Track the last ~32,000 messages we've handled, and remove very old ones as we reach new ids
	threads::Lock lock(reliableMutex);
	auto old = handledMessages.find(id - 0x8000);
	if(old != handledMessages.end())
		handledMessages.erase(old);

	if(handledMessages.find(id) != handledMessages.end())
		return false;

	handledMessages.insert(id);
	return true;
}

void Connection::sendPing() {
	//Send a ping message
	Message msg(MT_Ping);
	*this << msg;

	time_now(lastPingSent);
	if(!pingSent)
		firstPingSent = lastPingSent;
	pingSent = true;
	pingPongWait = rand() % NET_PING_INTERVAL;
}

void Connection::handleAck(unsigned short id) {
	threads::Lock lock(ackMutex);
	if(id == nextAck) {
		unorderedAcks.erase(nextAck);
		++nextAck;

		while(unorderedAcks.find(nextAck) != unorderedAcks.end())
			unorderedAcks.erase(nextAck++);
	}
	else if((unsigned short)(id - nextAck) < (unsigned short)0x8000) {
		unorderedAcks.insert(id);
	}
}

bool Connection::preHandle(MessageHandler& handler, Message* msg) {
	time_now(lastMessageReceived);

	inBytes += UDP_Header_IPv4 + msg->size();

	switch(msg->getType()) {
		case MT_Ack: {
			//Remove the acked message from the queue
			std::vector<unsigned short> ids;
			{
				threads::Lock lock(windowMutex);

				while(msg->canRead<unsigned short>()) {
					unsigned short id;
					*msg >> id;

					ids.push_back(id);

					for(auto i = window.begin(), end = window.end(); i != end; ++i) {
						auto* msg = i->msg;
						if(msg->getFlag(MF_Reliable) && !msg->getFlag(MF_Sequenced) && msg->getID() == id) {
							windowUsed -= msg->size();
							delete msg;
							window.erase(i);
							break;
						}
					}
				}
			}

			if(!ids.empty()) {
				threads::Lock lock(ackMutex);
				for(unsigned i = 0; i < ids.size(); ++i) {
					unsigned short id = ids[i];
					if(id == nextAck) {
						unorderedAcks.erase(id);
						++nextAck;

						while(unorderedAcks.find(nextAck) != unorderedAcks.end())
							unorderedAcks.erase(nextAck++);
					}
					else if((unsigned short)(id - nextAck) < (unsigned short)0x8000) {
						unorderedAcks.insert(id);
					}
				}
			}
		} return false;
		case MT_Ping: {
			Message pong(MT_Pong);
			*this << pong;
		} return true;
		case MT_Pong: {
			pingSent = false;

			ping = (unsigned)time_diff(lastPingSent, lastMessageReceived);
		} return true;
		case MT_SeqAck: {
			std::unordered_set<unsigned> sacks;

			{
				threads::Lock lock(sequenceMutex);
				while(msg->canRead<unsigned short>()) {
					unsigned short seqID, id;
					*msg >> seqID;

					if(!msg->canRead<unsigned short>())
						break;

					*msg >> id;

					sacks.insert((unsigned)seqID << 16 | (unsigned)id);

					auto it = outSequences.find(seqID);
					if(it != outSequences.end())
						it->second->handleAck(id);
				}
			}

			threads::Lock lock(windowMutex);
			for(auto i = window.begin(); i != window.end();) {
				auto* msg = i->msg;
				if(msg->getFlag(MF_Reliable) && msg->getFlag(MF_Sequenced)) {
					if(sacks.find((unsigned)msg->getSeqID() << 16 | (unsigned)msg->getID()) != sacks.end()) {
						windowUsed -= msg->size();
						delete msg;
						i = window.erase(i);
						continue;
					}
				}

				++i;
			}
		} return false;
		case MT_LastFragment:
		case MT_Fragment: {
			{
				threads::Lock lock(ackMutex);
				queuedAcks.insert(msg->getID());
			}

			if(shouldHandleID(msg->getID()))
				handleFragment(handler, msg);
		} return false;
	}

	if(msg->getFlag(MF_Sequenced)) {
		threads::Lock lock(sequenceMutex);
		InSequence* seq = 0;
		unsigned short seqID = msg->getSeqID();

		auto it = inSequences.find(seqID);
		if(it == inSequences.end()) {
			seq = new InSequence(*this, seqID);
			inSequences[seqID] = seq;
		}
		else {
			seq = it->second;
		}

		if(!seq->preHandle(handler, msg))
			return false;
	}
	else if(msg->getFlag(MF_Reliable)) {
		//Queue acks for reliable messages
		{
			threads::Lock lock(ackMutex);
			queuedAcks.insert(msg->getID());
		}

		//Check if we've already handled this message
		if(!shouldHandleID(msg->getID()))
			return false;
	}

	return true;
}

void Connection::handleFragment(MessageHandler& handler, Message* msg) {
	unsigned id;
	unsigned short fragIndex;
	*msg >> id;
	*msg >> fragIndex;

	{
		threads::Lock lock(fragmentMutex);
		auto it = waitingFragments.find(id);

		//Record this fragmented message
		Fragment* frag;
		if(it != waitingFragments.end()) {
			frag = it->second;
		}
		else {
			frag = new Fragment();
			frag->fragmentCount = 0;
			waitingFragments[id] = frag;
		}

		time_now(frag->lastActivity);

		//If we received the last fragment, we know
		//how many fragments we're waiting for.
		if(msg->getType() == MT_LastFragment)
			frag->fragmentCount = fragIndex + 1;

		//Save the fragment
		if(fragIndex >= frag->received.size()) {
			size_t prev = frag->received.size();
			frag->received.resize(fragIndex + 1);
			for(size_t i = prev; i < fragIndex; ++i)
				frag->received[i] = 0;
		}

		frag->received[fragIndex] = new Message(*msg);

		//Check if we have every fragment
		if(frag->fragmentCount > 0) {
			bool completed = true;
			for(size_t i = 0, cnt = frag->received.size(); i < cnt; ++i) {
				if(!frag->received[i]) {
					completed = false;
					break;
				}
			}

			if(completed) {
				//Reconstruct the message
				char* pBytes; msize_t size;
				frag->received[0]->getAsPacket(pBytes, size);

				Message* recMsg = new Message((uint8_t*)(pBytes+NET_FRAGMENT_OVERHEAD), size-NET_FRAGMENT_OVERHEAD);
				for(size_t i = 1, cnt = frag->received.size(); i < cnt; ++i)
					frag->received[i]->copyTo(*recMsg, NET_FRAGMENT_OVERHEAD);

				//printf("Fragment reconstructed message %d:%d\n", recMsg->getSeqID(), recMsg->getID());

				//Send reconstructed message into handler
				handler.queueMessage(&transport, address, recMsg);

				//Clean up the stored fragment
				if(it == waitingFragments.end())
					it = waitingFragments.find(id);
				waitingFragments.erase(it);
				for(size_t i = 0, cnt = frag->received.size(); i < cnt; ++i)
					delete frag->received[i];
				delete frag;
			}
		}
	}
}

void Connection::postHandle(MessageHandler& handler, Message* msg) {
	if(msg->getFlag(MF_Sequenced)) {
		threads::Lock lock(sequenceMutex);
		auto it = inSequences.find(msg->getSeqID());
		if(it != inSequences.end())
			it->second->postHandle(handler, msg);
	}
}

void Connection::getTraffic(unsigned& in_bytes, unsigned& out_bytes, unsigned& queuedPackets) {
	in_bytes = inBytes;
	inBytes = 0;

	out_bytes = outBytes;
	outBytes = 0;

	queuedPackets = queuedReliable.size() + queuedAcks.size() + queuedSeqAcks.size() + queuedMessages.size();

	threads::Lock lock(sequenceMutex);
	for(auto i = outSequences.begin(), end = outSequences.end(); i != end; ++i)
		queuedPackets += i->second->queuedMessages.size();
}
	
};
