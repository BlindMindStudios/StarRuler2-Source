#include "main/references.h"
#include "generic_call.h"
#include "compat/misc.h"
#include "str_util.h"
#include "obj/object.h"
#include "design/design.h"
#include "threads.h"
#include "empire.h"
#include "script_bind.h"
#include <assert.h>
#include <sstream>
#include <unordered_map>
#include "scriptany.h"
#include "network.h"
#include "network/network_manager.h"
#include "network/player.h"
#include "scripts/binds.h"
#include <stdint.h>

#undef GetObject

namespace scripts {
	
GenericType* GT_uint = nullptr;
GenericType* GT_Custom_Handle = nullptr;
GenericType* GT_Player_Ref = nullptr;
GenericType* GT_Object_Ref = nullptr;
GenericType* GT_Object_Handle = nullptr;
GenericType* GT_Empire_Ref = nullptr;
GenericType* GT_Node_Ref = nullptr;
GenericType* GT_Ref = nullptr;

void trivialCopy(GenericValue& to, GenericValue& from) {
	memcpy(&to,&from,sizeof(GenericValue));
}

template<class T>
void copyPtrType(GenericValue& to, GenericValue& from) {
	to.ptr = new T(*(T*)from.ptr);
	to.managed = true;
}

template<class T>
void simpleRetObjSafe(GenericValue& val, asIScriptGeneric* gen) {
	static T dValue;
	if(val.ptr)
		gen->SetReturnObject(val.ptr);
	else
		gen->SetReturnObject(&dValue);
}

static umap<std::string, GenericType*> genericTypes;

void initGenericTypes() {
	//Clear previous
	genericTypes.clear();

	//Primitive types
	genericTypes["int"] = (new GenericType())->setup<int>("int",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.integer = gen->GetArgDWord(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnDWord(val.integer);
		}
	);

	genericTypes["uint"] = (new GenericType())->setup<unsigned>("uint",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.uint = gen->GetArgDWord(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnDWord(val.uint);
		}
	);

	genericTypes["int64"] = (new GenericType())->setup<long long>("int64",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.longint = gen->GetArgQWord(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnQWord(val.longint);
		}
	);

	genericTypes["uint64"] = (new GenericType())->setup<long long>("uint64",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.longint = gen->GetArgQWord(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnQWord(val.longint);
		}
	);

	genericTypes["float"] = (new GenericType())->setup<float>("float",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.sfloat = gen->GetArgFloat(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnFloat(val.sfloat);
		}
	);

	genericTypes["double"] = (new GenericType())->setup<double>("double",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.dfloat = gen->GetArgDouble(i);
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnDouble(val.dfloat);
		}
	);

