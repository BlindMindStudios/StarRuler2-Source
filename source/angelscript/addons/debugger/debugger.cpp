#include "debugger.h"
#include <iostream>  // cout
#include <sstream> // stringstream

using namespace std;

CDebugger::CDebugger()
{
	m_action = CONTINUE;
	m_lastFunction = 0;
}

CDebugger::~CDebugger()
{
}

string CDebugger::ToString(void *value, asUINT typeId, bool expandMembers, asIScriptEngine *engine)
{
	stringstream s;
	if( typeId == asTYPEID_VOID )
		return "<void>";
	else if( typeId == asTYPEID_BOOL )
		return *(bool*)value ? "true" : "false";
	else if( typeId == asTYPEID_INT8 )
		s << (int)*(signed char*)value;
	else if( typeId == asTYPEID_INT16 )
		s << (int)*(signed short*)value;
	else if( typeId == asTYPEID_INT32 )
		s << *(signed int*)value;
	else if( typeId == asTYPEID_INT64 )
#if defined(_MSC_VER) && _MSC_VER <= 1200
		s << "{...}"; // MSVC6 doesn't like the << operator for 64bit integer
#else
		s << *(asINT64*)value;
#endif
	else if( typeId == asTYPEID_UINT8 )
		s << (unsigned int)*(unsigned char*)value;
	else if( typeId == asTYPEID_UINT16 )
		s << (unsigned int)*(unsigned short*)value;
	else if( typeId == asTYPEID_UINT32 )
		s << *(unsigned int*)value;
	else if( typeId == asTYPEID_UINT64 )
#if defined(_MSC_VER) && _MSC_VER <= 1200
		s << "{...}"; // MSVC6 doesn't like the << operator for 64bit integer
#else
		s << *(asQWORD*)value;
#endif
	else if( typeId == asTYPEID_FLOAT )
		s << *(float*)value;
	else if( typeId == asTYPEID_DOUBLE )
		s << *(double*)value;
	else if( (typeId & asTYPEID_MASK_OBJECT) == 0 )
	{
		// The type is an enum
		s << *(asUINT*)value;

		// Check if the value matches one of the defined enums
		for( int n = engine->GetEnumValueCount(typeId); n-- > 0; )
		{
			int enumVal;
			const char *enumName = engine->GetEnumValueByIndex(typeId, n, &enumVal);
			if( enumVal == *(int*)value )
			{
				s << ", " << enumName;
				break;
			}
		}
	}
	else if( typeId & asTYPEID_SCRIPTOBJECT )
	{
		// Dereference handles, so we can see what it points to
		if( typeId & asTYPEID_OBJHANDLE )
			value = *(void**)value;

		asIScriptObject *obj = (asIScriptObject *)value;

		s << "{" << obj << "}";

		if( obj && expandMembers )
		{
			asIObjectType *type = obj->GetObjectType();
			for( int n = 0; n < obj->GetPropertyCount(); n++ )
			{
				s << endl << "  " << type->GetPropertyDeclaration(n) << " = " << ToString(obj->GetAddressOfProperty(n), obj->GetPropertyTypeId(n), false, engine);
			}
		}
	}
	else
	{
		// Dereference handles, so we can see what it points to
		if( typeId & asTYPEID_OBJHANDLE )
			value = *(void**)value;

		// TODO: Value types can have their properties expanded by default
		
		// Just print the address
		s << "{" << value << "}";
	}

	return s.str();
}

void CDebugger::LineCallback(asIScriptContext *ctx)
{
	if( m_action == CONTINUE )
	{
		if( !CheckBreakPoint(ctx) )
			return;
	}
	else if( m_action == STEP_OVER )
	{
		if( ctx->GetCallstackSize() > m_lastCommandAtStackLevel )
		{
			if( !CheckBreakPoint(ctx) )
				return;
		}
	}
	else if( m_action == STEP_OUT )
	{
		if( ctx->GetCallstackSize() >= m_lastCommandAtStackLevel )
		{
			if( !CheckBreakPoint(ctx) )
				return;
		}
	}
	else if( m_action == STEP_INTO )
	{
		CheckBreakPoint(ctx);

		// Always break, but we call the check break point anyway 
		// to tell user when break point has been reached
	}

	stringstream s;
	const char *file;
	int lineNbr = ctx->GetLineNumber(0, 0, &file);
	s << file << ":" << lineNbr << "; " << ctx->GetFunction()->GetDeclaration() << endl;
	Output(s.str());

	TakeCommands(ctx);
}

