string formatEmpireName(Empire@ emp, Empire@ contactCheck = null) {
	if(emp is null)
		return "(n/a)";
	if(emp is defaultEmpire)
		return locale::EMPIRE_UNIVERSE;
	if(contactCheck !is null) {
		if(contactCheck.ContactMask & emp.mask == 0)
			return "[color=#aaa]???[/color]";
	}
	return format("[color=$1]$2[/color]", toString(emp.color), bbescape(emp.name));
}

string formatObject(Object@ obj, bool showOwner = true, bool showIcon = false) {
	if(obj is null)
		return "(n/a)";
	string text;
	if(showIcon)
		text += format("[obj_icon=$1/] ", toString(obj.id));
	if(showOwner) {
		if(obj.isRegion) {
			Empire@ primary = obj.visiblePrimaryEmpire;
			if(primary !is null)
				text += format("[color=$1]$2[/color]", toString(primary.color), formatObjectName(obj));
		}
		else if(obj.owner !is null)
			text += format("[color=$1]$2[/color]", toString(obj.owner.color), formatObjectName(obj));
	}
	else {
		text += formatObjectName(obj);
	}
	return text;
}

string formatGameTime(double time, bool dispSeconds = true) {
	int hours = time / 60.0 / 60.0;
	int minutes = (time - (hours * 60.0 * 60.0)) / 60.0;
	int seconds = (time - (hours * 60.0 * 60.0 + minutes * 60.0));

	string text;
	if(hours < 10) {
		text += "0";
		text += toString(hours);
	}
	else {
		text += toString(hours);
	}
	text += ":";
	if(minutes < 10) {
		text += "0";
		text += toString(minutes);
	}
	else {
		text += toString(minutes);
	}

	if(dispSeconds) {
		text += ":";
		if(seconds < 10) {
			text += "0";
			text += toString(seconds);
		}
		else {
			text += toString(seconds);
		}
	}
	return text;
}

string formatTimeStamp(double time, bool dispSeconds = true) {
	return format("[color=#888]$1[/color]", formatGameTime(time, dispSeconds));
}

string formatInfluenceCost(string option, int influence) {
	return format(locale::OPTION_INFLUENCE_COST, option, toString(influence));
}

string formatMoney(int money, bool colored = false, bool roundUp = true) {
	string text;
	if(money < 0) {
		if(colored)
			text += "[color=#f00]";
		text += "-";
	}

	text += "§";
	int am = abs(money);
	if(am == 0)
		text += "0";
	else if(am < 1000)
		text += toString(am)+"k";
	else if(am < 1000000)
		text += standardize(double(am) / 1000.0, true, true)+"M";
	else
		text += standardize(double(am) / 1000000.0, true, true)+"B";

	if(money < 0 && colored)
		text += "[/color]";
	return text;
}

string formatMoneyChange(int money, bool colored = false) {
	string text;
	if(money < 0) {
		if(colored)
			text += "[color=#f00]";
		text += "-";
	}
	else {
		if(colored)
			text += "[color=#0f0]";
		text += "+";
	}

	text += "§";
	int am = abs(money);
	if(am == 0)
		text += "0";
	else if(am < 1000)
		text += toString(am)+"k";
	else if(am < 1000000)
		text += toString(double(am) / 1000.0, 2)+"M";
	else
		text += toString(double(am) / 1000000.0, 1)+"B";

	if(colored)
		text += "[/color]";
	return text;
}

string formatMoney(int build, int maintain, bool hideZeroMaintenance = true) {
	if(maintain == 0 && hideZeroMaintenance)
		return formatMoney(build);
	return formatMoney(build)+" / "+formatMoney(maintain);
}

string formatTimeRate(double time, double atRate, bool tenthPrecision = false) {
	if(atRate == 0)
		return locale::NEVER;
	return formatTime(time / atRate, tenthPrecision);
}

string formatTime(double time, bool tenthPrecision = false) {
	if(time == INFINITY) {
		return locale::NEVER;
	}
	else if(time <= 0) {
		return "";
	}
	else if(time > 60) {
		int mins = floor(time / 60.0);
		int secs = time % 60;

		if(secs == 0)
			return format(locale::TIME_M, toString(mins));
		else
			return format(locale::TIME_MS, toString(mins), toString(secs));
	}
	else if(tenthPrecision) {
		return format(locale::TIME_S,
				toString(time, time < 10 ? 1 : 0));
	}
	else {
		return format(locale::TIME_S,
				toString(time, 0));
	}
}

