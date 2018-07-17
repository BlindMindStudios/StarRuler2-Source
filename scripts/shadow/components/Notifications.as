import notifications;

tidy class Notifications : Component_Notifications {
	Mutex mtx;
	array<Notification@> list;

	uint get_notificationCount() const {
		return list.length;
	}

	void getNotifications(uint limit, int beforeId = -1, bool reverse = true) {
		Lock lock(mtx);
		if(reverse) {
			if(beforeId == -1 || beforeId > int(list.length))
				beforeId = list.length;
			if(beforeId == 0)
				return;
			for(int i = beforeId - 1; i >= 0; --i) {
				Notification@ n = list[i];
				yieldNotification(n);
				if(--limit == 0)
					break;
			}
		}
		else {
			int cnt = list.length;
			if(beforeId == -1 || beforeId > cnt)
				beforeId = 0;
			if(beforeId >= cnt)
				return;
			for(int i = beforeId; i < cnt; ++i) {
				Notification@ n = list[i];
				yieldNotification(n);
				if(--limit == 0)
					break;
			}
		}
	}

	void readNotifications(Message& msg, bool delta) {
		Lock lock(mtx);
		uint cnt = 0;
		msg >> cnt;
		if(!delta)
			list.length = 0;
		list.reserve(list.length + cnt);
		for(uint i = 0; i < cnt; ++i) {
			uint type = msg.read_uint();
			Notification@ n = createNotification(type);
			msg >> n;
			list.insertLast(n);
		}
	}
};
