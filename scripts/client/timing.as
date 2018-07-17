const double[] SPEED_STEPS = {0.1, 0.2, 0.5, 0.8, 1.0, 1.2, 1.5, 2.0, 5.0, 10.0};

bool PAUSED = false;
double PREV_SPEED = 1.0;

uint closest_step(double speed) {
	double diff = INFINITY;
	uint index = 0;
	for(uint i = 0, cnt = SPEED_STEPS.length; i < cnt; ++i) {
		double d = abs(SPEED_STEPS[i] - speed);
		if(d < diff) {
			diff = d;
			index = i;
		}
	}
	return index;
}

void pause(bool pressed = false) {
	if(!pressed) {
		if(PAUSED) {
			PAUSED = false;
			setGameSpeed(PREV_SPEED);
		}
		else {
			PAUSED = true;
			PREV_SPEED = gameSpeed;
			setGameSpeed(0);
		}
	}
}

void speed_default(bool pressed = false) {
	if(!pressed) {
		PAUSED = false;
		setGameSpeed(1.0);
	}
}

void speed_faster(bool pressed = false) {
	if(!pressed) {
		uint index = closest_step(PAUSED ? PREV_SPEED : gameSpeed);
		PAUSED = false;
		double newSpeed = SPEED_STEPS[min(index + 1, SPEED_STEPS.length-1)];
		setGameSpeed(newSpeed);
	}
}

void speed_fastest(bool pressed = false) {
	if(!pressed) {
		PAUSED = false;
		double newSpeed = SPEED_STEPS[SPEED_STEPS.length-1];
		setGameSpeed(newSpeed);
	}
}

void speed_slower(bool pressed = false) {
	if(!pressed) {
		uint index = closest_step(PAUSED ? PREV_SPEED : gameSpeed);
		PAUSED = false;
		double newSpeed = SPEED_STEPS[max(index, 1) - 1];
		setGameSpeed(newSpeed);
	}
}

void speed_slowest(bool pressed = false) {
	if(!pressed) {
		PAUSED = false;
		double newSpeed = SPEED_STEPS[0];
		setGameSpeed(newSpeed);
	}
}

class GameSpeed : ConsoleCommand {
	void execute(const string& args) {
		double value = toDouble(args);
		PAUSED = value == 0;
		if(PAUSED)
			PREV_SPEED = gameSpeed;
		setGameSpeed(value);
	}
};

class Pause : ConsoleCommand {
	void execute(const string& args) {
		pause(false);
	}
};

void init() {
	addConsoleCommand("game_speed", GameSpeed());
	addConsoleCommand("pause", Pause());

	keybinds::Global.addBind(KB_PAUSE, "pause");
	keybinds::Global.addBind(KB_SPEED_SLOWER, "speed_slower");
	keybinds::Global.addBind(KB_SPEED_DEFAULT, "speed_default");
	keybinds::Global.addBind(KB_SPEED_FASTER, "speed_faster");
}
