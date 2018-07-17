#include <assert.h>
#include <string.h>
#include "scriptmap.h"
#include "scriptarray.h"

#include "../source/as_scriptengine.h"
#include "../source/as_scriptobject.h"

BEGIN_AS_NAMESPACE

using namespace std;

extern bool IsHandleCompatibleWithObject(asCScriptEngine* engine, void *obj, int objTypeId, int handleTypeId);

//--------------------------------------------------------------------------
// CScriptMap implementation

CScriptMap::CScriptMap(asIScriptEngine *engine)
{
    // We start with one reference
    refCount.set(1);
	gcFlag = false;

	// Start at the zeroth modification
	modCount = 0;

    // Keep a reference to the engine for as long as we live
	// We don't increment the reference counter, because the 
	// engine will hold a pointer to the object. 
    this->engine = engine;

	// Notify the garbage collector of this object
	// TODO: The type id should be cached
	engine->NotifyGarbageCollectorOfNewObject(this, engine->GetTypeInfoByName("map"));
}

CScriptMap::~CScriptMap()
{
    // Delete all keys and values
    DeleteAll();
}

void CScriptMap::AddRef() const
{
	// We need to clear the GC flag
	gcFlag = false;
	refCount.atomicInc();
}

void CScriptMap::Release() const
{
	// We need to clear the GC flag
	gcFlag = false;
	if( refCount.atomicDec() == 0 )
        delete this;
}

int CScriptMap::GetRefCount()
{
	return refCount.get();
}

void CScriptMap::SetGCFlag()
{
	gcFlag = true;
}

bool CScriptMap::GetGCFlag()
{
	return gcFlag;
}

void CScriptMap::EnumReferences(asIScriptEngine *engine)
{
	// Call the gc enum callback for each of the objects
    mapType::iterator it;
    for( it = dict.begin(); it != dict.end(); it++ )
    {
		if( it->second.typeId & asTYPEID_MASK_OBJECT )
			engine->GCEnumCallback(it->second.valueObj);
    }
}

void CScriptMap::ReleaseAllReferences(asIScriptEngine * /*engine*/)
{
	// We're being told to release all references in 
	// order to break circular references for dead objects
	DeleteAll();
}

CScriptMap &CScriptMap::operator =(const CScriptMap &other)
{
	// Clear everything we had before
	DeleteAll();

	// Do a shallow copy of the map
    mapType::const_iterator it;
    for( it = other.dict.begin(); it != other.dict.end(); it++ )
    {
		if( it->second.typeId & asTYPEID_OBJHANDLE )
			Set(it->first, (void*)&it->second.valueObj, it->second.typeId);
		else if( it->second.typeId & asTYPEID_MASK_OBJECT )
			Set(it->first, (void*)it->second.valueObj, it->second.typeId);
		else
			Set(it->first, (void*)&it->second.valueInt, it->second.typeId);
    }

    return *this;
}

void CScriptMap::Set(asINT64 key, void *value, int typeId)
{
	valueStruct valStruct = {{0},0};
	valStruct.typeId = typeId;
	if( typeId & asTYPEID_OBJHANDLE )
	{
		// We're receiving a reference to the handle, so we need to dereference it
		valStruct.valueObj = *(void**)value;
		engine->AddRefScriptObject(valStruct.valueObj, engine->GetTypeInfoById(typeId));
	}
	else if( typeId & asTYPEID_MASK_OBJECT )
	{
		// Create a copy of the object
		valStruct.valueObj = engine->CreateScriptObjectCopy(value, engine->GetTypeInfoById(typeId));
	}
	else
	{
		// Copy the primitive value
		// We receive a pointer to the value.
		int size = engine->GetSizeOfPrimitiveType(typeId);
		memcpy(&valStruct.valueInt, value, size);
	}

    mapType::iterator it;
    it = dict.find(key);
    if( it != dict.end() )
    {
        FreeValue(it->second);

        // Insert the new value
        it->second = valStruct;
    }
    else
    {
        dict.insert(mapType::value_type(key, valStruct));
		++modCount;
    }
}

