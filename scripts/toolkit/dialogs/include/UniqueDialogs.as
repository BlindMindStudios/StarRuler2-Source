//Dialogs can be given a unique id on
//a per-module basis, so duplicate dialogs
//are not allowed.

Dialog@[] uniqueDialogs;

void addDialog(uint num, Dialog@ dlg) {
	if(num >= uniqueDialogs.length)
		uniqueDialogs.length = num + 1;
	if(uniqueDialogs[num] !is null)
		closeDialog(uniqueDialogs[num]);
	@uniqueDialogs[num] = dlg;
	addDialog(dlg);
}

bool focusDialog(uint num) {
	if(uniqueDialogs.length <= num)
		return false;
	Dialog@ dlg = uniqueDialogs[num];
	if(dlg is null || dlg.closed)
		return false;
	dlg.focus();
	return true;
}

Dialog@ getUniqueDialog(uint num) {
	if(uniqueDialogs.length <= num)
		return null;
	Dialog@ dlg = uniqueDialogs[num];
	if(dlg is null || dlg.closed)
		return null;
	return dlg;
}
