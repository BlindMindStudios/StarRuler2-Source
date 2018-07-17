#include "binds.h"
#include "script_components.h"
#include "main/references.h"

namespace scripts {

void RegisterServerSideBinds(bool shadow) {
	InterfaceBind inf("Serializable");

	//Declarations
	RegisterObjectBinds(true, true, shadow);
	RegisterObjectDefinitions();
	RegisterEmpireBinds(true, true);
	RegisterDesignBinds(!shadow, true);
	RegisterObjectCreation(true);
	RegisterSaveFileBinds(true, true);
	RegisterRenderBinds(true, false, true);

	RegisterDataBinds();
	RegisterThreadingBinds();
	RegisterInspectionBinds();
	RegisterRenderBinds(false, false, true);
	RegisterObjectCreation(false);
	RegisterDesignBinds(!shadow, false);
	RegisterNetworkBinds(true);
	RegisterSaveFileBinds(true, false);
	RegisterEventBinds(true, shadow, false);
	RegisterComponentInterfaces(true);
	RegisterEmpireBinds(false, true);
	RegisterObjectBinds(false, true, shadow);
	RegisterSoundBinds();
	RegisterFormulaBinds(true);
	RegisterDynamicTypes(true);
	RegisterDatafiles();
	RegisterScriptHooks();
	RegisterJSONBinds();
	RegisterProfileBinds();
}

void RegisterClientSideBinds(bool menu) {
	InterfaceBind inf("Serializable");

	RegisterObjectBinds(true, false, false);
	RegisterObjectDefinitions();
	RegisterEmpireBinds(true, false);
	RegisterDesignBinds(false, true);
	RegisterSaveFileBinds(false, true);
	RegisterRenderBinds(true, false, false);

	RegisterDataBinds();
	RegisterThreadingBinds();
	RegisterGeneralBinds(false, false);
	RegisterProfileBinds();
	RegisterGuiBinds();
	RegisterParticleSystemBinds();
	RegisterRenderBinds(false, false, false);
	RegisterInspectionBinds();
	RegisterDesignBinds(false, false);
	RegisterJoystickBinds();
	RegisterNetworkBinds(false);
	RegisterSaveFileBinds(false, false);
	RegisterEventBinds(false, false, menu);
	RegisterComponentInterfaces(false);
	RegisterObjectBinds(false, false, false);
	RegisterEmpireBinds(false, false);
	RegisterSoundBinds();
	RegisterFormulaBinds(false);
	RegisterDynamicTypes(false);
	RegisterDatafiles();
	RegisterScriptHooks();
	RegisterJSONBinds();
	RegisterWebBinds();
	RegisterIRCBinds();
}

void RegisterServerBinds(asIScriptEngine* engine) {
	if(!engine)
		return;
	setEngine(engine);
	RegisterServerSideBinds(false);
	RegisterGeneralBinds(true, false);
}

void RegisterShadowBinds(asIScriptEngine* engine) {
	if(!engine)
		return;
	setEngine(engine);
	RegisterServerSideBinds(true);
	RegisterGeneralBinds(true, true);
}

void RegisterClientBinds(asIScriptEngine* engine) {
	if(!engine)
		return;
	setEngine(engine);
	RegisterClientSideBinds(false);
	RegisterMenuBinds(true);
}

void RegisterMenuBinds(asIScriptEngine* engine) {
	if(!engine)
		return;
	setEngine(engine);
	RegisterClientSideBinds(true);
	RegisterMenuBinds(false);
}

};