	genericTypes["bool"] = (new GenericType())->setup<bool>("bool",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.boolean = gen->GetArgByte(i) != 0;
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			gen->SetReturnByte(val.boolean);
		}
	);

	//Objects
	auto getObj = [](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
		val.ptr = gen->GetArgObject(i);
		val.managed = false;
	};

	auto retObj = [](GenericValue& val, asIScriptGeneric* gen) {
		gen->SetReturnObject(val.ptr);
	};

	auto callObj = [](Call& cl, GenericValue& val) {
		cl.callObjRet(val.ptr);
	};

	auto pushObj = [](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
		cl.pushObj(val.ptr);
	};

	genericTypes["vec3d"] = (new GenericType())->setup<vec3d*>("vec3d",
		//Get from argument
		getObj,
		//Return to generic
		simpleRetObjSafe<vec3d>,
		//Copy to new memory
		copyPtrType<vec3d>,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.v3)
				msg << *val.v3;
			else
				msg << vec3d();
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.v3) {
				val.v3 = new vec3d();
				val.managed = true;
			}
			msg >> *val.v3;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.v3;
		},
		//Const on client
		false
	);

	genericTypes["vec2i"] = (new GenericType())->setup<vec3d*>("vec2i",
		//Get from argument
		getObj,
		//Return to generic
		simpleRetObjSafe<vec2i>,
		//Copy to new memory
		copyPtrType<vec2i>,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.v2)
				msg << *val.v2;
			else
				msg << vec2i();
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.v2) {
				val.v2 = new vec2i();
				val.managed = true;
			}
			msg >> *val.v2;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.v2;
		},
		//Const on client
		false
	);

	genericTypes["quaterniond"] = (new GenericType())->setup<quaterniond*>("quaterniond",
		//Get from argument
		getObj,
		//Return to generic
		simpleRetObjSafe<quaterniond>,
		//Copy to new memory
		copyPtrType<quaterniond>,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.quat)
				msg << *val.quat;
			else
				msg << quaterniond();
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.quat) {
				val.quat = new quaterniond();
				val.managed = true;
			}
			msg >> *val.quat;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.quat;
		},
		//Const on client
		false
	);

	genericTypes["ref"] = (new GenericType())->setup<void*>("ref",
		//Get from argument
		getObj,
		//Return to generic
		retObj,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write a ref to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read a ref from message";
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	genericTypes["any"] = (new GenericType())->setup<void*>("any",
		//Get from argument
		getObj,
		//Return to generic
		retObj,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write any to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read any from message";
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	genericTypes["string"] = (new GenericType())->setup<void*>("string",
		//Get from argument
		getObj,
		//Return to generic
		simpleRetObjSafe<std::string>,
		//Copy to new memory
		copyPtrType<std::string>,
		//Call and retrieve return
		callObj,
		//Push to argument
		pushObj,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.str)
				msg << *val.str;
			else
				msg << "";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.str) {
				val.str = new std::string();
				val.managed = true;
			}
			msg >> *val.str;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.str;
		},
		//Const on client
		false
	);

	//Pointers and handles
	auto getPtr = [](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
		val.ptr = gen->GetArgAddress(i);
		val.managed = false;
	};

	auto retPtr = [](GenericValue& val, asIScriptGeneric* gen) {
		gen->SetReturnAddress(val.ptr);
	};

	auto callPtr = [](Call& cl, GenericValue& val) {
		cl.call(val.ptr);
	};

	auto pushPtr = [](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
		cl.push(val.ptr);
	};

	genericTypes["string&"] = (new GenericType())->setup<void*>("string&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		copyPtrType<std::string>,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.str)
				msg << *val.str;
			else
				msg << "";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.str) {
				val.str = new std::string();
				val.managed = true;
			}
			msg >> *val.str;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.str;
		},
		//Const on client
		false
	);

	genericTypes["Message&"] = (new GenericType())->setup<void*>("Message&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy message
		[](GenericValue& to, GenericValue& from) {
			to.msg = new net::Message();
			to.managed = true;
			*to.msg = *from.msg;
		},
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			//Not doable
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(!val.msg) {
				val.msg = new net::Message();
				val.managed = true;
			}
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed)
				delete val.msg;
		},
		//Const on client
		false
	);

	genericTypes["Node&"] = (new GenericType())->setup<void*>("Node&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy reference
		[](GenericValue& to, GenericValue& from) {
			to.node = from.node;
			to.managed = true;
			if(to.node)
				to.node->grab();
		},
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		nullptr,
		//Read from Message
		nullptr,
		//Destruct value
		[](GenericValue& val) {
			if(val.managed && val.node)
				val.node->drop();
		},
		//Const on client
		false
	);

	genericTypes["Object&"] = (new GenericType())->setup<void*>("Object&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy reference
		[](GenericValue& to, GenericValue& from) {
			to.obj = from.obj;
			to.managed = true;
			if(to.obj)
				to.obj->grab();
		},
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			writeObject(msg, val.obj);
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			val.obj = readObject(msg, false);

			if(!val.obj)
				return false;

			val.managed = true;
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.managed && val.obj)
				val.obj->drop();
		},
		//Const on client
		true
	);

	genericTypes["Object@"] = (new GenericType())->setup<void*>("Object@",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.obj = (Object*)gen->GetArgAddress(i);
			if(val.obj)
				val.obj->grab();
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			if(val.obj)
				val.obj->grab();
			gen->SetReturnAddress(val.obj);
		},
		//Copy handle
		[](GenericValue& to, GenericValue& from) {
			to.obj = from.obj;
			if(to.obj)
				to.obj->grab();
		},
		//Call and retrieve return
		callPtr,
		//Push to argument
		[](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
			if(val.obj)
				val.obj->grab();
			cl.push(val.obj);
		},
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			writeObject(msg, val.obj);
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			val.obj = readObject(msg, false);
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.obj)
				val.obj->drop();
		},
		//Const on client
		true
	);

	genericTypes["any@"] = (new GenericType())->setup<void*>("any@",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			CScriptAny* any = (CScriptAny*)gen->GetArgAddress(i);
			val.ptr = any;
			if(any)
				any->AddRef();
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			CScriptAny* any = (CScriptAny*)val.ptr;
			if(any)
				any->AddRef();
			gen->SetReturnAddress(val.ptr);
		},
		//Copy handle
		[](GenericValue& to, GenericValue& from) {
			to.ptr = from.ptr;
			CScriptAny* any = (CScriptAny*)to.ptr;
			if(any)
				any->AddRef();
		},
		//Call and retrieve return
		[](Call& cl, GenericValue& val) {
			cl.call();
			val.ptr = 0; //Not Allowed
		},
		//Push to argument
		[](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
			CScriptAny* any = (CScriptAny*)val.ptr;
			if(any)
				any->AddRef();
			cl.push(val.ptr);
		},
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write any to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read any from message";
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.ptr)
				((CScriptAny*)val.ptr)->Release();
		},
		//Const on client
		true
	);

	genericTypes["Empire&"] = (new GenericType())->setup<void*>("Empire&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.emp)
				msg << val.emp->id;
			else
				msg << (unsigned char)-1;
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			unsigned char id;
			msg >> id;

			val.emp = Empire::getEmpireByID(id);

			if(!val.emp)
				val.emp = Empire::getDefaultEmpire();
			return true;
		},
		//Destruct value
		nullptr,
		//Const on client
		true
	);

	genericTypes["Empire@"] = (new GenericType())->setup<void*>("Empire@",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(val.emp)
				msg << val.emp->id;
			else
				msg << (unsigned char)-1;
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			unsigned char id;
			msg >> id;

			val.emp = Empire::getEmpireByID(id);
			return true;
		},
		//Destruct value
		nullptr,
		//Const on client
		true
	);

	genericTypes["Design@"] = (new GenericType())->setup<void*>("Design@",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.design = (Design*)gen->GetArgAddress(i);
			if(val.design)
				val.design->grab();
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			if(val.design)
				val.design->grab();
			gen->SetReturnAddress(val.design);
		},
		//Copy handle
		[](GenericValue& to, GenericValue& from) {
			to.design = from.design;
			if(to.design)
				to.design->grab();
		},
		//Call and retrieve return
		callPtr,
		//Push to argument
		[](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
			if(val.design)
				val.design->grab();
			cl.push(val.design);
		},
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(!val.design || !val.design->owner) {
				msg << INVALID_EMPIRE;
			}
			else {
				msg << val.design->owner->id;
				msg.writeSmall(val.design->id);
			}
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(val.design) {
				val.design->drop();
				val.design = 0;
			}

			unsigned char ownerID;
			msg >> ownerID;

			if(ownerID == INVALID_EMPIRE)
				return true; //Just make it null
			unsigned designID = msg.readSmall();

			Empire* owner = Empire::getEmpireByID(ownerID);

			if(!owner)
				return true; //Just make it null

			val.design = (Design*)owner->getDesign(designID, true);
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.design)
				val.design->drop();
		},
		//Const on client
		true
	);

	genericTypes["Player&"] = (new GenericType())->setup<void*>("Player&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			msg << val.player->id;
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			int id;
			msg >> id;

			val.player = devices.network->getPlayer(id);
			return true;
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	genericTypes["Material&"] = (new GenericType())->setup<void*>("Material&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write reference to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read reference from message";
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	genericTypes["SpriteSheet&"] = (new GenericType())->setup<void*>("SpriteSheet&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write reference to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read reference from message";
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	genericTypes["Model&"] = (new GenericType())->setup<void*>("Model&",
		//Get from argument
		getPtr,
		//Return to generic
		retPtr,
		//Copy pointer
		trivialCopy,
		//Call and retrieve return
		callPtr,
		//Push to argument
		pushPtr,
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			throw "Cannot write reference to message";
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			throw "Cannot read reference from message";
		},
		//Destruct value
		nullptr,
		//Const on client
		false
	);

	//References to primitives
	auto setupPrimitiveReference = [&](std::string name) {
		genericTypes[name] = (new GenericType())->setup<void*>(name,
			//Get from argument
			getPtr,
			//Return to generic
			retPtr,
			//Unsupported copy
			[](GenericValue& to, GenericValue& from) {
				throwException("Cannot copy primitve references");
			},
			//Call and retrieve return
			[](Call& cl, GenericValue& val) {
				throw "Cannot return primitive reference";
			},
			//Push to argument
			pushPtr,
			//Write to Message
			[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
				throw "Cannot write primitive reference to message";
			},
				//Read from Message
			[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
				throw "Cannot read primitive reference from message";
			},
			//Destruct value
			nullptr,
			//Const on client
			false
		);
	};
	
	setupPrimitiveReference("int&");
	setupPrimitiveReference("uint&");
	setupPrimitiveReference("float&");
	setupPrimitiveReference("double&");
	setupPrimitiveReference("bool&");
	setupPrimitiveReference("vec3d&");
	setupPrimitiveReference("quaterniond&");
	setupPrimitiveReference("Image&");

	//Custom handles
	GT_Custom_Handle = (new GenericType());
	GT_Custom_Handle->setup<void*>("Serializable@",
		//Get from argument
		[](GenericValue& val, unsigned i, asIScriptGeneric* gen) {
			val.script = (asIScriptObject*)gen->GetArgAddress(i);
			if(val.script)
				val.script->AddRef();
		},
		//Return to generic
		[](GenericValue& val, asIScriptGeneric* gen) {
			if(val.script)
				val.script->AddRef();
			gen->SetReturnAddress(val.script);
		},
		//Copy handle
		[](GenericValue& to, GenericValue& from) {
			to.script = from.script;
			if(to.script)
				to.script->AddRef();
		},
		//Call and retrieve return
		[](Call& cl, GenericValue& val) {
			cl.call();
			val.ptr = 0; //Not Allowed
		},
		//Push to argument
		[](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
			if(custom) {
				cl.push(custom(desc, val.script));
			}
			else {
				if(val.script)
					val.script->AddRef();
				cl.push(val.ptr);
			}
		},
		//Write to Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
			if(custom)
				custom(msg, desc, val);
		},
		//Read from Message
		[](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
			if(custom)
				custom(msg, desc, val);
			return true;
		},
		//Destruct value
		[](GenericValue& val) {
			if(val.script)
				val.script->Release();
		},
		//Const on client
		true
	);

	//Cache types
	GT_uint = genericTypes["uint"];
	GT_Player_Ref = genericTypes["Player&"];
	GT_Object_Ref = genericTypes["Object&"];
	GT_Object_Handle = genericTypes["Object@"];
	GT_Empire_Ref = genericTypes["Empire&"];
	GT_Node_Ref = genericTypes["Node&"];
	GT_Ref = genericTypes["ref"];
};

