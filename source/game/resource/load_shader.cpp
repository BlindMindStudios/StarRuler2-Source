#include "main/references.h"
#include "main/initialization.h"
#include "main/logging.h"
#include "render/render_state.h"
#include "render/shader.h"
#include "resource/library.h"
#include "str_util.h"
#include "num_util.h"
#include <iostream>
#include <fstream>
#include <string>
#include "util/random.h"

#include "files.h"
#include <set>

//External shader uniform handlers
extern void shader_frameTime(float*,unsigned short,void*);
extern void shader_gameTime(float*,unsigned short,void*);
extern void shader_frameTime_cycle(float*,unsigned short,void*);
extern void shader_gameTime_cycle(float*,unsigned short,void*);
extern void shader_frameTime_cycle_abs(float*,unsigned short,void*);
extern void shader_gameTime_cycle_abs(float*,unsigned short,void*);
extern void shader_pixelRatio(float*,unsigned short,void*);
extern void shader_sprite_pos(float*,unsigned short,void*);

extern void shader_skin_margin_src(float*,unsigned short,void*);
extern void shader_skin_margin_dest(float*,unsigned short,void*);
extern void shader_skin_src_pos(float*,unsigned short,void*);
extern void shader_skin_src_size(float*,unsigned short,void*);
extern void shader_skin_dst_size(float*,unsigned short,void*);
extern void shader_skin_mode(float*,unsigned short,void*);
extern void shader_skin_gradientCount(float*,unsigned short,void*);
extern void shader_skin_gradientMode(float*,unsigned short,void*);
extern void shader_skin_gradientRects(float*,unsigned short,void*);
extern void shader_skin_gradientCols(float*,unsigned short,void*);

extern void shader_unique(float* values,unsigned short,void*);
extern void shader_node_color(float*,unsigned short,void*);
extern void shader_node_distance(float*,unsigned short,void*);
extern void shader_node_scale(float*,unsigned short,void*);
extern void shader_node_selected(float*,unsigned short,void*);
extern void shader_emp_flag(int*,unsigned short,void*);
extern void shader_obj_velocity(float*,unsigned short,void*);
extern void shader_obj_position(float*,unsigned short,void*);
extern void shader_obj_rotation(float*,unsigned short,void*);
extern void shader_node_position(float*,unsigned short,void*);
extern void shader_node_rotation(float*,unsigned short,void*);
extern void shader_obj_id(int*,unsigned short,void*);
extern void shader_obj_acceleration(float*,unsigned short,void*);

extern void shader_plane_minrad(float*,unsigned short,void*);
extern void shader_plane_maxrad(float*,unsigned short,void*);

extern void shader_tex_size(float*,unsigned short,void*);
extern void shader_light_radius(float*,unsigned short,void*);
extern void shader_light_position(float*,unsigned short,void*);
extern void shader_light_screen(float*,unsigned short,void*);
extern void shader_light_active(float*,unsigned short,void*);

extern unsigned registerVar(const std::string& name);
extern void shader_statevars(float*,unsigned short,void*);

extern void shader_quadrant_damage(float*,unsigned short,void*);

void shader_invView(float* mat,unsigned short,void*) {
	devices.render->getInverseView(mat);
}

void shader_random(float* values,unsigned short,void*) {
	values[0] = randomf();
}

namespace resource {

ShaderGlobal::ShaderGlobal() : type(render::Shader::VT_invalid), size(0), ptr(0), arraySize(1) {
}

std::unordered_map<std::string, ShaderGlobal*> shaderGlobals;

void shader_global(float* out, unsigned short n, void* args) {
	ShaderGlobal* glob = (ShaderGlobal*)args;
	memcpy(out, glob->ptr, glob->size);
}

void loadToInts(int* ints, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, ++ints)
		*ints = atoi(from->c_str());
}

void loadToInt2s(int* ints, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, ints += 2)
		sscanf(from->c_str(),"<%d,%d>",ints,ints+1);
}

