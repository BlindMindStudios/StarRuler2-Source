from map_systems import IMapHook;
import hooks;
import settings.map_lib;

class BlockEffect : BlockHook, IMapHook {
	//For use in maps
	bool prepare(Argument@& arg, SystemData@ data, SystemDesc@ system, Object@& current) const{
		return true;
	}

	void trigger(SystemData@ data, SystemDesc@ system, Object@& current) const override {
		Argument@ arg;
		if(!prepare(arg) || !prepare(arg, data, system, current))
			return;
		Hook@ hook;
		uint num = 0;
		while(feed(arg, hook, num)) {
			auto@ cur = cast<IMapHook@>(hook);
			if(cur !is null)
				cur.trigger(data, system, current);
		}
	}

	void postTrigger(SystemData@ data, SystemDesc@ system, Object@& current) const override {
		Argument@ arg;
		if(!prepare(arg) || !prepare(arg, data, system, current))
			return;
		Hook@ hook;
		uint num = 0;
		while(feed(arg, hook, num)) {
			auto@ cur = cast<IMapHook@>(hook);
			if(cur !is null)
				cur.postTrigger(data, system, current);
		}
	}
};

class Repeat : BlockEffect {
	Argument count(AT_Range);

	bool prepare(Argument@& dat) const override {
		@dat = Argument();
		if(count.isRange)
			dat.integer = randomi(int(count.decimal), int(count.decimal2));
		else
			dat.integer = int(count.decimal);
		return true;
	}

	bool feed(Argument@& dat, Hook@& hook, uint& num) const override {
		if(num >= inner.length * uint(dat.integer))
			return false;

		@hook = inner[num % inner.length];
		num += 1;
		return true;
	}
};

class RepeatModified : Repeat {
	Argument mod(AT_Range);
	Argument minimum(AT_Integer, "1");
	Argument maximum(AT_Integer, "99999999");

	bool prepare(Argument@& dat) const override {
		@dat = Argument();
		dat.integer = clamp(int(round(count.fromRange() * mod.fromRange())), minimum.integer, maximum.integer);
		return true;
	}
};

class RepeatChance : BlockEffect {
	RepeatChance() {
		argument("Chance", AT_Range);
		argument("Repeat Modifier", AT_Range, "1.0");
	}

	bool prepare(Argument@& dat) const override {
		@dat = Argument();
		dat.decimal = arguments[0].fromRange();
		dat.decimal2 = arguments[1].fromRange();
		return true;
	}

	bool feed(Argument@& dat, Hook@& hook, uint& num) const override {
		uint index = num % inner.length;
		if(index == 0) {
			uint repeats = num / inner.length;
			double chance = dat.decimal * pow(dat.decimal2, repeats);
			if(randomd() > chance)
				return false;
		}

		@hook = inner[index];
		num += 1;
		return true;
	}
};

class RepeatQuality : BlockEffect {
	RepeatQuality() {
		argument("Chance", AT_Range);
		argument("Repeat Modifier", AT_Range, "1.0");
		argument("Quality Step", AT_Range);
	}

	bool prepare(Argument@& dat) const override {
		@dat = Argument();
		dat.decimal = arguments[0].fromRange();
		dat.decimal2 = arguments[1].fromRange();
		dat.integer = 0;
		return true;
	}

	bool prepare(Argument@& dat, SystemData@ data, SystemDesc@ system, Object@& current) const{
		dat.integer = floor(double(data.quality) / arguments[2].fromRange());
		return true;
	}

	bool feed(Argument@& dat, Hook@& hook, uint& num) const override {
		uint index = num % inner.length;
		if(index == 0) {
			uint repeats = num / inner.length;
			double chance = dat.decimal * pow(dat.decimal2, repeats);

			bool gotten = false;
			do {
				if(randomd() <= chance) {
					gotten = true;
					break;
				}
				else {
					dat.integer -= 1;
				}
			}
			while(dat.integer >= 0);
			if(!gotten)
				return false;
		}

		@hook = inner[index];
		num += 1;
		return true;
	}
};
