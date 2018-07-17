#ifndef SCRIPTARRAY_H
#define SCRIPTARRAY_H

#ifndef ANGELSCRIPT_H 
// Avoid having to inform include path if header is already include before
#include <angelscript.h>
#endif

#include "../source/as_atomic.h"

// Sometimes it may be desired to use the same method names as used by C++ STL.
// This may for example reduce time when converting code from script to C++ or
// back.
//
//  0 = off
//  1 = on

#ifndef AS_USE_STLNAMES
#define AS_USE_STLNAMES 0
#endif

BEGIN_AS_NAMESPACE

struct SArrayBuffer;
struct SArrayCache;

class CScriptArray
{
public:
	CScriptArray(asITypeInfo *ot, void *initBuf); // Called from script when initialized with list
	CScriptArray(asUINT length, asITypeInfo *ot);
	CScriptArray(asUINT length, void *defVal, asITypeInfo *ot);
	CScriptArray(const CScriptArray &other);
	virtual ~CScriptArray();

	void AddRef() const;
	void Release() const;

	// Type information
	asITypeInfo *GetArrayObjectType() const;
	int            GetArrayTypeId() const;
	int            GetElementTypeId() const;

	void   Reserve(asUINT maxElements);
	void   Resize(asUINT numElements);
	asUINT GetSize() const;
	bool   IsEmpty() const;

	// Get a pointer to an element. Returns 0 if out of bounds
	void       *At(asUINT index);
	const void *At(asUINT index) const;

	// Get a pointer to the last element. Returns 0 if empty array.
	void       *Last();
	const void *Last() const;

	// Set value of an element
	void  SetValue(asUINT index, void *value);

	CScriptArray &operator=(const CScriptArray&);
	bool operator==(const CScriptArray &) const;

	void InsertAt(asUINT index, void *value);
	void RemoveAt(asUINT index);
	void InsertLast(void *value);
	void RemoveLast();
	void Remove(void *value);
	void RemoveAll(void *value);
	void SortAsc();
	void SortDesc();
	void SortAsc(asUINT index, asUINT count);
	void SortDesc(asUINT index, asUINT count);
	void Sort(asUINT index, asUINT count, bool asc);
	void Reverse();
	int  Find(void *value) const;
	int  Find(asUINT index, void *value) const;

	// GC methods
	int  GetRefCount();
	void SetFlag();
	bool GetFlag();
	void EnumReferences(asIScriptEngine *engine);
	void ReleaseAllHandles(asIScriptEngine *engine);

protected:
	mutable asCAtomic       refCount;
	mutable bool      gcFlag;
	asITypeInfo    *objType;
	SArrayBuffer     *buffer;
	int               elementSize;
	int               subTypeId;
	int               numElements;

	bool  Less(const void *a, const void *b, bool asc, asIScriptContext *ctx, SArrayCache *cache);
	void *GetArrayItemPointer(int index);
	void *GetDataPointer(void *buffer);
	void  Copy(void *dst, void *src);
	void  Precache();
	bool  CheckMaxSize(asUINT numElements);
	void  Resize(int delta, asUINT at);
	void  CreateBuffer(SArrayBuffer **buf, asUINT numElements);
	void  DeleteBuffer(SArrayBuffer *buf);
	void  CopyBuffer(SArrayBuffer *dst, SArrayBuffer *src);
	void  Construct(SArrayBuffer *buf, asUINT start, asUINT end);
	void  Destruct(SArrayBuffer *buf, asUINT start, asUINT end);
	bool  Equals(const void *a, const void *b, asIScriptContext *ctx, SArrayCache *cache) const;
};

void RegisterScriptArray(asIScriptEngine *engine, bool defaultArray);

END_AS_NAMESPACE

#endif