void loadToInt3s(int* ints, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, ints += 3)
		sscanf(from->c_str(),"<%d,%d,%d>",ints,ints+1,ints+2);
}

void loadToInt4s(int* ints, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, ints += 4)
		sscanf(from->c_str(),"<%d,%d,%d,%d>",ints,ints+1,ints+2,ints+3);
}

void loadToFloats(float* floats, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, ++floats)
		*floats = (float)atof(from->c_str());
}

void loadToFloat2s(float* floats, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, floats += 2)
		sscanf(from->c_str(),"<%f,%f>",floats,floats+1);
}

void loadToFloat3s(float* floats, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, floats += 3)
		sscanf(from->c_str(),"<%f,%f,%f>",floats,floats+1,floats+2);
}

void loadToFloat4s(float* floats, std::vector<std::string>::iterator from, std::vector<std::string>::iterator to) {
	for(; from != to; ++from, floats += 4)
		sscanf(from->c_str(),"<%f,%f,%f,%f>",floats,floats+1,floats+2,floats+3);
}

void Library::compileShaders() {
	foreach(program,programs) {
		int result = program->second->compile();
		if(result != 0)
			error("-In Shader Program '%s'", program->first.c_str());
	}

	foreach(shader,shaders) {
		int result = shader->second->compile();
		if(result != 0)
			error("-In Shader '%s'", shader->first.c_str());
	}
}

void Library::clearShaderGlobals() {
	foreach(it, shaderGlobals) {
		free(it->second->ptr);
		delete it->second;
	}
	shaderGlobals.clear();
}

void Library::iterateShaderGlobals(std::function<void(std::string&,resource::ShaderGlobal*)> func) {
	foreach(it, shaderGlobals)
		func(it->second->name, it->second);
}

