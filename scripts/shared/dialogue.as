#section server
import void addDialogue(Dialogue@ diag) from "scenario";
#section all

class Dialogue : Serializable {
	string title;
	string text;
	string proceedText;
	Sprite icon;
	array<Objective@> objectives;

	//pass is called at the start of the page, even if skipping/loading through it
	DialogueAction@ pass;

	//complete is called when the page is first completed or skipped, not when loading.
	DialogueAction@ complete;
	
	//start is called when the page is trying to appear
	DialogueAction@ start;

	Dialogue() {
		_add();
	}

	Dialogue(const string& title, const string& text, const Sprite& icon = Sprite()) {
		this.title = title;
		this.text = text;
		this.icon = icon;
		_add();
	}

	Dialogue(const string& ident) {
		this.title = localize("#"+ident+"_TITLE");
		this.text = localize("#"+ident+"_TEXT");
		addObjectives(ident);
		_add();
	}

	Dialogue& proceedWith(const string& text) {
		proceedText = localize(text);
		return this;
	}

	Dialogue& onPass(DialogueAction@ act) {
		@pass = act;
		return this;
	}

	Dialogue& onComplete(DialogueAction@ act) {
		@complete = act;
		return this;
	}
	
	Dialogue& onStart(DialogueAction@ act) {
		@start = act;
		return this;
	}
	
	Dialogue& get_newObjective() {
		objectives.insertLast(Objective(empty=true));
		return this;
	}

	Dialogue& addObjectives(const string& ident) {
		for(uint i = 1; true; ++i) {
			string title = localize("#"+ident+"_ACT"+i+"_TITLE");
			if(title[0] == '#')
				break;
			objectives.insertLast(Objective(ident+"_ACT"+i));
		}
		return this;
	}

	Dialogue& checker(uint index, ObjectiveCheck@ check, bool skippable = false) {
		if(index > objectives.length) {
			error("Invalid objective "+index+" on "+title);
			return this;
		}
		@objectives[index-1].check = check;
		objectives[index-1].skippable = skippable;
		return this;
	}

	Dialogue& objectiveKeybind(uint index, uint keybind) {
		if(index > objectives.length) {
			error("Invalid objective "+index+" on "+title);
			return this;
		}
		auto@ obj = objectives[index-1];
		int key = keybinds::Global.getCurrentKey(Keybind(keybind), 0);
		string keyname = getKeyDisplayName(key);
		obj.text = format(obj.text, keyname);
		return this;
	}

	void _add() {
#section server
		addDialogue(this);
#section all
	}

	void write(Message& msg) {
		msg << title << text << proceedText;
		msg << getSpriteDesc(icon);
		msg.writeSmall(objectives.length);
		for(uint i = 0, cnt = objectives.length; i < cnt; ++i)
			msg << objectives[i];
	}

	void read(Message& msg) {
		msg >> title >> text >> proceedText;
		string desc;
		msg >> desc;
		icon = getSprite(desc);
		uint cnt = msg.readSmall();
		objectives.length = cnt;
		for(uint i = 0, cnt = objectives.length; i < cnt; ++i) {
			if(objectives[i] !is null) {
				msg >> objectives[i];
			}
			else {
				Objective obj;
				msg >> obj;
				@objectives[i] = obj;
			}
		}
	}
};

class DialogueAction {
	void call() {
	}
	
	bool check() {
		return true;
	}
};

class GUIAction : DialogueAction {
	string id;

	GUIAction(const string& id) {
		this.id = id;
	}

	void call() {
#section server
		guiDialogueAction(CURRENT_PLAYER, id);
#section all
	}
};

void DialogueRemoteAction(string id) {
	auto@ cls = getClass(id);
	if(cls is null)
		return;
	Lock lck(actMtx);
	actions.insertLast(cast<DialogueAction>(cls.create()));
}

Mutex actMtx;
array<DialogueAction@> actions;
array<GuiObjectiveCheck@> guiCheckers;
array<GUIChecker@> remoteCheckers;
void tick(double time) {
	Lock lck(actMtx);
	for(uint i = 0, cnt = actions.length; i < cnt; ++i)
		actions[i].call();
	actions.length = 0;
#section gui
	for(uint i = 0, cnt = guiCheckers.length; i < cnt; ++i) {
		if(guiCheckers[i].check()) {
			srvObjectiveComplete(guiCheckers[i].id);
			guiCheckers[i].end();
			guiCheckers.removeAt(i);
			--i; --cnt;
		}
	}
#section all
}

void RemoteObjectiveStart(string id, Object@ obj) {
	auto@ cls = getClass(id);
	if(cls is null)
		return;
	Lock lck(actMtx);
	auto@ chk = cast<GuiObjectiveCheck>(cls.create());
	chk.id = id;
	@chk.obj = obj;
	chk.start();
	guiCheckers.insertLast(chk);
}

void RemoteObjectiveEnd(string id) {
	Lock lck(actMtx);
	for(uint i = 0, cnt = guiCheckers.length; i < cnt; ++i) {
		if(guiCheckers[i].id == id) {
			guiCheckers[i].end();
			guiCheckers.removeAt(i);
			--i; --cnt;
		}
	}
}

void RemoteObjectiveComplete(string id) {
	Lock lck(actMtx);
	for(uint i = 0, cnt = remoteCheckers.length; i < cnt; ++i) {
		if(remoteCheckers[i].id == id)
			remoteCheckers[i].completed = true;
	}
}

int nextObjectiveId = 0;
class Objective : Serializable {
	int id;
	string title;
	string text;
	Sprite icon;

	bool skippable = true;
	ObjectiveCheck@ check;

	Objective() {
		id = -1;
	}
	
	Objective(bool empty) {
		if(!empty)
			error("Empty objectives must be empty");
		id = nextObjectiveId++;
	}

	Objective(const string& ident) {
		id = nextObjectiveId++;
		this.title = localize("#"+ident+"_TITLE");
		this.text = localize("#"+ident+"_TEXT");
	}

	void write(Message& msg) {
		msg << id;
		msg << title << text;
		msg << getSpriteDesc(icon);
		msg << skippable;
	}

	void read(Message& msg) {
		msg >> id;
		msg >> title >> text;
		string desc;
		msg >> desc;
		icon = getSprite(desc);
		msg >> skippable;
	}
};

class ObjectiveCheck {
	bool start() {
		return true;
	}

	bool check() {
		return false;
	}

	void end() {
	}
};

class GuiObjectiveCheck : ObjectiveCheck {
	string id;
	Object@ obj;
};

class GUIChecker : ObjectiveCheck {
	string id;
	bool completed;
	Object@ obj;

	GUIChecker(const string& id, Object@ obj = null) {
		this.id = id;
		@this.obj = obj;
	}

#section server
	bool start() {
		guiObjectiveStart(CURRENT_PLAYER, id, obj);
		completed = false;

		{
			Lock lck(actMtx);
			remoteCheckers.insertLast(this);
		}
		
		return true;
	}

	bool check() {
		return completed;
	}

	void end() {
		guiObjectiveEnd(CURRENT_PLAYER, id);

		{
			Lock lck(actMtx);
			remoteCheckers.remove(this);
		}
	}
#section all
};
