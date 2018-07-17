final class ConVar : ConsoleCommand {
	string name;
	double value;
	
	ConVar(const string& Name, double initial = 0) {
		name = Name;
		value = initial;
		addConsoleCommand(Name, this);
	}
	
	void execute(const string& args) {
		if(args.length != 0)
			value = toDouble(args);
		print(name + " = " + value);
	}
};