void bindGenericObjectType(ScriptObjectType* type, std::string name) {
	std::string ref = name+"&";
	std::string handle = name+"@";

	auto* refType = new GenericType();
	*refType = *GT_Object_Ref;
	refType->name = ref;
	genericTypes[ref] = refType;
	type->refType = refType;

	auto* handleType = new GenericType();
	*handleType = *GT_Object_Handle;
	handleType->name = handle;
	genericTypes[handle] = handleType;
	type->handleType = handleType;
}

const std::string strVoid("void");
const std::string& getTypeString(GenericType* type) {
	if(type)
		return type->name;
	return strVoid;
}

GenericType* getStringType(const std::string& type) {
	auto it = genericTypes.find(type);
	if(it != genericTypes.end())
		return it->second;
	return nullptr;
}

GenericCallDesc::GenericCallDesc()
	: returnType(nullptr), argCount(0), constFunction(false), returnsArray(false) {
}

GenericCallDesc::GenericCallDesc(std::string decl, bool hasReturnType, bool customRefs)
	: returnType(nullptr), argCount(0), constFunction(false), returnsArray(false) {

	parse(decl, hasReturnType, customRefs);
}

void GenericCallDesc::parse(std::string decl, bool hasReturnType, bool customRefs) {
	//Retrieve the return type first
	if(hasReturnType) {
		if(decl.compare(0, 6, "const ") == 0) {
			returnType.isConst = true;
			decl = decl.substr(6);
		}

		auto pos = decl.find(' ');
		auto brPos = decl.find('(');

		if(pos != std::string::npos && brPos > pos) {
			std::string retstr = decl.substr(0, pos);
			decl = decl.substr(pos + 1);

			GenericType* type = getStringType(retstr);

			if(!type) {
				if(retstr.compare(retstr.size() - 3, 3, "@[]") == 0)
					returnsArray = true;
			}
			else {
				returnType = type;
			}
		}
	}

	//Ignore semicolon
	if(decl[decl.size() - 1] == ';')
		decl = decl.substr(0, decl.size() - 1);

	//Check if it ends in const
	if(decl.compare(decl.size() - 6, 6, " const") == 0) {
		decl = decl.substr(0, decl.size() - 6);
		constFunction = true;
	}

	//Parse the rest of the function
	std::vector<std::string> argstr;
	if(funcSplit(decl, name, argstr))
		append(argstr, customRefs);
}

