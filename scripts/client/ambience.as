const double DROPOFF_FACTOR = 64.0;
const double DROPOFF_FACTOR_SQ = DROPOFF_FACTOR * DROPOFF_FACTOR;

final class SoundEntry {
	vec3d pos;
	double scale;
};

final class AmbienceGroup {
	map entries;
	SoundEntry@ active;
	const SoundSource@ source;
	Sound@ sound;
	double volume = 0;
	
	AmbienceGroup(const SoundSource& soundSource) {
		@source = soundSource;
	}
	
	void addEntry(int id, const vec3d& pos, double scale) {
		SoundEntry entry;
		entry.pos = pos;
		entry.scale = scale;
		entries.set(id, @entry);
	}
	
	void deleteEntry(int id) {
		entries.delete(id);
	}
	
	SoundEntry@ findNearest(const vec3d& to) {
		SoundEntry@ nearest;
		double nearDist = 0;
	
		map_iterator i = entries.iterator();
		SoundEntry@ entry;
		while(i.iterate(@entry)) {
			double d = to.distanceToSQ(entry.pos);
			if(d < entry.scale * entry.scale * DROPOFF_FACTOR_SQ && (nearest is null || d < nearDist)) {
				@nearest = entry;
				nearDist = d;
			}
		}
		
		return nearest;
	}
	
	void tick(double time, const vec3d& pos) {
		auto@ entry = findNearest(pos);
		if(entry !is active) {
			if(active !is null && sound !is null) {
				if(volume > 0) {
					volume = max(volume - time, 0.0);
					sound.volume = volume * sqrt(active.scale);
				}
				else {
					sound.pause();
					@active = null;
				}
			}
			else {
				@active = entry;
			}
		}
		else if(active !is null) {
			if(sound is null) {
				@sound = source.play(entry.pos, loop=true, pause=true, priority=true);
				if(sound !is null) {
					sound.minDistance = entry.scale;
					sound.maxDistance = entry.scale * DROPOFF_FACTOR;
					sound.volume = 0;
					sound.resume();
					volume = 0;
				}
			}
			else if(volume < 1.0) {
				if(volume == 0.0) {
					sound.position = entry.pos;
					sound.minDistance = entry.scale;
					sound.maxDistance = entry.scale * DROPOFF_FACTOR;
					sound.resume();
				}
				volume = min(1.0, volume+time);
				sound.volume = volume * sqrt(entry.scale);
			}
		}
	}
	
	void clear() {
		if(sound !is null)
			sound.stop();
		entries.deleteAll();
	}
};

Mutex mtx;
dictionary ambientSounds;

void addAmbientSource(string sound, int id, vec3d pos, double scale) {
	Lock lck(mtx);
	AmbienceGroup@ group;
	if(!ambientSounds.get(sound, @group)) {
		const auto@ source = getSound(sound);
		if(source is null)
			return;
		@group = AmbienceGroup(source);
		ambientSounds.set(sound, @group);
	}
	
	group.addEntry(id, pos, scale);
}

void removeAmbientSource(int id) {
	Lock lck(mtx);
	AmbienceGroup@ group;
	dictionary_iterator i = ambientSounds.iterator();
	while(i.iterate(@group))
		group.deleteEntry(id);
}

void tick(double time) {
	Lock lck(mtx);
	AmbienceGroup@ group;
	dictionary_iterator i = ambientSounds.iterator();
	while(i.iterate(@group))
		group.tick(time, cameraPos);
}

void deinit() {
	Lock lck(mtx);
	AmbienceGroup@ group;
	dictionary_iterator i = ambientSounds.iterator();
	while(i.iterate(@group))
		group.clear();
}
