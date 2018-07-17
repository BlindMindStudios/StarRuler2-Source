#priority init 1501
import maps;

const int DEFAULT_SYSTEM_COUNT = 60;
const double DEFAULT_SPACING = 6500.0;
const double MIN_SPACING = 6500.0;

void init() {
	auto@ mapClass = getClass("Map");
	for(uint i = 0, cnt = THIS_MODULE.classCount; i < cnt; ++i) {
		auto@ cls = THIS_MODULE.classes[i];
		if(cls !is mapClass && cls.implements(mapClass))
			cls.create();
	}
}