void GenericCallDesc::append(std::vector<std::string>& argstr, bool customRefs) {
	unsigned count = argstr.size();
	if(argCount + count > MAX_GENERIC_ARGUMENTS)
		return;

	for(unsigned i = 0; i < count; ++i) {
		std::string& arg = argstr[i];

		//Check for const argument
		if(arg.compare(0, 6, "const ") == 0) {
			arguments[argCount + i].isConst = true;
			arg = arg.substr(6);
		}

		//Read default value for declaration
		auto& adesc = arguments[argCount + i];
		auto eqpos = arg.find('=');
		if(eqpos != std::string::npos)
			adesc.defaultValue = arg.substr(eqpos+1);

		//Remove the variable name from the argument,
		//use only the type name
		auto pos = arg.find(' ');
		if(pos != std::string::npos && pos < arg.size() - 1) {
			if(eqpos != std::string::npos)
				adesc.argName = trim(arg.substr(pos, eqpos-pos));
			else
				adesc.argName = trim(arg.substr(pos));
		}
		if(pos != std::string::npos)
			arg = arg.substr(0, pos);

		GenericType* type = getStringType(arg);
		if(!type && arg.size() > 1 && arg[arg.size() - 1] == '@') {
			if(customRefs) {
				adesc.type = GT_Ref;
			}
			else {
				adesc.type = GT_Custom_Handle;
				adesc.customName = arg.substr(0, arg.size() - 1);
			}
		}
		else {
			adesc.type = type;
		}
	}

	argCount += count;
}

