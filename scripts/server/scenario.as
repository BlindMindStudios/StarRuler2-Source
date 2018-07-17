import dialogue;

Mutex mtx;
array<Dialogue@> dialogue;
Dialogue@ activeDialogue;
uint activeObjective = 0;
bool pageActive = false;
bool dialogueOver = true;

void addDialogue(Dialogue@ diag) {
	dialogueOver = false;
	dialogue.insertLast(diag);
	if(activeDialogue is null) {
		@activeDialogue = diag;
		pageActive = true;
	}
}

bool hasDialogue_cl() {
	return !dialogueOver;
}

void getActiveDialogue_cl() {
	Lock lock(mtx);
	if(activeDialogue !is null && pageActive)
		yield(activeDialogue);
}

void getActiveDialogueObjective_cl() {
	Lock lock(mtx);
	if(activeDialogue !is null && pageActive)
		if(activeObjective < activeDialogue.objectives.length)
			yield(activeDialogue.objectives[activeObjective]);
}

void skipObjective_cl() {
	Lock lock(mtx);
	if(activeDialogue !is null) {
		if(activeObjective < activeDialogue.objectives.length) {
			auto@ obj = activeDialogue.objectives[activeObjective];
			if(!obj.skippable)
				return;
		}
		incObjective();
	}
}

void incObjective() {
	Lock lock(mtx);
	if(activeDialogue !is null) {
		if(activeObjective < activeDialogue.objectives.length) {
			auto@ obj = activeDialogue.objectives[activeObjective];
			if(obj.check !is null)
				obj.check.end();
		}
		activeObjective += 1;
		if(activeObjective >= activeDialogue.objectives.length) {
			activeObjective = 0;
			uint ind = dialogue.find(activeDialogue);
			if(ind < dialogue.length - 1) {
				if(activeDialogue.complete !is null)
					activeDialogue.complete.call();
				@activeDialogue = dialogue[ind+1];
				if(activeDialogue.pass !is null)
					activeDialogue.pass.call();
			}
			else {
				dialogueOver = true;
				@activeDialogue = null;
			}
		}
		if(activeDialogue !is null && activeObjective < activeDialogue.objectives.length) {
			if(activeDialogue.start is null || activeDialogue.start.check()) {
				auto@ obj = activeDialogue.objectives[activeObjective];
				if(obj.check !is null)
					pageActive = obj.check.start();
				else
					pageActive = true;
			}
			else {
				pageActive = false;
			}
		}
	}
}

void saveDialoguePosition(SaveFile& file) {
	uint pos = dialogue.find(activeDialogue);
	file << pos;
	file << activeObjective;
}

uint loadedPos = 0;
void loadDialoguePosition(SaveFile& file) {
	file >> loadedPos;
	file >> activeObjective;
}

bool initialized = false;
void tick(double time) {
	Lock lock(mtx);
	if(!initialized) {
		initialized = true;
		if(isLoadedSave) {
			if(loadedPos < dialogue.length) {
				@activeDialogue = dialogue[loadedPos];
				for(uint i = 0; i < loadedPos; ++i) {
					if(dialogue[i].pass !is null)
						dialogue[i].pass.call();
				}
			}
		}

		if(activeDialogue !is null) {
			if(activeDialogue.pass !is null)
				activeDialogue.pass.call();
			if(activeObjective < activeDialogue.objectives.length) {
				auto@ obj = activeDialogue.objectives[activeObjective];
				if(obj.check !is null)
					obj.check.start();
			}
		}
	}
	if(activeDialogue !is null) {
		if(activeObjective < activeDialogue.objectives.length) {
			if(!pageActive) {
				if(activeDialogue.start is null || activeDialogue.start.check()) {
					auto@ obj = activeDialogue.objectives[activeObjective];
					if(obj.check !is null)
						pageActive = obj.check.start();
					else
						pageActive = true;
				}
				else {
					pageActive = false;
				}
			}
			
			if(pageActive) {
				auto@ obj = activeDialogue.objectives[activeObjective];
				if(obj.check !is null) {
					if(obj.check.check())
						incObjective();
				}
			}
		}
	}
}
