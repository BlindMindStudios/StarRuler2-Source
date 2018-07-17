#include <assert.h>
#include "scriptstdstring.h"
#include "scriptarray.h"

using namespace std;

BEGIN_AS_NAMESPACE


// This function takes an input string and splits it into parts by looking
// for a specified delimiter. Example:
//
// string str = "A|B||D";
// array<string>@ array = str.split("|");
//
// The resulting array has the following elements:
//
// {"A", "B", "", "D"}
//
// AngelScript signature:
// array<string>@ string::split(const string &in delim) const
static void StringSplit_Generic(asIScriptGeneric *gen)
{
    // Obtain a pointer to the engine
    asIScriptContext *ctx = asGetActiveContext();
    asIScriptEngine *engine = ctx->GetEngine();

    // TODO: This should only be done once
	// TODO: This assumes that CScriptArray was already registered
	asITypeInfo *arrayType = engine->GetTypeInfoById(engine->GetTypeIdByDecl("array<string>"));

    // Create the array object
    CScriptArray *array = new CScriptArray(0, arrayType);

    // Get the arguments
    string *str   = (string*)gen->GetObject();
    string *delim = *(string**)gen->GetAddressOfArg(0);

    // Find the existence of the delimiter in the input string
    int pos = 0, prev = 0, count = 0;
    while( (pos = (int)str->find(*delim, prev)) != (int)string::npos )
    {
        // Add the part to the array
        array->Resize(array->GetSize()+1);
        ((string*)array->At(count))->assign(&(*str)[prev], pos-prev);

        // Find the next part
        count++;
        prev = pos + (int)delim->length();
    }

    // Add the remaining part
    array->Resize(array->GetSize()+1);
    ((string*)array->At(count))->assign(&(*str)[prev]);

    // Return the array by handle
    *(CScriptArray**)gen->GetAddressOfReturnLocation() = array;
}



// This function takes as input an array of string handles as well as a
// delimiter and concatenates the array elements into one delimited string.
// Example:
//
// array<string> array = {"A", "B", "", "D"};
// string str = join(array, "|");
//
// The resulting string is:
//
// "A|B||D"
//
// AngelScript signature:
// string join(const array<string> &in array, const string &in delim)
static void StringJoin_Generic(asIScriptGeneric *gen)
{
    // Get the arguments
    CScriptArray  *array = *(CScriptArray**)gen->GetAddressOfArg(0);
    string *delim = *(string**)gen->GetAddressOfArg(1);

    // Create the new string
    string str = "";
	if( array->GetSize() )
	{
		int n;
		for( n = 0; n < (int)array->GetSize() - 1; n++ )
		{
			str += *(string*)array->At(n);
			str += *delim;
		}

		// Add the last part
		str += *(string*)array->At(n);
	}

    // Return the string
    new(gen->GetAddressOfReturnLocation()) string(str);
}




// This is where the utility functions are registered.
// The string type must have been registered first.
void RegisterStdStringUtils(asIScriptEngine *engine)
{
	int r;

	r = engine->RegisterObjectMethod("string", "array<string>@ split(const string &in) const", asFUNCTION(StringSplit_Generic), asCALL_GENERIC); assert(r >= 0);
	r = engine->RegisterGlobalFunction("string join(const array<string> &in, const string &in)", asFUNCTION(StringJoin_Generic), asCALL_GENERIC); assert(r >= 0);
}

END_AS_NAMESPACE