void GenericCallDesc::append(GenericType* argument) {
	if(argCount >= MAX_GENERIC_ARGUMENTS)
		return;

	arguments[argCount] = ArgumentDesc(argument);
	++argCount;
}

void GenericCallDesc::prepend(ArgumentDesc argument) {
	if(argCount >= MAX_GENERIC_ARGUMENTS)
		return;

	for(unsigned i = argCount; i > 0; --i)
		arguments[i] = arguments[i - 1];

	arguments[0] = argument;
	++argCount;
}

void GenericCallDesc::append(GenericCallDesc& other) {
	if(argCount + other.argCount > MAX_GENERIC_ARGUMENTS)
		return;

	for(unsigned i = 0; i < other.argCount; ++i)
		arguments[argCount + i] = other.arguments[i];

	argCount += other.argCount;
}

std::string GenericCallDesc::declaration(bool ret, bool forceConst, unsigned start) {
	std::stringstream out;

	if(ret) {
		out << returnType.toString();
		out << " ";
	}

	out << name << "(";

	for(unsigned i = start; i < argCount; ++i) {
		auto& adesc = arguments[i];
		if(i != start)
			out << ", ";
		if(!adesc.type) {
			out << "void";
			continue;
		}
		if(adesc.type->wouldConst && forceConst && !adesc.isConst)
			out << "const ";
		out << adesc.toString();
		if(!adesc.argName.empty())
			out << " " << adesc.argName;
		if(!adesc.defaultValue.empty()) {
			if(adesc.argName.empty())
				out << " arg" << i;
			out << " =" << adesc.defaultValue;
		}
	}

	out << ")";

	if(constFunction)
		out << " const";

	return out.str();
}

GenericValue GenericCallDesc::call(Call& cl) {
	GenericValue val;

	if(returnsArray) {
		val.ptr = (void*)StartYieldContext();
		cl.call();
		EndYieldContext();
	}
	else if(returnType.type && returnType.type->call)
		returnType.type->call(cl, val);
	else
		cl.call();

	return val;
}

GenericCallData::GenericCallData(GenericCallData& data) : desc(data.desc), object(data.object) {
	data.object = 0;
	memset(values, 0, sizeof(values));

	for(unsigned i = 0; i < desc.argCount; ++i) {
		auto& arg = desc.arguments[i];
		if(arg.type)
			arg.type->copy(values[i], data.values[i]);
	}
}

GenericCallData::GenericCallData(GenericCallDesc& Desc)
	: desc(Desc), object(0) {
	memset(values, 0, sizeof(values));
}

GenericCallData::GenericCallData(GenericCallDesc& Desc, asIScriptGeneric* gen)
	: desc(Desc), object(gen->GetObject()) {

	memset(values, 0, sizeof(values));
	//assert(gen->GetArgCount() == desc.argCount);

	for(unsigned i = 0; i < desc.argCount; ++i) {
		auto& arg = desc.arguments[i];
		if(arg.type && arg.type->get)
			arg.type->get(values[i], i, gen);
	}
}

