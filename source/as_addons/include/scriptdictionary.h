#ifndef SCRIPTDICTIONARY_H
#define SCRIPTDICTIONARY_H

// The dictionary class relies on the script string object, thus the script
// string type must be registered with the engine before registering the
// dictionary type

#ifndef ANGELSCRIPT_H 
// Avoid having to inform include path if header is already include before
#include <angelscript.h>
#endif

#include "../source/as_atomic.h"

#include <string>

#ifdef _MSC_VER
// Turn off annoying warnings about truncated symbol names
#pragma warning (disable:4786)
#endif

#if __cplusplus >= 201103
#include <unordered_map>
#else
#include <map>
#endif

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

class CScriptArray;

class CScriptDictionary
{
protected:
	// The structure for holding the values
    struct valueStruct
    {
        union
        {
            asINT64 valueInt;
            double  valueFlt;
            void   *valueObj;
        };
        int   typeId;
    };

	// The type of the internal map
#if __cplusplus >= 201103
	typedef std::unordered_map<std::string, valueStruct> mapType;
#else
	typedef std::map<std::string, valueStruct> mapType;
#endif

public:
    // Memory management
    CScriptDictionary(asIScriptEngine *engine);
    void AddRef() const;
    void Release() const;

    CScriptDictionary &operator =(const CScriptDictionary &other);

    // Sets/Gets a variable type value for a key
    void Set(const std::string &key, void *value, int typeId);
    bool Get(const std::string &key, void *value, int typeId) const;

    // Sets/Gets an integer number value for a key
    void Set(const std::string &key, asINT64 &value);
    bool Get(const std::string &key, asINT64 &value) const;

    // Sets/Gets a real number value for a key
    void Set(const std::string &key, double &value);
    bool Get(const std::string &key, double &value) const;

    // Returns true if the key is set
    bool Exists(const std::string &key) const;
	bool IsEmpty() const;
	asUINT GetSize() const;

    // Deletes the key
    void Delete(const std::string &key);

    // Deletes all keys
    void DeleteAll();

	// Deletes all keys that have null reference values
	void DeleteNulls();

	// Get an array of all keys
	CScriptArray *GetKeys() const;

	// Garbage collections behaviours
	int GetRefCount();
	void SetGCFlag();
	bool GetGCFlag();
	void EnumReferences(asIScriptEngine *engine);
	void ReleaseAllReferences(asIScriptEngine *engine);

	// An iterator type to wrap for script iteration
	struct Iterator
	{
	public:
		// Returns the key of the current element or
		// an error string if the iterator is at the end
		const std::string &GetKey();

		// Get the value of the current element
		// Returns true if the value is of the correct type and
		// the iterator is not at the end
		bool Iterate(void *value, int typeId);
		bool Iterate(std::string* key, void *value, int typeId);

		// Returns whether the iterator is not at
		// the end yet
		bool IsValid();

		// Copy the iterator
		Iterator &operator =(const Iterator &other);

		Iterator();
		Iterator(const CScriptDictionary *container);
		~Iterator();

		friend CScriptDictionary;
	protected:
		bool first;
		asUINT modCount;
		const CScriptDictionary *container;
		mapType::const_iterator it;
	};

	// Returns an iterator
	Iterator GetIterator() const;

	// Delete the current element of an iterator
	void Delete(Iterator& it);

protected:
	// We don't want anyone to call the destructor directly, it should be called through the Release method
	virtual ~CScriptDictionary();

	// Helper methods
    void FreeValue(valueStruct &value);
	bool Iterator_GetValue(mapType::const_iterator &it, void *value, int typeId) const;
	
	// Our properties
    asIScriptEngine *engine;
    mutable asCAtomic refCount;
	mutable bool gcFlag;

	// Whenever we erase or insert a new key, we increment the modification count.
	// Iterators check whether the modification count has changed, and will fail
	// when it has. This makes iterator-based iteration safe for scripts.
	asUINT modCount;

    mapType dict;
};

// This function will determine the configuration of the engine
// and use one of the two functions below to register the dictionary object
void RegisterScriptDictionary(asIScriptEngine *engine);

// Call this function to register the math functions
// using native calling conventions
void RegisterScriptDictionary_Native(asIScriptEngine *engine);

// Use this one instead if native calling conventions
// are not supported on the target platform
void RegisterScriptDictionary_Generic(asIScriptEngine *engine);

END_AS_NAMESPACE

#endif