// This overloaded method is implemented so that all integer and
// unsigned integers types will be stored in the map as int64
// through implicit conversions. This simplifies the management of the
// numeric types when the script retrieves the stored value using a 
// different type.
void CScriptMap::Set(asINT64 key, asINT64 &value)
{
	Set(key, &value, asTYPEID_INT64);
}

// This overloaded method is implemented so that all floating point types 
// will be stored in the map as double through implicit conversions. 
// This simplifies the management of the numeric types when the script 
// retrieves the stored value using a different type.
void CScriptMap::Set(asINT64 key, double &value)
{
	Set(key, &value, asTYPEID_DOUBLE);
}

// This helper function exists to assist various map and iterator
// methods that want to retrieve a value from a standard iterator
bool CScriptMap::Iterator_GetValue(CScriptMap::mapType::const_iterator &it, void *value, int typeId) const {
	// Return the value
	if( typeId & asTYPEID_OBJHANDLE )
	{
		// A handle can be retrieved if the stored type is a handle of same or compatible type
		// or if the stored type is an object that implements the interface that the handle refer to.
		if( (it->second.typeId & asTYPEID_MASK_OBJECT) && 
			IsHandleCompatibleWithObject((asCScriptEngine*)engine, it->second.valueObj, it->second.typeId, typeId) )
		{
			engine->AddRefScriptObject(it->second.valueObj, engine->GetTypeInfoById(it->second.typeId));
			*(void**)value = it->second.valueObj;

			return true;
		}
	}
	else if( typeId & asTYPEID_MASK_OBJECT )
	{
		// Verify that the copy can be made
		bool isCompatible = false;
		if( it->second.typeId == typeId )
			isCompatible = true;

		// Copy the object into the given reference
		if( isCompatible )
		{
			engine->AssignScriptObject(value, it->second.valueObj, engine->GetTypeInfoById(typeId));

			return true;
		}
	}
	else
	{
		if( it->second.typeId == typeId )
		{
			int size = engine->GetSizeOfPrimitiveType(typeId);
			memcpy(value, &it->second.valueInt, size);
			return true;
		}

		// We know all numbers are stored as either int64 or double, since we register overloaded functions for those
		if( it->second.typeId == asTYPEID_INT64 && typeId == asTYPEID_DOUBLE )
		{
			*(double*)value = double(it->second.valueInt);
			return true;
		}
		else if( it->second.typeId == asTYPEID_DOUBLE && typeId == asTYPEID_INT64 )
		{
			*(asINT64*)value = asINT64(it->second.valueFlt);
			return true;
		}
	}

    // AngelScript has already initialized the value with a default value,
    // so we don't have to do anything if we don't find the element, or if 
	// the element is incompatible with the requested type.

	return false;
}

// Returns true if the value was successfully retrieved
bool CScriptMap::Get(asINT64 key, void *value, int typeId) const
{
    mapType::const_iterator it;
    it = dict.find(key);
    if( it != dict.end() )
    {
		// This logic is already implemented in the iterator wrapper,
		// so defer to that function from here
		return Iterator_GetValue(it, value, typeId);
    }

	return false;
}

bool CScriptMap::Get(asINT64 key, asINT64 &value) const
{
	return Get(key, &value, asTYPEID_INT64);
}

bool CScriptMap::Get(asINT64 key, double &value) const
{
	return Get(key, &value, asTYPEID_DOUBLE);
}

bool CScriptMap::Exists(asINT64 key) const
{
    mapType::const_iterator it;
    it = dict.find(key);
    if( it != dict.end() )
        return true;

    return false;
}

bool CScriptMap::IsEmpty() const
{
	if( dict.size() == 0 )
		return true;

	return false;
}

asUINT CScriptMap::GetSize() const
{
	return asUINT(dict.size());
}

void CScriptMap::Delete(asINT64 key)
{
    mapType::iterator it;
    it = dict.find(key);
    if( it != dict.end() )
    {
        FreeValue(it->second);
        dict.erase(it);
		++modCount;
    }
}

void CScriptMap::DeleteAll()
{
    mapType::iterator it;
    for( it = dict.begin(); it != dict.end(); it++ )
        FreeValue(it->second);

    dict.clear();
}