GenericCallData::~GenericCallData() {
	for(unsigned i = 0; i < desc.argCount; ++i) {
		auto& arg = desc.arguments[i];
		if(arg.type && arg.type->destruct)
			arg.type->destruct(values[i]);
	}
}

void GenericCallData::pushTo(Call& call, int startAt, customHandle custom) {
	for(unsigned i = startAt; i < desc.argCount; ++i) {
		auto& arg = desc.arguments[i];
		if(arg.type && arg.type->push)
			arg.type->push(call, arg, values[i], custom);
	}
}

GenericValue GenericCallData::call(Call& cl) {
	return desc.call(cl);
}

void GenericCallData::write(net::Message& msg, unsigned startAt, customRW custom) {
	for(unsigned i = startAt; i < desc.argCount; ++i) {
		GenericValue& val = values[i];

		auto& arg = desc.arguments[i];
		if(arg.type && arg.type->write)
			arg.type->write(msg, arg, val, custom);
	}
}

bool GenericCallData::read(net::Message& msg, unsigned startAt, customRW custom) {
	for(unsigned i = startAt; i < desc.argCount; ++i) {
		GenericValue& val = values[i];

		auto& arg = desc.arguments[i];
		if(arg.type && arg.type->read) {
			if(!arg.type->read(msg, arg, val, custom))
				return false;
		}
	}
	return true;
}

asIScriptFunction* getFunction(Manager* manager, const char* module, GenericCallDesc& desc, bool acceptConst) {
	return manager->getFunction(module, desc.declaration(true, acceptConst).c_str());
}

struct genHandle {
	GenericCallDesc desc;
	GenericHandler handler;
	void* arg;
};

threads::Mutex genericBindMutex;
std::vector<genHandle*> genHandlers;

static void handleGeneric(asIScriptGeneric* gen) {
	//Retrieve the handle data
	auto func = gen->GetFunction();
	genHandle* handle = (genHandle*)func->GetUserData();

	//Parse function data from generic
	GenericCallData args(handle->desc, gen);

	//Call the appropriate function
	GenericValue retVal = handle->handler(handle->arg, args);

	//Handle the return value
	if(handle->desc.returnsArray)
		gen->SetReturnAddress(retVal.ptr);
	else if(handle->desc.returnType.type && handle->desc.returnType.type->ret)
		handle->desc.returnType.type->ret(retVal, gen);
}

void bindGeneric(int fid, GenericCallDesc& desc, GenericHandler handler, void* arg) {
	//Create the handle data struct we need
	genHandle* handle = new genHandle;
	handle->desc = desc;
	handle->handler = handler;
	handle->arg = arg;

	{
		threads::Lock lock(genericBindMutex);
		genHandlers.push_back(handle);
	}

	//Assign the handle data to the function's
	//user data so we don't need to lookup
	auto func = getEngine()->GetFunctionById(fid);
	if(func)
		func->SetUserData(handle);
}

int bindGeneric(GenericCallDesc& desc, GenericHandler handler, void* arg, bool acceptConst) {
	//Register the function to the engine
	auto eng = getEngine();
	int fid = eng->RegisterGlobalFunction(desc.declaration(true, acceptConst).c_str(),
										asFUNCTION(handleGeneric), asCALL_GENERIC);
	assert(fid >= 0);

	bindGeneric(fid, desc, handler, arg);
	return fid;
}

int bindGeneric(ClassBind& cls, GenericCallDesc& desc, GenericHandler handler, void* arg, bool acceptConst) {
	//Register the function to the engine
	auto eng = getEngine();
	int fid = eng->RegisterObjectMethod(cls.name.c_str(), desc.declaration(true, acceptConst).c_str(),
										asFUNCTION(handleGeneric), asCALL_GENERIC);
	assert(fid >= 0);

	bindGeneric(fid, desc, handler, arg);
	return fid;
}

int bindGeneric(ClassBind& cls, const std::string& decl, GenericCallDesc& desc, GenericHandler handler, void* arg) {
	auto eng = getEngine();
	int fid = eng->RegisterObjectMethod(cls.name.c_str(), decl.c_str(), asFUNCTION(handleGeneric), asCALL_GENERIC);
	assert(fid >= 0);

	bindGeneric(fid, desc, handler, arg);
	return fid;
}

void clearGenericBinds() {
	threads::Lock lock(genericBindMutex);
	foreach(it, genHandlers)
		delete *it;
	genHandlers.clear();
}

};
