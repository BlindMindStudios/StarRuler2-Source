import attributes;

tidy class Attributes : Component_Attributes {
	array<double> attributes(getEmpAttributeCount());

	double getAttribute(Empire& emp, uint id) {
		if(id < EA_COUNT)
			return emp.attributes[id];
		return attributes[id];
	}

	void readAttributes(Empire& emp, Message& msg) {
		msg.readAlign();
		uint cnt = 0;
		msg >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			uint index = msg.readLimited(attributes.length-1);

			double value = 1.0;
			msg >> value;

			attributes[index] = value;
			if(index < EA_COUNT)
				emp.attributes[index] = value;
		}
	}
};