void CScriptMap::DeleteNulls()
{
    mapType::iterator it;
    for( it = dict.begin(); it != dict.end(); it++ )
	{
		if( it->second.typeId & asTYPEID_OBJHANDLE )
			if( it->second.valueObj == 0 )
				it = dict.erase(it);
	}
	++modCount;
}

void CScriptMap::FreeValue(valueStruct &value)
{
    // If it is a handle or a ref counted object, call release
	if( value.typeId & asTYPEID_MASK_OBJECT )
	{
		// Let the engine release the object
		engine->ReleaseScriptObject(value.valueObj, engine->GetTypeInfoById(value.typeId));
		value.valueObj = 0;
		value.typeId = 0;
	}

    // For primitives, there's nothing to do
}

CScriptArray* CScriptMap::GetKeys() const
{
	// TODO: optimize: The string array type should only be determined once. 
	//                 It should be recomputed when registering the map class.
	//                 Only problem is if multiple engines are used, as they may not
	//                 share the same type id. Alternatively it can be stored in the 
	//                 user data for the map type.
	int stringArrayType = engine->GetTypeIdByDecl("array<int64>");
	asITypeInfo *ot = engine->GetTypeInfoById(stringArrayType);

	// Create the array object
	CScriptArray *array = new CScriptArray(dict.size(), ot);
	long current = -1;
	mapType::const_iterator it;
	for( it = dict.begin(); it != dict.end(); it++ )
	{
		current++;
		*(asINT64*)array->At(current) = it->first;
	}

	return array;
}

CScriptMap::Iterator CScriptMap::GetIterator() const {
	return Iterator(this);
}

void CScriptMap::Delete(CScriptMap::Iterator& it) {
	if( it.container != this ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Mismatched script container and iterator.");
		return;
	}

	if( it.it == dict.end() ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Deleting invalid iterator.");
		return;
	}

	it.it = dict.erase(it.it);
	it.first = true;
	++modCount;
	it.modCount = modCount;
}

//--------------------------------------------------------------------------
// Iterator implementation

CScriptMap::Iterator::Iterator() {
	container = 0;
}

CScriptMap::Iterator::Iterator(const CScriptMap *container) {
	this->container = container;

	// Start the iteration
	it = container->dict.begin();
	first = true;

	// Track the modification count of the map
	// so we can safely fail when the map is altered
	modCount = container->modCount;

	// Keep a reference to the map so it doesn't
	// get destroyed from under us
	container->AddRef();
}

CScriptMap::Iterator::~Iterator() {
	// Release map reference
	if(container)
		container->Release();
}

static void DefaultConstructIterator(void *memory) {
	new(memory) CScriptMap::Iterator();
}

static void ConstructIterator(void *memory, const CScriptMap *container) {
	new(memory) CScriptMap::Iterator(container);
}

static void DestructIterator(CScriptMap::Iterator &it) {
	it.~Iterator();
}

asINT64 CScriptMap::Iterator::GetKey() {
	if( !container || modCount != container->modCount || it == container->dict.end() ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Iterator not valid or map changed.");

		return 0;
	}

	return it->first;
}

bool CScriptMap::Iterator::Iterate(void *value, int typeId) {
	return Iterate(0, value, typeId);
}

bool CScriptMap::Iterator::Iterate(asINT64* key, void *value, int typeId) {
	if( !container ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Iterating on invalid iterator.");
		return false;
	}

	if( modCount != container->modCount ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Dictionary changed during iteration.");
		return false;
	}

	if( it == container->dict.end() )
		return false;

	if( first )
		first = false;
	else
		++it;

	if( it == container->dict.end() )
		return false;

	if( key )
		*key = it->first;

	if( container->Iterator_GetValue(it, value, typeId) )
	{
		return true;
	}
	else
	{
		// The caller can check IsValid to see if the iteration can still
		// continue because the type was wrong, or whether it has really ended
		return false;
	}
}

bool CScriptMap::Iterator::IsValid() {
	if( !container || modCount != container->modCount ) {
		asIScriptContext *ctx = asGetActiveContext();
		if( ctx )
			ctx->SetException("Map changed during iteration.");
	}

	return it != container->dict.end();
}

