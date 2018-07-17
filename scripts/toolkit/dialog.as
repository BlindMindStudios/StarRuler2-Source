import elements.IGuiElement;
import dialogs.IDialog;

IDialog@[] dialogs;

//Add and remove dialogs from the global
//list accordingly
void addDialog(IDialog@ dlg) {
	dlg.updatePosition();
	dialogs.insertLast(dlg);
	dlg.focus();
}

void closeDialog(IDialog@ dlg) {
	int ind = dialogs.find(dlg);
	if(ind >= 0)
		dialogs.removeAt(ind);
	if(!dlg.closed)
		dlg.close();
}

//An element can close all dialogs bound to it
void closeDialogs(IGuiElement@ elem) {
	uint cnt = dialogs.length(), offset = 0;
	for(uint i = 0; i < cnt; ++i) {
		if(dialogs[i].bound is elem)
			++offset;
		else if(offset > 0)
			@dialogs[i - offset] = dialogs[i];
	}
	if(offset > 0)
		dialogs.resize(cnt - offset);
}

//Tick function checks for closed dialogs to clean
//up every once in a while
double timer = 0.0;
void tick(double time) {
	if(timer >= 1.0) {
		timer = 0.0;

		uint cnt = dialogs.length(), offset = 0;
		for(uint i = 0; i < cnt; ++i) {
			if(dialogs[i].closed)
				++offset;
			else if(offset > 0)
				@dialogs[i - offset] = dialogs[i];
		}
		if(offset > 0)
			dialogs.resize(cnt - offset);
	}
	else
		timer += time;
}
