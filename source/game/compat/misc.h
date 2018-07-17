#pragma once
#if defined(_MSC_VER)
 #ifdef _DEBUG
  #define NO_DEFAULT default: throw 0;
  #define UNREACHABLE throw 0;
 #else
  #define NO_DEFAULT default: __assume(0);
  #define UNREACHABLE __assume(0);
 #endif
#else
#ifdef _DEBUG
 #define NO_DEFAULT default: throw 0;
 #define UNREACHABLE throw 0;
#else
 #define NO_DEFAULT default: __builtin_unreachable();
 #define UNREACHABLE __builtin_unreachable();
#endif
#endif

#define foreach(var, cont) for(auto var = cont.begin(), end = cont.end(); var != end; ++var)

#ifdef WIN_MODE
#define unsigned_enum(name) enum name : unsigned
#else
#ifdef LIN_MODE
#define unsigned_enum(name) enum name
#endif
#endif

#define umap std::unordered_map
#define uset std::unordered_set

#define INIT_FUNC(name) namespace __init__##name { struct init { init()

#define INIT_FUNC_END } v; };

#define INIT_VAR(var) var; namespace __init__##var { struct init { init()

#define INIT_VAR_END } v; };