CScriptMap::Iterator &CScriptMap::Iterator::operator =(const CScriptMap::Iterator &other) {
	if(other.container)
		other.container->AddRef();
	if(container)
		container->Release();

	modCount = other.modCount;
	container = other.container;
	first = other.first;
	it = other.it;
	return *this;
}

//--------------------------------------------------------------------------
// Generic wrappers

void ScriptMapFactory_Generic(asIScriptGeneric *gen)
{
    *(CScriptMap**)gen->GetAddressOfReturnLocation() = new CScriptMap(gen->GetEngine());
}

void ScriptMapAddRef_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    dict->AddRef();
}

void ScriptMapRelease_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    dict->Release();
}

void ScriptMapAssign_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    CScriptMap *other = *(CScriptMap**)gen->GetAddressOfArg(0);
	*dict = *other;
	*(CScriptMap**)gen->GetAddressOfReturnLocation() = dict;
}

void ScriptMapSet_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    int typeId = gen->GetArgTypeId(1);
    dict->Set(key, ref, typeId);
}

void ScriptMapSetInt_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    dict->Set(key, *(asINT64*)ref);
}

void ScriptMapSetFlt_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    dict->Set(key, *(double*)ref);
}

void ScriptMapGet_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    int typeId = gen->GetArgTypeId(1);
    *(bool*)gen->GetAddressOfReturnLocation() = dict->Get(key, ref, typeId);
}

void ScriptMapGetInt_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    *(bool*)gen->GetAddressOfReturnLocation() = dict->Get(key, *(asINT64*)ref);
}

void ScriptMapGetFlt_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    void *ref = *(void**)gen->GetAddressOfArg(1);
    *(bool*)gen->GetAddressOfReturnLocation() = dict->Get(key, *(double*)ref);
}

void ScriptMapExists_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    bool ret = dict->Exists(key);
    *(bool*)gen->GetAddressOfReturnLocation() = ret;
}

void ScriptMapDelete_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    asINT64 key = *(asINT64*)gen->GetAddressOfArg(0);
    dict->Delete(key);
}

void ScriptMapDeleteAll_Generic(asIScriptGeneric *gen)
{
    CScriptMap *dict = (CScriptMap*)gen->GetObject();
    dict->DeleteAll();
}

static void ScriptMapGetRefCount_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	*(int*)gen->GetAddressOfReturnLocation() = self->GetRefCount();
}

static void ScriptMapSetGCFlag_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	self->SetGCFlag();
}

static void ScriptMapGetGCFlag_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	*(bool*)gen->GetAddressOfReturnLocation() = self->GetGCFlag();
}

static void ScriptMapEnumReferences_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	asIScriptEngine *engine = *(asIScriptEngine**)gen->GetAddressOfArg(0);
	self->EnumReferences(engine);
}

static void ScriptMapReleaseAllReferences_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	asIScriptEngine *engine = *(asIScriptEngine**)gen->GetAddressOfArg(0);
	self->ReleaseAllReferences(engine);
}

static void CScriptMapGetKeys_Generic(asIScriptGeneric *gen)
{
	CScriptMap *self = (CScriptMap*)gen->GetObject();
	*(CScriptArray**)gen->GetAddressOfReturnLocation() = self->GetKeys();
}

//--------------------------------------------------------------------------
// Register the type

void RegisterScriptMap(asIScriptEngine *engine)
{
	if( strstr(asGetLibraryOptions(), "AS_MAX_PORTABILITY") )
		RegisterScriptMap_Generic(engine);
	else
		RegisterScriptMap_Native(engine);
}

