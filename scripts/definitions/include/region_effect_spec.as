import region_effects;
from region_effects import addRegionEffect;

_Type definition;
void init() {
	if(definition.implementationClass.length != 0)
		@definition.implementation = getClass(definition.implementationClass);
	addRegionEffect(definition);
}
