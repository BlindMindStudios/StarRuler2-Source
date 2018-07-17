const float fadeInTime = 1000.f;
const float fadeOutTime = 3000.f;

//Delay (seconds) to avoid playing music after the track ends
float silenceTime = 0;

//Calculated volume for the music tracks
double musicVolume = 1.0;

class Layer {
	Movement@ movement;
	Sound@ track;
	float currentVolume = 1;
	float volumeGoal = 1;
	float fadeTime = 0;
	
	string name;
	
	Layer(Movement@ moveTrack, const string& file, float Volume = 1.f, bool loop = false) {
		name = file;
		@movement = moveTrack;
		
		//Sounds don't play if the volume is 0
		if(soundVolume <= 0)
			return;
		
		@track = playTrack(file, loop, true);
		currentVolume = Volume;
		volumeGoal = Volume;
		if(track !is null) {
			track.volume = Volume;
		}
		else {
			error("Could not load track " + file);
		}
	}
	
	void volumeFade(float goal, float seconds) {
		volumeGoal = goal;
		fadeTime = seconds;
	}
	
	void stop() {
		if(track !is null)
			track.stop();
		@track = null;
		@movement = null;
	}
	
	void play() {
		if(track !is null)
			track.paused = false;
	}

	void updateVolume() {
		track.volume = currentVolume * musicVolume;
	}
	
	bool update(double time) {
		if(track is null)
			return true;
		
		if(currentVolume != volumeGoal) {
			if(time >= fadeTime) {
				currentVolume = volumeGoal;
				fadeTime = 0;
			}
			else {
				currentVolume += (volumeGoal - currentVolume) * (time/fadeTime);
				fadeTime -= time;
			}
			
			track.volume = currentVolume * musicVolume;
		}
		
		if(track.playing) {
			return false;
		}
		else {
			@track = null;
			return true;
		}
	}
};

array<string> tracks;
int lastTrack = -1;
string get_nextTrack() {
	int nextIndex;
	do {
		nextIndex = randomi(0,tracks.length-1);
	} while(nextIndex == lastTrack && tracks.length != 1);
	
	lastTrack = nextIndex;
	return tracks[nextIndex];
}

Namespace musicVars;
array<Arrangement@> arrangements, queued;
array<Layer@> layers;
StatTracker winTracker(stat::ShipsDestroyed, "ships_destroyed"), lossTracker(stat::ShipsLost, "ships_lost");

class Movement {
	string name;
	string track;
	bool loop = false;
	Formula@ volume;
	
	int volVar, timeVar, playingVar;
	
	Movement(const string& Name) {
		name = Name;
		volVar = musicVars.lookup(name + ".volume", true);
		timeVar = musicVars.lookup(name + ".time", true);
		playingVar = musicVars.lookup(name + ".playing", true);
	}
};

class Arrangement {
	array<Movement@> movements;
	double playOrder = 0;
	string name;
	
	int opCmp(const Arrangement& other) {
		if(playOrder < other.playOrder)
			return -1;
		else if(playOrder == other.playOrder)
			return 0;
		else
			return 1;
	}
	
	void prepare() {
		//Load up all tracks, then start them when they've all been loaded
		for(uint i = 0; i < movements.length; ++i) {
			Movement@ movement = movements[i];
			layers.insertLast(Layer(movement, movement.track, 0, movement.loop));
			musicVars.setConstant(movement.playingVar, 1.0);
		}
		
		for(uint i = 0; i < layers.length; ++i)
			layers[i].play();
	}
};

void init() {
	if(!soundEnabled)
		return;

	//Load arrangements
	ReadFile file(resolve("data/music/orchestra.txt"));
	
	Arrangement@ arrange;
	Movement@ movement;
	
	string key, value;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(key == "Arrangement") {
			@arrange = Arrangement();
			arrange.name = value;
			arrangements.insertLast(arrange);
		}
		else if(arrange !is null) {
			if(key == "Era") {
				if(value == "Industrial")
					arrange.playOrder = randomd(0.75, 1.25);
				else if(value == "Imperial")
					arrange.playOrder = randomd(1.2, 1.5);
				else
					arrange.playOrder = randomd(0.0, 1.0);
			}
			else if(key == "Movement") {
				@movement = Movement(value);
				arrange.movements.insertLast(movement);
			}
			else if(movement !is null) {
				if(key == "Track") {
					movement.track = value;
				}
				else if(key == "Volume") {
					@movement.volume = Formula(value);
				}
				else if(key == "Loop") {
					movement.loop = toBool(value);
				}
			}
		}
	}

	//If we're starting a new-ish game, play the music in a semi-ordered way
	if(gameTime < 30.0 * 60.0) {
		queued = arrangements;
		queued.sortAsc();
		uint remove = min(uint(max(double(queued.length) * gameTime / (30.0 / 60.0), 0.0)), queued.length);
		for(uint i = 0; i < remove; ++i)
			queued.removeAt(0);
	}
	
	if(soundVolume > 0)
		playNewArrangement();
}

