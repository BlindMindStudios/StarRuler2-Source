#include "binds.h"
#include <stdlib.h>
#include <string>
#include "rect.h"
#include "main/logging.h"
#include "design/hull.h"

namespace scripts {

void inspect(asIScriptContext* ctx, const char* name, void* pData, int typeID) {
	asIScriptEngine* engine = ctx->GetEngine();


	union {
		double asDouble;
		asINT64 asInt;
	};
	char buffer[256];
	sprintf(buffer,"<?> at 0x%p",pData);
	const char* value = buffer;

	int objType = typeID & (asTYPEID_MASK_OBJECT | asTYPEID_MASK_SEQNBR);
	void* handle = 0;

	if(typeID & asTYPEID_OBJHANDLE) {
		handle = pData;
		pData = *(void**)pData;
	}

	switch(objType) {
	case asTYPEID_VOID:
		value = "<void>";
		break;
	case asTYPEID_BOOL:
		asInt = *(bool*)pData;
		value = asInt ? "true" : "false";
		break;
	case asTYPEID_INT8:
		asInt = *(char*)pData;
		sprintf(buffer,"%d",(int)asInt);
		value = buffer;
		break;
	case asTYPEID_INT16:
		asInt = *(short*)pData;
		sprintf(buffer,"%d",(int)asInt);
		value = buffer;
		break;
	case asTYPEID_INT32:
		asInt = *(int*)pData;
		sprintf(buffer,"%d",(int)asInt);
		value = buffer;
		break;
	case asTYPEID_INT64:
		asInt = *(asINT64*)pData;
		sprintf(buffer,"%ld",asInt);
		value = buffer;
		break;
	case asTYPEID_UINT8:
		asInt = *(unsigned char*)pData;
		sprintf(buffer,"%d",(unsigned)asInt);
		value = buffer;
		break;
	case asTYPEID_UINT16:
		asInt = *(unsigned short*)pData;
		sprintf(buffer,"%d",(unsigned)asInt);
		value = buffer;
		break;
	case asTYPEID_UINT32:
		asInt = *(unsigned*)pData;
		sprintf(buffer,"%d",(unsigned)asInt);
		value = buffer;
		break;
	case asTYPEID_UINT64:
		asInt = *(asINT64*)pData;
		sprintf(buffer,"%lu",asInt);
		value = buffer;
		break;
	case asTYPEID_FLOAT:
		asDouble = *(double*)pData;
		sprintf(buffer,"%f",asDouble);
		value = buffer;
		break;
	case asTYPEID_DOUBLE:
		asDouble = *(double*)pData;
		sprintf(buffer,"%f",asDouble);
		value = buffer;
		break;
	default:
		if( pData ) {
			if(objType == engine->GetTypeIdByDecl("recti")) {
				recti* r = (recti*)pData;
				sprintf(buffer,"<%d,%d,%d,%d>",r->topLeft.x,r->topLeft.y,r->botRight.x,r->botRight.y);
				value = buffer;
			}
			else if(objType == engine->GetTypeIdByDecl("vec2i")) {
				vec2i* v = (vec2i*)pData;
				sprintf(buffer,"<%d,%d>",v->x,v->y);
				value = buffer;
			}
			else if(objType == engine->GetTypeIdByDecl("vec2f")) {
				vec2f* v = (vec2f*)pData;
				sprintf(buffer,"<%f,%f>",v->x,v->y);
				value = buffer;
			}
			else if(objType == engine->GetTypeIdByDecl("Hull")) {
				HullDef* hull = (HullDef*)pData;
				sprintf(buffer,"{name:%64s; id:%d}",hull->name.c_str(),hull->id);
			}
			else if(handle != 0) {
				sprintf(buffer,"0x%p",handle);
			}
		}
		else {
			value = "null";
		}
	}

	error("%s %s = %s",engine->GetTypeDeclaration(typeID),name,value);
}

void inspect(const std::string& name, void* pData, int typeID) {
	inspect(asGetActiveContext(), name.c_str(), pData, typeID);
}

void printContext() {
	asIScriptContext* ctx = asGetActiveContext();
	for(unsigned d = 0; d < ctx->GetCallstackSize(); ++d) {
		asIScriptFunction* func = ctx->GetFunction(d);
		func->GetName();
		error("%u: %s\n %s(%i)", d, func->GetDeclaration(), func->GetScriptSectionName(), ctx->GetLineNumber(d));
		for(unsigned v = 0; v < (unsigned)ctx->GetVarCount(d); ++v) {
			if(!ctx->IsVarInScope(v,d))
				continue;
			inspect(ctx, ctx->GetVarName(v,d), ctx->GetAddressOfVar(v,d), ctx->GetVarTypeId(v,d));
		}
	}
}

void RegisterInspectionBinds() {
	bind("void inspect(const string &in name, const ?&in)", asFUNCTIONPR(inspect,(const std::string&, void*, int),void));
	bind("void debug()", asFUNCTION(printContext));
}

};