string formatShortTime(double time) {
	if(time == INFINITY || time <= 0)
		return format(locale::TIME_MS_SHORT, "--", "--");
	double mins = floor(time / 60.0);
	double secs = time % 60;
	if(secs < 10.0)
		return format(locale::TIME_MS_SHORT, toString(mins, 0), "0"+toString(floor(secs), 0));
	else
		return format(locale::TIME_MS_SHORT, toString(mins, 0), toString(floor(secs), 0));
}

string formatEstTime(double time) {
	if(time == INFINITY) {
		return "-";
	}
	else if(time <= 0) {
		return "";
	}
	else if(time > 60) {
		return format(locale::TIME_M, toString(round(time / 60.0), 0));
	}
	else {
		return format(locale::TIME_S, toString(time, 0));
	}
}

string formatMinuteRate(double rate) {
	rate *= 60.0;
	return standardize(rate, true)+locale::PER_MINUTE;
}

string formatMinuteRate(double rate, const string& unit) {
	rate *= 60.0;
	return standardize(rate, true)+unit+locale::PER_MINUTE;
}

string formatIncomeRate(double rate, bool perMinute = false) {
	string unit = locale::PER_SECOND;
	if(perMinute) {
		rate *= 60.0;
		unit = locale::PER_MINUTE;
	}
	if(rate < 0)
		return format("[color=#f88]$1$2[/color]", standardize(rate, true), unit);
	else if(rate == 0)
		return format("[color=#bbb]±0$1[/color]", unit);
	else
		return format("[color=#8f8]+$1$2[/color]", standardize(rate, true), unit);
}

string formatRate(double rate) {
	if(rate < 0.2) {
		rate *= 60.0;
		return standardize(rate, true)+locale::PER_MINUTE;
	}
	else {
		return standardize(rate, true)+locale::PER_SECOND;
	}
}

string formatRate(double rate, const string& unit) {
	if(rate < 0.2) {
		rate *= 60.0;
		return standardize(rate, true)+unit+locale::PER_MINUTE;
	}
	else {
		return standardize(rate, true)+unit+locale::PER_SECOND;
	}
}

string formatEffect(const string& effect, const string& magnitude) {
	return format("$1\n[right][b]$2[/b][/right]", effect, magnitude);
}

string formatPosEffect(const string& effect, const string& magnitude) {
	return format("$1\n[right][b][color=#0f0]$2[/color][/b][/right]", effect, magnitude);
}

string formatNegEffect(const string& effect, const string& magnitude) {
	return format("$1\n[right][b][color=#f00]$2[/color][/b][/right]", effect, magnitude);
}

string formatMagEffect(const string& effect, double amt) {
	string magnitude;
	if(amt < 0.0)
		magnitude = "[color=#f00]-"+standardize(amt, true)+"[/color]";
	else
		magnitude = "[color=#0f0]+"+standardize(amt, true)+"[/color]";
	return formatEffect(effect, magnitude);
}

string formatPctEffect(const string& effect, float pct) {
	string magnitude;
	if(pct < 0.f)
		magnitude = "[color=#f00]-"+toString(pct*-100.f, 0)+"%[/color]";
	else
		magnitude = "[color=#0f0]+"+toString(pct*100.f, 0)+"%[/color]";

	return formatEffect(effect, magnitude);
}

string formatPctEffect(const string& effect, float pct, const string& mod) {
	string magnitude;
	if(pct < 0.f)
		magnitude = mod+" [color=#f00]-"+toString(pct*-100.f, 0)+"%[/color]";
	else
		magnitude = mod+" [color=#0f0]+"+toString(pct*100.f, 0)+"%[/color]";

	return formatEffect(effect, magnitude);
}

string formatObjectName(Object& obj) {
	if(obj.isShip)
		return formatShipName(cast<Ship>(obj));
	else
		return obj.name;
}

string formatShipName(Ship& ship) {
	if(ship.named)
		return format("$1 ($2)", ship.name, standardize(ship.blueprint.design.size, true));
	return formatShipName(ship.blueprint.design);
}

string formatShipName(const Design@ dsg) {
	if(dsg is null)
		return "-";
	string name = dsg.name;
	if(dsg.next() !is null)
		name += format(locale::REV_SPEC, toString(dsg.revision));
	name = format("$1 ($2)", name, standardize(dsg.size, true));
	return name;
}