void Library::loadShaders(const std::string& filename) {
	render::Shader* shader = 0;

	std::vector<render::Shader::Variable> vars;
	std::string vertex_file;
	std::string fragment_file;

	DataHandler datahandler;

	bool activeBlock = true, anyBlockActive = false;

	int shaderLevel = 3;
	auto* sl = devices.settings.engine.getSetting("iShaderLevel");
	if(sl)
		shaderLevel = sl->getInteger();

	auto BuildShader = [&]() {
		if(!shader)
			return;

		auto progName = vertex_file + "|" + fragment_file;
		auto p = programs.find(progName);
		if(p != programs.end()) {
			shader->program = p->second;
			return;
		}
		
		render::ShaderProgram* program = 0;

		if(load_resources)
			program = devices.render->createShaderProgram(vertex_file.c_str(), fragment_file.c_str());

		shader->program = program;
		programs[progName] = program;

		if(watch_resources) {
			watchShader(progName, vertex_file);
			watchShader(progName, fragment_file);
		}

		fragment_file.clear();
		vertex_file.clear();
	};

	datahandler.controlHandler([&](std::string& line) -> bool {
		if(!line.empty() && line[0] == '#') {
			if(line.compare(0, 6, "#endif") == 0) {
				activeBlock = true;
				anyBlockActive = false;
				return false;
			}
			else if(line.compare(0, 5, "#else") == 0) {
				activeBlock = !anyBlockActive;
				anyBlockActive = true;
				return false;
			}
			else {
				std::string control, condition;
				if(splitKeyValue(line, control, condition, " ")) {
					if(control == "#if" || control == "#elif") {
						if(anyBlockActive) {
							activeBlock = false;
						}
						else {
							bool enterBlock = false;
							if(condition == "fallback") {
								auto* fallback = devices.settings.engine.getSetting("bShaderFallback");
								if(fallback)
									enterBlock = *fallback;
							}
							else if(condition == "low") {
								enterBlock = shaderLevel == 1;
							}
							else if(condition == "medium") {
								enterBlock = shaderLevel == 2;
							}
							else if(condition == "high") {
								enterBlock = shaderLevel == 3;
							}
							else if(condition == "extreme") {
								enterBlock = shaderLevel == 4;
							}
							else {
								activeBlock = toBool(condition);
							}
							activeBlock = enterBlock;
							anyBlockActive = activeBlock;
						}
						return false;
					}
				}
			}
			error("Unrecognized directive %s", line.c_str());
			return false;
		}
		return activeBlock;
	});

	datahandler("Shader", [&](std::string& value) {
		fragment_file.clear();
		vertex_file.clear();

		if(shaders.find(value) != shaders.end()) {
			shader = 0;
			error("Duplicate shader entry '%s'", value.c_str());
			return;
		}
		shader = devices.render->createShader();
		shaders[value] = shader;
	});

	datahandler("Vertex", [&](std::string& value) {
		vertex_file = devices.mods.resolve(value);

		if(!fragment_file.empty())
			BuildShader();
	});

	datahandler("Fragment", [&](std::string& value) {
		fragment_file = devices.mods.resolve(value);

		if(!vertex_file.empty())
			BuildShader();
	});

	datahandler("Settings Reload", [&](std::string& value) {
		if(shader && toBool(value))
			settingsShaders.push_back(shader);
	});

	datahandler("Variable", [&](std::string& value) {
		if(!shader)
			return;

		//Split into left and right parts
		std::vector<std::string> parts;
		split(value, parts, '=');

		if(parts.size() != 2)
			return;

		//Find variable type and name
		std::vector<std::string> decl;
		split(parts[0], decl, ' ');

		if(decl.size() != 2)
			return;

		//Find arguments to variable
		std::vector<std::string> args;
		split(parts[1], args, ' ');

		if(args.size() == 0)
			return;

		//Find the correct variable type
		render::Shader::VarType type = render::Shader::VT_invalid;

		std::string typeName, arraySizeText;
		unsigned arraySize;
		if(split(decl[0], typeName, '[', arraySizeText, ']')) {
			arraySize = atoi(arraySizeText.c_str());
			if(arraySize > 100 || arraySize == 0)
				return;
		}
		else {
			typeName = decl[0];
			arraySize = 1;
		}

		if(typeName == "tex" || typeName == "int")
			type = render::Shader::VT_int;
		else if(typeName == "ivec2")
			type = render::Shader::VT_int2;
		else if(typeName == "ivec3")
			type = render::Shader::VT_int3;
		else if(typeName == "ivec4")
			type = render::Shader::VT_int4;
		else if(typeName == "float")
			type = render::Shader::VT_float;
		else if(typeName == "vec2")
			type = render::Shader::VT_float2;
		else if(typeName == "vec3")
			type = render::Shader::VT_float3;
		else if(typeName == "vec4")
			type = render::Shader::VT_float4;
		else if(typeName == "mat3")
			type = render::Shader::VT_mat3;

		if(type == render::Shader::VT_invalid)
			return;

		render::Shader::Variable var(type, arraySize);

		if(args[0].find_first_not_of("0123456789.-+eE") != args[0].npos) {
			auto& call = args[0];
			if(call == "global") {
				if(args.size() >= 2) {
					ShaderGlobal* glob;
					auto it = shaderGlobals.find(args[1]);

					if(it == shaderGlobals.end()) {
						glob = new ShaderGlobal();
						glob->name = args[1];
						glob->type = type;
						glob->arraySize = arraySize;
						shaderGlobals[glob->name] = glob;

						switch(type) {
							case render::Shader::VT_int:
								glob->size = sizeof(int);
							break;
							case render::Shader::VT_int2:
								glob->size = sizeof(int) * 2;
							break;
							case render::Shader::VT_int3:
								glob->size = sizeof(int) * 3;
							break;
							case render::Shader::VT_int4:
								glob->size = sizeof(int) * 4;
							break;
							case render::Shader::VT_float:
								glob->size = sizeof(float);
							break;
							case render::Shader::VT_float2:
								glob->size = sizeof(float) * 2;
							break;
							case render::Shader::VT_float3:
								glob->size = sizeof(float) * 3;
							break;
							case render::Shader::VT_float4:
								glob->size = sizeof(float) * 4;
							break;
							case render::Shader::VT_mat3:
								glob->size = sizeof(float) * 9;
							break;
						}

						glob->size *= arraySize;
						glob->ptr = malloc(glob->size);
						memset(glob->ptr, 0, glob->size);
					}
					else {
						glob = it->second;
					}

					var._floatcall = shader_global;
					var._args = (void*)glob;
					var.constant = false;
				}
			}
			else switch(var.type) {
				case render::Shader::VT_int:
					if(call == "emp_flag") {
						var._intcall = shader_emp_flag;
						var.constant = false;
					}
					else if(call == "obj_id") {
						var._intcall = shader_obj_id;
						var.constant = false;
					}
				break;
				case render::Shader::VT_float:
					if(call == "time") {
						var._floatcall = shader_frameTime;
					}
					else if(call == "game_time") {
						var._floatcall = shader_gameTime;
					}
					else if(call == "unique") {
						var._floatcall = shader_unique;
						var.constant = false;
					}
					else if(call == "random") {
						var._floatcall = shader_random;
					}
					else if(call == "time_cycle") {
						var._floatcall = shader_frameTime_cycle;
						float* pArgs = new float[var.count];
						var._args = pArgs;

						for(auto i = 0; i < var.count; ++i)
							pArgs[i] = 1000;
						loadToFloats(pArgs,args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "game_time_cycle") {
						var._floatcall = shader_gameTime_cycle;
						float* pArgs = new float[var.count];
						var._args = pArgs;

						for(auto i = 0; i < var.count; ++i)
							pArgs[i] = 1000;
						loadToFloats(pArgs,args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "time_cycle_abs") {
						var._floatcall = shader_frameTime_cycle_abs;
						float* pArgs = new float[var.count];
						var._args = pArgs;

						for(auto i = 0; i < var.count; ++i)
							pArgs[i] = 1000;
						loadToFloats(pArgs,args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "game_time_cycle_abs") {
						var._floatcall = shader_gameTime_cycle_abs;
						float* pArgs = new float[var.count];
						var._args = pArgs;

						for(auto i = 0; i < var.count; ++i)
							pArgs[i] = 1000;
						loadToFloats(pArgs,args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "node_distance") {
						var._floatcall = shader_node_distance;
						var.constant = false;
					}
					else if(call == "node_selected") {
						var._floatcall = shader_node_selected;
						var.constant = false;
					}
					else if(call == "node_scale") {
						var._floatcall = shader_node_scale;
						var.constant = false;
					}
					else if(call == "obj_velocity") {
						var._floatcall = shader_obj_velocity;
						var.constant = false;
					}
					else if(call == "obj_acceleration") {
						var._floatcall = shader_obj_acceleration;
						var.constant = false;
					}
					else if(call == "plane_minrad") {
						var._floatcall = shader_plane_minrad;
						var.constant = false;
					}
					else if(call == "plane_maxrad") {
						var._floatcall = shader_plane_maxrad;
						var.constant = false;
					}
					else if(call == "state_vars") {
						var._floatcall = shader_statevars;
						var.constant = false;

						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						unsigned index = 0;
						auto i = args.begin() + 1;
						auto end = args.end();
						for(; i != end && index < var.count; ++i, ++index)
							pArgs[index] = registerVar(*i);
					}
					else if(call == "pixel_ratio") {
						var._floatcall = shader_pixelRatio;
					}
					else if(call == "skin_grd_count") {
						var._floatcall = shader_skin_gradientCount;
						var.constant = false;
					}
					else if(call == "skin_grd_mode") {
						var._floatcall = shader_skin_gradientMode;
						var.constant = false;
					}
					else if(call == "light_radius") {
						var._floatcall = shader_light_radius;
						var.constant = true;

						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						loadToInts(pArgs, args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "light_active") {
						var._floatcall = shader_light_active;
						var.constant = true;

						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						loadToInts(pArgs, args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
				break;
				case render::Shader::VT_float2:
					if(call == "skin_src_pos") {
						var._floatcall = shader_skin_src_pos;
						var.constant = false;
					}
					else if(call == "skin_src_size") {
						var._floatcall = shader_skin_src_size;
						var.constant = false;
					}
					else if(call == "skin_dst_size") {
						var._floatcall = shader_skin_dst_size;
						var.constant = false;
					}
					else if(call == "skin_dim_modes") {
						var._floatcall = shader_skin_mode;
						var.constant = false;
					}
					else if(call == "tex_size") {
						var._floatcall = shader_tex_size;
						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						loadToInts(pArgs, args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "light_screen_position") {
						var._floatcall = shader_light_screen;
						var.constant = true;

						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						loadToInts(pArgs, args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
				break;
				case render::Shader::VT_float3:
					if(call == "light_position") {
						var._floatcall = shader_light_position;
						var.constant = true;

						int* pArgs = new int[var.count];
						memset(pArgs,0,sizeof(int) * var.count);
						var._args = pArgs;

						loadToInts(pArgs, args.begin()+1,
							(int)args.size() <= var.count+1 ? args.end() : args.begin()+(1+var.count));
					}
					else if(call == "obj_position") {
						var._floatcall = shader_obj_position;
						var.constant = false;
					}
					else if(call == "node_position") {
						var._floatcall = shader_node_position;
						var.constant = false;
					}
				break;
				case render::Shader::VT_float4:
					if(call == "node_color") {
						var._floatcall = shader_node_color;
						var.constant = false;
					}
					else if(call == "skin_grd_colors") {
						var._floatcall = shader_skin_gradientCols;
						var.constant = false;
					}
					else if(call == "skin_grd_rects") {
						var._floatcall = shader_skin_gradientRects;
						var.constant = false;
					}
					else if(call == "skin_margin_src") {
						var._floatcall = shader_skin_margin_src;
						var.constant = false;
					}
					else if(call == "skin_margin_dest") {
						var._floatcall = shader_skin_margin_dest;
						var.constant = false;
					}
					else if(call == "sprite_pos") {
						var._floatcall = shader_sprite_pos;
						var.constant = false;
					}
					else if(call == "obj_quadrant_damage") {
						var._floatcall = shader_quadrant_damage;
						var.constant = false;
					}
					else if(call == "obj_rotation") {
						var._floatcall = shader_obj_rotation;
						var.constant = false;
					}
					else if(call == "node_rotation") {
						var._floatcall = shader_node_rotation;
						var.constant = false;
					}
				break;
				case render::Shader::VT_mat3:
					if(call == "inverse_view") {
						var._floatcall = shader_invView;
					}
				break;
			}
		}

		if(var._intcall == 0) {
			auto from = args.begin(), to = args.size() <= var.count ? args.end() : args.begin()+var.count;
			switch(var.type) {
			case render::Shader::VT_int:
				loadToInts(var._ints, from, to); break;
			case render::Shader::VT_int2:
				loadToInt2s(var._ints, from, to); break;
			case render::Shader::VT_int3:
				loadToInt3s(var._ints, from, to); break;
			case render::Shader::VT_int4:
				loadToInt4s(var._ints, from, to); break;

			case render::Shader::VT_float:
				loadToFloats(var._floats, from, to); break;
			case render::Shader::VT_float2:
				loadToFloat2s(var._floats, from, to); break;
			case render::Shader::VT_float3:
				loadToFloat3s(var._floats, from, to); break;
			case render::Shader::VT_float4:
				loadToFloat4s(var._floats, from, to); break;
			}
		}

		shader->addVariable(decl[1], var);
	});

	datahandler.read(filename);
}

};
