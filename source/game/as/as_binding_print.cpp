#include "as_binding_print.h"

#include "angelscript.h"
#include <fstream>

using std::endl;

//Prints all enums, global variables, global functions, and object declarations in the engine to the specified file
void printBindings(asIScriptEngine* engine, const char* filename) {
	//TODO
	/*std::ofstream file(filename);
	if(!file.is_open() || !file.good())
		return;

	file << "Enums:" << endl << "======" << endl << endl;

	for(asUINT i = 0, cnt = engine->GetEnumCount(); i < cnt; ++i) {
		int id;
		file << engine->GetEnumByIndex(i, &id) << " {" << endl;

		int prevV = -1;
		bool showNums = false;
		for(asUINT v = 0, vCnt = engine->GetEnumValueCount(id); v < vCnt; ++v) {
			int value;
			file << "\t" << engine->GetEnumValueByIndex(id, v, &value);

			//Show it like a traditional enum if it starts at 0. If it ever breaks from that, begin to always show the numbers
			if(!showNums && value == prevV + 1) {
				file << "," << endl;
				prevV = value;
			}
			else {
				showNums = true;
				file << " = " << value << endl;
			}
		}

		file << "}" << endl << endl;
	}

	file << "Globals:" << endl << "========" << endl << endl;

	for(asUINT i = 0, cnt = engine->GetGlobalPropertyCount(); i < cnt; ++i) {
		const char* name;
		int typeID;
		bool isConst;
		int id = engine->GetGlobalPropertyByIndex(i, &name, 0, &typeID, &isConst);

		file << "\t";
		if(isConst)
			file << "const ";
		file << engine->GetTypeDeclaration(typeID) << " " << name << endl;
	}

	file << endl << "Global Functions:" << endl << "=================" << endl << endl;

	for(asUINT i = 0, cnt = engine->GetGlobalFunctionCount(); i < cnt; ++i) {
		asIScriptFunction* func = engine->GetGlobalFunctionByIndex(i);
		file << func->GetDeclaration() << endl;
	}

	file << endl << "Classes:" << endl << "========" << endl << endl;

	for(asUINT i = 0, cnt = engine->GetObjectTypeCount(); i < cnt; ++i) {
		asITypeInfo* obj = engine->GetObjectTypeByIndex(i);
		file << obj->GetName();
		if(asITypeInfo* base = obj->GetBaseType())
			file << " : " << base->GetName();
		file << " {" << endl;

		for(asUINT p = 0, pCnt = obj->GetPropertyCount(); p < pCnt; ++p) {
			const char* name;
			bool isRef;
			int typeID;
			obj->GetProperty(p, &name, &typeID, 0, 0, &isRef);

			file << "\t" << engine->GetTypeDeclaration(typeID);
			if(isRef)
				file << "@ ";
			else
				file << " ";

			file << name << endl;
		}

		if(obj->GetPropertyCount() != 0 && obj->GetMethodCount() != 0)
			file << endl;

		for(asUINT m = 0, mCnt = obj->GetMethodCount(); m < mCnt; ++m) {
			asIScriptFunction* func = obj->GetMethodByIndex(m);

			file << "\t" << func->GetDeclaration(false) << endl;
		}

		file << "}" << endl << endl;
	}*/
}