Arrangement@ prevArrangement;
void randomize() {
	queued = arrangements;
	for(uint i = 0, cnt = queued.length; i < cnt; ++i) {
		uint o = randomi(i, cnt-1);
		if(o != i) {
			auto@ a = queued[i];
			@queued[i] = queued[o];
			@queued[o] = a;
		}
	}
	
	if(prevArrangement !is null && prevArrangement is queued[0] && queued.length > 1) {
		uint i = randomi(1, queued.length-1);
		auto@ a = queued[0];
		@queued[0] = queued[i];
		@queued[i] = a;
	}
}

void playNewArrangement() {
	if(arrangements.length == 0)
		return;
	else if(arrangements.length == 1) {
		arrangements[0].prepare();
		return;
	}
	else if(queued.length == 0) {
		randomize();
	}

	Arrangement@ nextArrangement = queued[0];
	queued.removeAt(0);
	nextArrangement.prepare();
	@prevArrangement = nextArrangement;
}

void deinit() {
	for(uint i = 0; i < layers.length; ++i)
		layers[i].stop();
}

double prevMusicVol = 1.0, prevMasterVol = 1.0, prevSFXVol = 1.0;
void tick(double time) {
	if(!soundEnabled)
		return;

	//Update volume settings
	if(prevMusicVol != settings::dMusicVolume || prevSFXVol != settings::dSFXVolume || prevMasterVol != settings::dMasterVolume) {
		if(settings::dSFXVolume < 0.01)
			musicVolume = settings::dMusicVolume;
		else
			musicVolume = settings::dMusicVolume / settings::dSFXVolume;

		for(int i = layers.length - 1; i >= 0; --i)
			layers[i].updateVolume();
		prevMusicVol = settings::dMusicVolume;
		prevMasterVol = settings::dMasterVolume;
		prevSFXVol = settings::dSFXVolume;
	}
	
	if(layers.length == 0) {
		silenceTime -= time;
	
		if(soundVolume > 0 && silenceTime <= 0.0) {
			playNewArrangement();
			//Silence music for 3 seconds after we attempt to resume the tracks
			// Mostly, this avoids spamming errors when failing to play trakcs for some reason
			silenceTime = 3.0;
		}
		else {
			return;
		}
	}
	
	winTracker.update();
	lossTracker.update();
	
	bool activeTrack = false;

	for(int i = layers.length - 1; i >= 0; --i) {
		Layer@ layer = layers[i];
		if(layer.update(time)) {
			musicVars.setConstant(layer.movement.playingVar, 0.0);
			layers.removeAt(i);
		}
		else {
			if(!layer.movement.loop || layer.currentVolume > 0.01)
				activeTrack = true;
			musicVars.setConstant(layer.movement.playingVar, 1.0);
			musicVars.setConstant(layer.movement.timeVar, double(layer.track.playPosition) / 1000.0);
			musicVars.setConstant(layer.movement.volVar, layer.currentVolume);
			layer.volumeFade(layer.movement.volume.evaluate(musicVars), 2);
		}
	}
	
	if(!activeTrack) {
		for(int i = layers.length - 1; i >= 0; --i)
			layers[i].stop();
		layers.length = 0;
	}
}

class StatTracker {
	stat::EmpireStat stat;
	
	string name;
	int accVar;
	
	uint lastTime = 0;
	int lastVal = 0;
	int accumulation = 0;
	
	float decay = 0.7;
	
	StatTracker(stat::EmpireStat Stat, string Name) {
		stat = Stat;
		name = Name;
		accVar = musicVars.lookup(name + ".acc", true);
	}
	
	void update() {
		if(lastTime + 1 >= (systemTime/1000))
			return;
		lastTime = systemTime/1000;
		
		if(accumulation > 0)
			accumulation = int(ceil(float(accumulation) * decay)) - 1;
		
		int value = 0;
		{
			StatHistory history(playerEmpire, stat);
			if(history.advance(-1))
				value = history.intVal;
		}
		
		//Accumulate events
		accumulation = max(accumulation + (value - lastVal),0);
		
		lastVal = value;
		
		musicVars.setConstant(accVar, double(accumulation));
	}
};