bool CDebugger::CheckBreakPoint(asIScriptContext *ctx)
{
	// TODO: Should cache the break points in a function by checking which possible break points
	//       can be hit when entering a function. If there are no break points in the current function
	//       then there is no need to check every line.

	const char *tmp = 0;
	int lineNbr = ctx->GetLineNumber(0, 0, &tmp);

	// Consider just filename, not the full path
	string file = tmp;
	size_t r = file.find_last_of("\\/");
	if( r != string::npos )
		file = file.substr(r+1);

	// Did we move into a new function?
	asIScriptFunction *func = ctx->GetFunction();
	if( m_lastFunction != func )
	{
		// Check if any breakpoints need adjusting
		for( size_t n = 0; n < breakPoints.size(); n++ )
		{
			// We need to check for a breakpoint at entering the function
			if( breakPoints[n].func )
			{
				if( breakPoints[n].name == func->GetName() )
				{
					stringstream s;
					s << "Entering function '" << breakPoints[n].name << "'. Transforming it into break point" << endl;
					Output(s.str());

					// Transform the function breakpoint into a file breakpoint
					breakPoints[n].name           = file;
					breakPoints[n].lineNbr        = lineNbr;
					breakPoints[n].func           = false;
					breakPoints[n].needsAdjusting = false;
				}
			}
			// Check if a given breakpoint fall on a line with code or else adjust it to the next line
			else if( breakPoints[n].needsAdjusting &&
					 breakPoints[n].name == file )
			{
				int line = func->FindNextLineWithCode(breakPoints[n].lineNbr);
				if( line >= 0 )
				{
					stringstream s;
					s << "Moving break point " << n << " in file '" << file << "' to next line with code at line " << line << endl;
					Output(s.str());

					// Move the breakpoint to the next line
					breakPoints[n].needsAdjusting = false;
					breakPoints[n].lineNbr = line;
				}
			}
		}
	}
	m_lastFunction = func;

	// Determine if there is a breakpoint at the current line
	for( size_t n = 0; n < breakPoints.size(); n++ )
	{
		// TODO: do case-less comparison for file name

		// Should we break?
		if( !breakPoints[n].func &&
			breakPoints[n].lineNbr == lineNbr &&
			breakPoints[n].name == file )
		{
			stringstream s;
			s << "Reached break point " << n << " in file '" << file << "' at line " << lineNbr << endl;
			Output(s.str());
			return true;
		}
	}

	return false;
}

void CDebugger::TakeCommands(asIScriptContext *ctx)
{
	for(;;)
	{
		char buf[512];

		Output("[dbg]> ");
		cin.getline(buf, 512);

		if( InterpretCommand(string(buf), ctx) )
			break;
	}
}

bool CDebugger::InterpretCommand(const string &cmd, asIScriptContext *ctx)
{
	if( cmd.length() == 0 ) return true;

	switch( cmd[0] )
	{
	case 'c':
		m_action = CONTINUE;
		break;

	case 's':
		m_action = STEP_INTO;
		break;

	case 'n':
		m_action = STEP_OVER;
		m_lastCommandAtStackLevel = ctx->GetCallstackSize();
		break;

	case 'o':
		m_action = STEP_OUT;
		m_lastCommandAtStackLevel = ctx->GetCallstackSize();
		break;

	case 'b':
		{
			// Set break point
			size_t div = cmd.find(':'); 
			if( div != string::npos && div > 2 )
			{
				string file = cmd.substr(2, div-2);
				string line = cmd.substr(div+1);

				int nbr = atoi(line.c_str());

				AddFileBreakPoint(file, nbr);
			}
			else if( div == string::npos && (div = cmd.find_first_not_of(" \t", 1)) != string::npos )
			{
				string func = cmd.substr(div);

				AddFuncBreakPoint(func);
			}
			else
			{
				Output("Incorrect format for setting break point, expected one of:\n"
				       "b <file name>:<line number>\n"
				       "b <function name>\n");
			}
		}
		// take more commands
		return false;

	case 'r':
		{
			// Remove break point
			if( cmd.length() > 2 )
			{
				string br = cmd.substr(2);
				if( br == "all" )
				{
					breakPoints.clear();
					Output("All break points have been removed\n");
				}
				else
				{
					int nbr = atoi(br.c_str());
					if( nbr >= 0 && nbr < (int)breakPoints.size() )
						breakPoints.erase(breakPoints.begin()+nbr);
					ListBreakPoints();
				}
			}
			else
			{
				Output("Incorrect format for removing break points, expected:\n"
				       "r <all|number of break point>\n");
			}
		}
		// take more commands
		return false;

	case 'l':
		{
			// List something
			size_t p = cmd.find_first_not_of(" \t", 1);
			if( p != string::npos )
			{
				if( cmd[p] == 'b' )
				{
					ListBreakPoints();
				}
				else if( cmd[p] == 'v' )
				{
					ListLocalVariables(ctx);
				}
				else if( cmd[p] == 'g' )
				{
					ListGlobalVariables(ctx);
				}
				else if( cmd[p] == 'm' )
				{
					ListMemberProperties(ctx);
				}
				else if( cmd[p] == 's' )
				{
					ListStatistics(ctx);
				}
				else
				{
					Output("Unknown list option, expected one of:\n"
					       "b - breakpoints\n"
					       "v - local variables\n"
						   "m - member properties\n"
					       "g - global variables\n"
						   "s - statistics\n");
				}
			}
			else 
			{
				Output("Incorrect format for list, expected:\n"
				       "l <list option>\n");
			}
		}
		// take more commands
		return false;

	case 'h':
		PrintHelp();
		// take more commands
		return false;

	case 'p':
		{
			// Print a value 
			size_t p = cmd.find_first_not_of(" \t", 1);
			if( p != string::npos )
			{
				PrintValue(cmd.substr(p), ctx);
			}
			else
			{
				Output("Incorrect format for print, expected:\n"
					   "p <expression>\n");
			}
		}
		// take more commands
		return false;

	case 'w':
		// Where am I?
		PrintCallstack(ctx);
		// take more commands
		return false;

	case 'a':
		// abort the execution
		ctx->Abort();
		break;

	default:
		Output("Unknown command\n");
		// take more commands
		return false;
	}

	// Continue execution
	return true;
}