void RegisterScriptMap_Native(asIScriptEngine *engine)
{
	int r;

	//Register iterator type so we can use it later
	r = engine->RegisterObjectType("map_iterator", sizeof(CScriptMap::Iterator), asOBJ_VALUE | asOBJ_APP_CLASS_CDA); assert( r >= 0 );

    r = engine->RegisterObjectType("map", sizeof(CScriptMap), asOBJ_REF | asOBJ_GC); assert( r >= 0 );
	// Use the generic interface to construct the object since we need the engine pointer, we could also have retrieved the engine pointer from the active context
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_FACTORY, "map@ f()", asFUNCTION(ScriptMapFactory_Generic), asCALL_GENERIC); assert( r>= 0 );
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_ADDREF, "void f()", asMETHOD(CScriptMap,AddRef), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_RELEASE, "void f()", asMETHOD(CScriptMap,Release), asCALL_THISCALL); assert( r >= 0 );

	r = engine->RegisterObjectMethod("map", "map &opAssign(const map &in)", asMETHODPR(CScriptMap, operator=, (const CScriptMap &), CScriptMap&), asCALL_THISCALL); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "void set(int64, const ?&in)", asMETHODPR(CScriptMap,Set,(asINT64,void*,int),void), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, ?&out) const", asMETHODPR(CScriptMap,Get,(asINT64,void*,int) const,bool), asCALL_THISCALL); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "void set(int64, int64&in)", asMETHODPR(CScriptMap,Set,(asINT64,asINT64&),void), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, int64&out) const", asMETHODPR(CScriptMap,Get,(asINT64,asINT64&) const,bool), asCALL_THISCALL); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "void set(int64, double&in)", asMETHODPR(CScriptMap,Set,(asINT64,double&),void), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, double&out) const", asMETHODPR(CScriptMap,Get,(asINT64,double&) const,bool), asCALL_THISCALL); assert( r >= 0 );

	r = engine->RegisterObjectMethod("map", "bool exists(int64) const", asMETHOD(CScriptMap,Exists), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectMethod("map", "bool isEmpty() const", asMETHOD(CScriptMap, IsEmpty), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectMethod("map", "uint getSize() const", asMETHOD(CScriptMap, GetSize), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void delete(int64)", asMETHODPR(CScriptMap, Delete, (asINT64), void), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void delete(map_iterator&)", asMETHODPR(CScriptMap, Delete, (CScriptMap::Iterator&), void), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void deleteAll()", asMETHOD(CScriptMap,DeleteAll), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void deleteNulls()", asMETHOD(CScriptMap,DeleteNulls), asCALL_THISCALL); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "map_iterator iterator()", asMETHOD(CScriptMap,GetIterator), asCALL_THISCALL); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "array<int64> @getKeys() const", asMETHOD(CScriptMap,GetKeys), asCALL_THISCALL); assert( r >= 0 );

	// Register GC behaviours
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_GETREFCOUNT, "int f()", asMETHOD(CScriptMap,GetRefCount), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_SETGCFLAG, "void f()", asMETHOD(CScriptMap,SetGCFlag), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_GETGCFLAG, "bool f()", asMETHOD(CScriptMap,GetGCFlag), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_ENUMREFS, "void f(int&in)", asMETHOD(CScriptMap,EnumReferences), asCALL_THISCALL); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_RELEASEREFS, "void f(int&in)", asMETHOD(CScriptMap,ReleaseAllReferences), asCALL_THISCALL); assert( r >= 0 );

#if AS_USE_STLNAMES == 1
	// Same as isEmpty
	r = engine->RegisterObjectMethod("map", "bool empty() const", asMETHOD(CScriptMap, IsEmpty), asCALL_THISCALL); assert( r >= 0 );
	// Same as getSize
	r = engine->RegisterObjectMethod("map", "uint size() const", asMETHOD(CScriptMap, GetSize), asCALL_THISCALL); assert( r >= 0 );
	// Same as delete
    r = engine->RegisterObjectMethod("map", "void erase(asINT64 in)", asMETHOD(CScriptMap,Delete), asCALL_THISCALL); assert( r >= 0 );
	// Same as deleteAll
	r = engine->RegisterObjectMethod("map", "void clear()", asMETHOD(CScriptMap,DeleteAll), asCALL_THISCALL); assert( r >= 0 );
