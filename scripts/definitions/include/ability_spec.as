import abilities;
from abilities import addAbilityType;

_Type definition;
void init() {
	if(definition.implementationClass.length != 0)
		@definition.implementation = getClass(definition.implementationClass);
	addAbilityType(definition);
}