void CDebugger::PrintValue(const std::string &expr, asIScriptContext *ctx)
{
	asIScriptEngine *engine = ctx->GetEngine();

	int len;
	asETokenClass t = engine->ParseToken(expr.c_str(), 0, &len);

	// TODO: If the expression starts with :: we should only look for global variables
	if( t == asTC_IDENTIFIER )
	{
		string name(expr.c_str(), len);

		// Find the variable
		void *ptr = 0;
		int typeId;

		asIScriptFunction *func = ctx->GetFunction();
		if( !func ) return;

		// We start from the end, in case the same name is reused in different scopes
		for( asUINT n = func->GetVarCount(); n-- > 0; )
		{
			if( ctx->IsVarInScope(n) && name == ctx->GetVarName(n) )
			{
				ptr = ctx->GetAddressOfVar(n);
				typeId = ctx->GetVarTypeId(n);
				break;
			}
		}

		// Look for class members, if we're in a class method
		if( !ptr && func->GetObjectType() )
		{
			if( name == "this" )
			{
				ptr = ctx->GetThisPointer();
				typeId = ctx->GetThisTypeId();
			}
			else
			{
				asIObjectType *type = engine->GetObjectTypeById(ctx->GetThisTypeId());
				for( asUINT n = 0; n < type->GetPropertyCount(); n++ )
				{
					const char *propName = 0;
					int offset = 0;
					bool isReference = 0;
					type->GetProperty(n, &propName, &typeId, 0, &offset, &isReference);
					if( name == propName )
					{
						ptr = (void*)(((asBYTE*)ctx->GetThisPointer())+offset);
						if( isReference ) ptr = *(void**)ptr;
						break;
					}
				}
			}
		}

		// Look for global variables
		if( !ptr )
		{
			asIScriptModule *mod = ctx->GetEngine()->GetModule(func->GetModuleName(), asGM_ONLY_IF_EXISTS);
			if( mod )
			{
				for( asUINT n = 0; n < mod->GetGlobalVarCount(); n++ )
				{
					const char *varName = 0;
					mod->GetGlobalVar(n, &varName, &typeId);
					if( name == varName )
					{
						ptr = mod->GetAddressOfGlobalVar(n);
						break;
					}
				}
			}
		}

		if( ptr )
		{
			// TODO: If there is a . after the identifier, check for members

			stringstream s;
			s << ToString(ptr, typeId, true, engine) << endl;
			Output(s.str());
		}
	}
	else
	{
		Output("Invalid expression. Expected identifier\n");
	}
}

void CDebugger::ListBreakPoints()
{
	// List all break points
	stringstream s;
	for( size_t b = 0; b < breakPoints.size(); b++ )
		if( breakPoints[b].func )
			s << b << " - " << breakPoints[b].name << endl;
		else
			s << b << " - " << breakPoints[b].name << ":" << breakPoints[b].lineNbr << endl;
	Output(s.str());
}

