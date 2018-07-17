#pragma once
#include "angelscript.h"
#include "util/format.h"
#include <string>
#include <vector>

namespace scripts {

//#define DOCUMENT_API
#ifdef DOCUMENT_API
#define doc(...) ( __VA_ARGS__ )
#define classdoc(cls, str) cls.document(str)
#define _DOC Documentor&
#define _GLOBAL_DOC GlobalDoc&
#define _MEMBER_DOC MemberDoc&

struct Documentor {
	int fid;
	std::string decl;
	std::string funcName;
	bool documented;

	std::string funcDoc;
	std::string retDoc;
	std::vector<std::string> argNames;
	std::vector<std::string> argDefaults;
	std::vector<std::string> argDoc;

	Documentor();
	Documentor(int fid, std::string decl);
	void operator()(const char* funcDoc, ...);
};

struct GlobalDoc {
	std::string doc;
	std::string varname;

	GlobalDoc(std::string decl);
	void operator()(const char* doc);
};

struct MemberDoc {
	std::string clsname;
	std::string varname;
	std::string doc;

	MemberDoc(std::string clsname, std::string decl);
	void operator()(const char* doc);
};

Documentor* getDocumentation(asIScriptEngine* eng, int fid);
Documentor* getDocumentation(asIScriptFunction* func);
GlobalDoc* getGlobalDocumentation(asIScriptEngine* eng, std::string varname);
std::string getClassDocumentation(asIScriptEngine* eng, std::string clsname);
MemberDoc* getMemberDocumentation(asIScriptEngine* eng, std::string clsname, std::string varname);
void documentBinds();

#else
#define doc(...)
#define classdoc(cls, str)
#define _DOC void
#define _GLOBAL_DOC void
#define _MEMBER_DOC void
#endif

void setEngine(asIScriptEngine* engine);
asIScriptEngine* getEngine();

_DOC bind(const char* declaration, asSFuncPtr func, asDWORD callType = asCALL_CDECL);
_DOC bind(const char* declaration, asSFuncPtr func, void* delegateObject);
void bindStringFactory(const char* stringClass, asSFuncPtr func, asDWORD callType = asCALL_CDECL);
_GLOBAL_DOC bindGlobal(const char* declaration, void* ptr);
void bindFuncdef(const char* declaration);

struct Namespace {
	Namespace(const char* name) {
		getEngine()->SetDefaultNamespace(name);
	}

	~Namespace() {
		getEngine()->SetDefaultNamespace("");
	}
};

struct ClassBind {
	std::string name;
	
	//Does not register the class, but allows registration of members of the class
	ClassBind(const char* Name);
	//Registers the class, and allows registration of members of the class
	ClassBind(const char* Name, asDWORD flags, int size = 0);

	asITypeInfo* getType();
	
	//Registers a factory function
	_DOC addFactory(const char* declaration, asSFuncPtr func);
	//Registers a generic factory function
	_DOC addGenericFactory(const char* declaration, asSFuncPtr func, void* userdata = 0);
	//Registers a initializer function
	_DOC addConstructor(const char* declaration, asSFuncPtr func);
	//Registers a destructor function
	_DOC addDestructor(const char* declaration, asSFuncPtr func);
	//Registers a native method of the class
	_DOC addMethod(const char* declaration, asSFuncPtr func);
	//Registers a psuedo-method of the class - a global function that accepts a pointer to the class (either first or last argument)
	_DOC addExternMethod(const char* declaration, asSFuncPtr func, bool ptrFirst = true);
	//Registers a psuedo-method of the class, implemented as a generic call
	_DOC addGenericMethod(const char* declaration, asSFuncPtr func, void* userdata = 0);
	//Registers a behaviour
	_DOC addBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func);
	//Registers a pseudo-method behaviour
	_DOC addExternBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func, bool ptrFirst = true);
	//Registers a generic behaviour
	_DOC addGenericBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func, void* userdata = 0);
	//Registers a behaviour that doesn't take an object
	_DOC addLooseBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func);
	//Register garbage collection functions to the object
	void addGarbageCollection(asSFuncPtr setflag, asSFuncPtr getflag, asSFuncPtr getrefcount, asSFuncPtr enumrefs, asSFuncPtr releaserefs);

	//Registers a member of the class
	_MEMBER_DOC addMember(const char* declaration, size_t offset);
	
	//Register reference count methods
	void setReferenceFuncs(asSFuncPtr grab, asSFuncPtr drop);

#ifdef DOCUMENT_API
	void document(std::string str);
#endif
private:
	ClassBind() {}
};

struct InterfaceBind {
	const char* name;

	//Allows registering methods on interfaces
	InterfaceBind(const char* Name, bool Register = true);

	//Add a method
	_DOC addMethod(const char* declaration, asIScriptFunction** funcptr = 0);

#ifdef DOCUMENT_API
	void document(std::string str);
#endif
};

struct EnumBind {
	const char* name;
	
	//Allows registering constants to the enum, and optionally registers it
	EnumBind(const char* Name, bool Register = true);

	//To set a value, use EnumBind["ValueName"] = value;

	struct setter {
		const char* enumName, *itemName;
		void operator=(int val);
		setter(const char* E, const char* I);
	};

	setter operator[](const char* item);
	setter operator[](const std::string& item);

#ifdef DOCUMENT_API
	void document(std::string str);
#endif
private:
	EnumBind() {}
};

};