#endif

	// Register iterator methods
    r = engine->RegisterObjectBehaviour("map_iterator", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(DefaultConstructIterator), asCALL_CDECL_OBJFIRST); assert( r>= 0 );
    r = engine->RegisterObjectBehaviour("map_iterator", asBEHAVE_CONSTRUCT, "void f(const map &in)", asFUNCTION(ConstructIterator), asCALL_CDECL_OBJFIRST); assert( r>= 0 );
    r = engine->RegisterObjectBehaviour("map_iterator", asBEHAVE_DESTRUCT, "void f()", asFUNCTION(DestructIterator), asCALL_CDECL_OBJFIRST); assert( r>= 0 );

	r = engine->RegisterObjectMethod("map_iterator", "int64 get_key()", asMETHOD(CScriptMap::Iterator, GetKey), asCALL_THISCALL); assert( r>= 0 );
	r = engine->RegisterObjectMethod("map_iterator", "bool iterate(?&out)", asMETHODPR(CScriptMap::Iterator, Iterate, (void*,int), bool), asCALL_THISCALL); assert( r>= 0 );
	r = engine->RegisterObjectMethod("map_iterator", "bool iterate(int64 &out, ?&out)", asMETHODPR(CScriptMap::Iterator, Iterate, (asINT64*,void*,int), bool), asCALL_THISCALL); assert( r>= 0 );
	r = engine->RegisterObjectMethod("map_iterator", "bool get_valid()", asMETHOD(CScriptMap::Iterator, IsValid), asCALL_THISCALL); assert( r>= 0 );
	r = engine->RegisterObjectMethod("map_iterator", "map_iterator& opAssign(const map_iterator &in)", asMETHOD(CScriptMap::Iterator, operator=), asCALL_THISCALL); assert( r>= 0 );
}

void RegisterScriptMap_Generic(asIScriptEngine *engine)
{
    int r;

    r = engine->RegisterObjectType("map", sizeof(CScriptMap), asOBJ_REF | asOBJ_GC); assert( r >= 0 );
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_FACTORY, "map@ f()", asFUNCTION(ScriptMapFactory_Generic), asCALL_GENERIC); assert( r>= 0 );
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_ADDREF, "void f()", asFUNCTION(ScriptMapAddRef_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectBehaviour("map", asBEHAVE_RELEASE, "void f()", asFUNCTION(ScriptMapRelease_Generic), asCALL_GENERIC); assert( r >= 0 );

	r = engine->RegisterObjectMethod("map", "map &opAssign(const map &in)", asFUNCTION(ScriptMapAssign_Generic), asCALL_GENERIC); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "void set(int64, ?&in)", asFUNCTION(ScriptMapSet_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, ?&out) const", asFUNCTION(ScriptMapGet_Generic), asCALL_GENERIC); assert( r >= 0 );
    
    r = engine->RegisterObjectMethod("map", "void set(int64, int64&in)", asFUNCTION(ScriptMapSetInt_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, int64&out) const", asFUNCTION(ScriptMapGetInt_Generic), asCALL_GENERIC); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "void set(int64, double&in)", asFUNCTION(ScriptMapSetFlt_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "bool get(int64, double&out) const", asFUNCTION(ScriptMapGetFlt_Generic), asCALL_GENERIC); assert( r >= 0 );

	r = engine->RegisterObjectMethod("map", "bool exists(asINT64 in) const", asFUNCTION(ScriptMapExists_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void delete(asINT64 in)", asFUNCTION(ScriptMapDelete_Generic), asCALL_GENERIC); assert( r >= 0 );
    r = engine->RegisterObjectMethod("map", "void deleteAll()", asFUNCTION(ScriptMapDeleteAll_Generic), asCALL_GENERIC); assert( r >= 0 );

    r = engine->RegisterObjectMethod("map", "array<int64> @getKeys() const", asFUNCTION(CScriptMapGetKeys_Generic), asCALL_GENERIC); assert( r >= 0 );

	// Register GC behaviours
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_GETREFCOUNT, "int f()", asFUNCTION(ScriptMapGetRefCount_Generic), asCALL_GENERIC); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_SETGCFLAG, "void f()", asFUNCTION(ScriptMapSetGCFlag_Generic), asCALL_GENERIC); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_GETGCFLAG, "bool f()", asFUNCTION(ScriptMapGetGCFlag_Generic), asCALL_GENERIC); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_ENUMREFS, "void f(int&in)", asFUNCTION(ScriptMapEnumReferences_Generic), asCALL_GENERIC); assert( r >= 0 );
	r = engine->RegisterObjectBehaviour("map", asBEHAVE_RELEASEREFS, "void f(int&in)", asFUNCTION(ScriptMapReleaseAllReferences_Generic), asCALL_GENERIC); assert( r >= 0 );
}

END_AS_NAMESPACE