void CDebugger::ListMemberProperties(asIScriptContext *ctx)
{
	void *ptr = ctx->GetThisPointer();
	if( ptr )
	{
		stringstream s;
		s << "this = " << ToString(ptr, ctx->GetThisTypeId(), true, ctx->GetEngine()) << endl;
		Output(s.str());
	}
}

void CDebugger::ListLocalVariables(asIScriptContext *ctx)
{
	asIScriptFunction *func = ctx->GetFunction();
	if( !func ) return;

	stringstream s;
	for( asUINT n = 0; n < func->GetVarCount(); n++ )
	{
		if( ctx->IsVarInScope(n) )
			s << func->GetVarDecl(n) << " = " << ToString(ctx->GetAddressOfVar(n), ctx->GetVarTypeId(n), false, ctx->GetEngine()) << endl;
	}
	Output(s.str());
}

void CDebugger::ListGlobalVariables(asIScriptContext *ctx)
{
	// Determine the current module from the function
	asIScriptFunction *func = ctx->GetFunction();
	if( !func ) return;

	asIScriptModule *mod = ctx->GetEngine()->GetModule(func->GetModuleName(), asGM_ONLY_IF_EXISTS);
	if( !mod ) return;

	stringstream s;
	for( asUINT n = 0; n < mod->GetGlobalVarCount(); n++ )
	{
		int typeId;
		mod->GetGlobalVar(n, 0, &typeId);
		s << mod->GetGlobalVarDeclaration(n) << " = " << ToString(mod->GetAddressOfGlobalVar(n), typeId, false, ctx->GetEngine()) << endl;
	}
	Output(s.str());
}

void CDebugger::ListStatistics(asIScriptContext *ctx)
{
	asIScriptEngine *engine = ctx->GetEngine();
	
	asUINT gcCurrSize, gcTotalDestr, gcTotalDet, gcNewObjects, gcTotalNewDestr;
	engine->GetGCStatistics(&gcCurrSize, &gcTotalDestr, &gcTotalDet, &gcNewObjects, &gcTotalNewDestr);

	stringstream s;
	s << "Garbage collector:" << endl;
	s << " current size:          " << gcCurrSize << endl;
	s << " total destroyed:       " << gcTotalDestr << endl;
	s << " total detected:        " << gcTotalDet << endl;
	s << " new objects:           " << gcNewObjects << endl;
	s << " new objects destroyed: " << gcTotalNewDestr << endl;

	Output(s.str());
}

void CDebugger::PrintCallstack(asIScriptContext *ctx)
{
	stringstream s;
	const char *file;
	int lineNbr;
	for( asUINT n = 0; n < ctx->GetCallstackSize(); n++ )
	{
		lineNbr = ctx->GetLineNumber(n, 0, &file);
		s << file << ":" << lineNbr << "; " << ctx->GetFunction(n)->GetDeclaration() << endl;
	}
	Output(s.str());
}

void CDebugger::AddFuncBreakPoint(const string &func)
{
	// Trim the function name
	size_t b = func.find_first_not_of(" \t");
	size_t e = func.find_last_not_of(" \t");
	string actual = func.substr(b, e != string::npos ? e-b+1 : string::npos);

	stringstream s;
	s << "Adding deferred break point for function '" << actual << "'" << endl;
	Output(s.str());

	BreakPoint bp(actual, 0, true);
	breakPoints.push_back(bp);
}

void CDebugger::AddFileBreakPoint(const string &file, int lineNbr)
{
	// Store just file name, not entire path
	size_t r = file.find_last_of("\\/");
	string actual;
	if( r != string::npos )
		actual = file.substr(r+1);
	else
		actual = file;

	// Trim the file name
	size_t b = actual.find_first_not_of(" \t");
	size_t e = actual.find_last_not_of(" \t");
	actual = actual.substr(b, e != string::npos ? e-b+1 : string::npos);

	stringstream s;
	s << "Setting break point in file '" << actual << "' at line " << lineNbr << endl;
	Output(s.str());

	BreakPoint bp(actual, lineNbr, false);
	breakPoints.push_back(bp);
}

void CDebugger::PrintHelp()
{
	Output("c - Continue\n"
	       "s - Step into\n"
	       "n - Next step\n"
	       "o - Step out\n"
	       "b - Set break point\n"
	       "l - List various things\n"
	       "r - Remove break point\n"
	       "p - Print value\n"
	       "w - Where am I?\n"
	       "a - Abort execution\n"
	       "h - Print this help text\n");
}

void CDebugger::Output(const string &str)
{
	// By default we just output to stdout
	cout << str;
}