import construction.Constructible;
import resources;

tidy class ExportConstructible : Constructible {
	Object@ exportTo;
	double givenLabor = 0.0;

	ExportConstructible(Object& obj, Object& exportTo) {
		@this.exportTo = exportTo;
		totalLabor = INT_MAX;
	}

	ExportConstructible(SaveFile& file) {
		Constructible::load(file);
		file >> exportTo;
		file >> givenLabor;
	}

	bool repeat(Object& obj) {
		return false;
	}

	void save(SaveFile& file) {
		Constructible::save(file);
		file << exportTo;
		file << givenLabor;
	}

	ConstructibleType get_type() {
		return CT_Export;
	}

	string get_name() {
		return format(locale::EXPORT_LABOR, exportTo.name);
	}

	bool start(Object& obj) {
		if(started)
			return true;
		if(!Constructible::start(obj))
			return false;
		return true;
	}

	void remove(Object& obj) {
		Constructible::remove(obj);
		if(givenLabor != 0)
			exportTo.modLaborIncome(-givenLabor);
	}

	bool get_canComplete() {
		return false;
	}

	TickResult tick(Object& obj, double time) override {
		if(!exportTo.valid || !obj.canExportLabor || !exportTo.canImportLabor || exportTo.owner !is obj.owner)
			return TR_Remove;
		double income = max(obj.laborIncome, curLabor / max(time, 0.001));
		if(obj.queuePosition(id) != 0)
			income = 0.0;
		curLabor = 0;
		if(income != givenLabor) {
			exportTo.modLaborIncome(income - givenLabor);
			givenLabor = income;
		}
		return exportTo.isUsingLabor ? TR_UsedLabor : TR_UnusedLabor;
	}

	void move(Object& obj, uint toPosition) {
		if(toPosition != 0 && givenLabor > 0 && exportTo.valid) {
			exportTo.modLaborIncome(-givenLabor);
			givenLabor = 0;
		}
	}

	void write(Message& msg) {
		Constructible::write(msg);
		msg << exportTo;
	}
};
