#pragma once
#include <string>
#include <vector>

namespace render {

class ShaderProgram {
public:
	virtual int compile() = 0;
	virtual ~ShaderProgram() {}
};

class Shader {
public:
	ShaderProgram* program;

	enum VarType {
		VT_invalid = 0,
		VT_int,
		VT_int2,
		VT_int3,
		VT_int4,
		VT_float,
		VT_float2,
		VT_float3,
		VT_float4,
		VT_mat3
	};

	struct Variable {
		VarType type : 16;
		unsigned short count : 16;
		union {
			mutable int* _ints;
			mutable float* _floats;
		};
		union {
			mutable void* _args;
		};
		union {
			void (*_intcall)(int*,unsigned short,void*);
			void (*_floatcall)(float*,unsigned short,void*);
		};
		bool constant;
		
		Variable() : type(VT_invalid), count(0), _ints(0), _args(0), _intcall(0), constant(true) {}
		Variable(VarType Type, unsigned short Count) : type(Type), count(Count), _args(0), _intcall(0), constant(true) {
			switch(Type) {
			case VT_int:
				_ints = new int[Count*1]; break;
			case VT_int2:
				_ints = new int[Count*2]; break;
			case VT_int3:
				_ints = new int[Count*3]; break;
			case VT_int4:
				_ints = new int[Count*4]; break;
			case VT_float:
				_floats = new float[Count*1]; break;
			case VT_float2:
				_floats = new float[Count*2]; break;
			case VT_float3:
				_floats = new float[Count*3]; break;
			case VT_float4:
				_floats = new float[Count*4]; break;
			case VT_mat3:
				_floats = new float[Count*9]; break;
			case VT_invalid:
				break;
			}
		}
	};

	std::vector<Variable> vars;
	unsigned dynamicFloats;

	//Whether the shader's inputs are constant across a frame
	bool constant;

	virtual int compile() = 0;

	virtual void addVariable(const std::string& name, const Variable& var) {
		vars.push_back(var);
		if(!var.constant) {
			constant = false;
			switch(var.type) {
				case VT_int:
				case VT_float:
					dynamicFloats += var.count; break;
				case VT_int2:
				case VT_float2:
					dynamicFloats += 2 * var.count; break;
				case VT_int3:
				case VT_float3:
					dynamicFloats += 3 * var.count; break;
				case VT_int4:
				case VT_float4:
					dynamicFloats += 4 * var.count; break;
				case VT_invalid:
					break;
			}
		}
	}

	virtual void bind(float* dynamicBuffer) const = 0;
	virtual void updateDynamicVars() const = 0;
	virtual void saveDynamicVars(float* buffer) const = 0;
	virtual void loadDynamicVars(float* buffer) const = 0;

	virtual ~Shader() {}
};
	
};
