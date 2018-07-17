#include "render/shader.h"
#include "render/gl_shader.h"
#include "compat/gl.h"
#include "compat/misc.h"
#include "str_util.h"
#include "files.h"
#include "main/logging.h"
#include "main/references.h"

extern unsigned frameNumber;

namespace render {

void preProcessShader(std::string& shader) {
	std::string output;
	size_t start = 0;
	while(start < shader.size()) {
		size_t pos = shader.find('#', start);
		if(pos == std::string::npos)
			break;

		if(pos != start)
			output += shader.substr(start, pos-start);

		if(shader.size() - pos > 3 && shader[pos+1] == '{' && shader[pos+2] == '{') {
			size_t endpos = shader.find("}}", pos, 2);
			if(endpos == std::string::npos)
				break;

			std::string value = shader.substr(pos+3, endpos-pos-3);
			std::string replace;

			if(value == "level:extreme") {
				auto* sl = devices.settings.engine.getSetting("iShaderLevel");
				if(sl)
					output += (sl->getInteger() >= 4) ? "true" : "false";
			}
			else if(value == "level:high") {
				auto* sl = devices.settings.engine.getSetting("iShaderLevel");
				if(sl)
					output += (sl->getInteger() >= 3) ? "true" : "false";
			}
			else if(value == "level:medium") {
				auto* sl = devices.settings.engine.getSetting("iShaderLevel");
				if(sl)
					output += (sl->getInteger() >= 2) ? "true" : "false";
			}
			else if(value == "fallback") {
				auto* fallback = devices.settings.engine.getSetting("bShaderFallback");
				if(fallback)
					output += (fallback->getBool()) ? "true" : "false";
			}
			else {
				auto* setting = devices.settings.engine.getSetting(value.c_str());
				if(!setting)
					setting = devices.settings.mod.getSetting(value.c_str());

				if(setting) {
					switch(setting->type) {
						case GT_Bool:
							output += (setting->getBool()) ? "true" : "false";
						break;
						case GT_Integer:
						case GT_Enum:
							output += toString<int>(setting->getInteger());
						break;
						case GT_Double:
							output += toString<double>(setting->getDouble());
						break;
						case GT_String:
							output += *setting->getString();
						break;
					}
				}
				else {
					error("ERROR: Could not find shader variable %s.", value.c_str());
				}
			}

			start = endpos + 2;
		}
		else if(shader.size() - pos > 11 && shader.compare(pos, 10, "#include \"") == 0) {
			size_t endpos = shader.find("\"", pos+10, 1);
			if(endpos == std::string::npos)
				break;

			std::string value = shader.substr(pos+10, endpos-pos-10);
			std::string fname = devices.mods.resolve(value);
			if(!fileExists(fname)) {
				error("ERROR COMPILING SHADER: Could not find include file %s. (Resolved to %s)", value.c_str(), fname.c_str());
			}
			else {
				std::string includeContents = getFileContents(fname);
				preProcessShader(includeContents);
				output += includeContents;
			}

			start = endpos + 1;
		}
		else {
			output += "#";
			start = pos + 1;
		}
	}
	if(start < shader.size())
		output += shader.substr(start, shader.size()-start);
	shader = output;
}

class GLShader;
class GLShaderProgram : public ShaderProgram {
public:
	GLuint vertex_shader, fragment_shader, program;
	std::string vertex_file, fragment_file;

	std::unordered_map<GLuint, unsigned> cached_uniforms;
	std::vector<float> mem_buffer;

	const GLShader* lastShader;

	GLShaderProgram(const std::string& vFile, const std::string& fFile)
		: vertex_file(vFile), fragment_file(fFile), program(0), lastShader(0)
	{
	}

	~GLShaderProgram() {
		reset();
	}

	void reset() {
		if(program != 0) {
			glDeleteProgram(program);
			program = 0;
		}

		mem_buffer.clear();
		cached_uniforms.clear();
	}

	unsigned cacheUniform(GLuint position, size_t size) {
		auto it = cached_uniforms.find(position);
		if(it != cached_uniforms.end())
			return it->second;

		unsigned pos = (unsigned)mem_buffer.size();
		cached_uniforms[position] = pos;

		for(size_t i = 0; i < size; ++i)
			mem_buffer.push_back(0);
		return pos;
	}

	GLuint compileShader(GLenum type, const std::string& fname, const std::string& source) {
		GLuint shader;

		//Compile
		const GLchar* str_ptr = (const GLchar*)source.c_str();
		GLint str_len = (GLint)source.size();
		shader = glCreateShader(type);
		glShaderSource(shader, 1, &str_ptr, &str_len);
		glCompileShader(shader);
		
		//Check compile value
		GLint shader_ok;
		glGetShaderiv(shader, GL_COMPILE_STATUS, &shader_ok);

		if(!shader_ok) {
			error("Failed to compile shader: %s", fname.c_str());

			GLint log_length;
			char* log;

			glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);
			log = (char*)malloc(log_length);

			glGetShaderInfoLog(shader, log_length, NULL, log);
			error("%s", log);

			free(log);

			glDeleteShader(shader);
			return 0;
		}
		else if(getLogLevel() == LL_Info) {
			//Print warnings in verbose
			GLint log_length;
			glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);

			//We're always provided at least an empty string, just ignore very small logs
			if(log_length > 8) {
				char* log;
				log = (char*)malloc(log_length);

				glGetShaderInfoLog(shader, log_length, NULL, log);
				error("Shader '%s' has warnings:\n%s", fname.c_str(), log);

				free(log);
			}
		}

		return shader;
	}

	int compile() override {
		reset();
		//Compile vertex shader
		{
			auto contents = getFileContents(vertex_file);
			preProcessShader(contents);
			if(contents.empty()) {
				error("Could not open vertex shader, or the file was empty");
				return 1;
			}

			vertex_shader = compileShader(GL_VERTEX_SHADER, vertex_file, contents);
			if(!vertex_shader)
				return 1;
		}

		//Compile fragment shader
		{
			auto contents = getFileContents(fragment_file);
			preProcessShader(contents);
			fragment_shader = compileShader(GL_FRAGMENT_SHADER, fragment_file, contents);
			if(!fragment_shader) {
				if(contents.empty())
					error("Could not open fragment shader, or the file was empty");
				glDeleteShader(vertex_shader);
				return 2;
			}
		}
		
		//Link entire program
		program = glCreateProgram();
		
		glBindAttribLocation(program, 0, "in_vertex");
		glBindAttribLocation(program, 2, "in_normal");
		glBindAttribLocation(program, 1, "in_uv");
		glBindAttribLocation(program, 3, "in_tangent");
		glBindAttribLocation(program, 4, "in_color");
		glBindAttribLocation(program, 5, "in_uv2");

		glAttachShader(program, vertex_shader);
		glAttachShader(program, fragment_shader);
		glLinkProgram(program);

		glDeleteShader(vertex_shader);
		glDeleteShader(fragment_shader);

		//Make sure it linked correctly
		GLint status;
		glGetProgramiv(program,GL_LINK_STATUS,&status);
		if(status == GL_FALSE) {
			error("Linking failed:");
			GLint log_length;
			char* log;

			glGetProgramiv(program, GL_INFO_LOG_LENGTH, &log_length);
			log = (char*)malloc(log_length);

			glGetProgramInfoLog(program, log_length, NULL, log);
			error("%s", log);

			free(log);

			glDeleteProgram(program);
			program = 0;
			return 3;
		}

		return 0;
	}
};

class GLShader : public Shader {
public:
	mutable unsigned lastBoundFrame;

	std::vector<std::string> uniform_names;
	std::vector<GLuint> uniform_locations;
	std::vector<unsigned> uniform_vars;
	std::vector<unsigned> uniform_cache;

	GLShader()
	{
		program = 0;
		constant = true;
		dynamicFloats = 0;
		lastBoundFrame = 0xffffffff;
	}

	~GLShader() {
		reset();
	}

	void reset() {
		uniform_locations.clear();
		uniform_cache.clear();
		uniform_vars.clear();
	}

	virtual int compile() {
		reset();

		if(!program) {
			error("No associated program");
			return 4;
		}

		auto glProgram = (GLShaderProgram*)program;
		if(glProgram->program == 0)
			return 4;

		bool missingVars = false;
		for(unsigned i = 0; i < uniform_names.size(); ++i) {
			GLuint location = glGetUniformLocation(glProgram->program, uniform_names[i].c_str());

			if(location == (GLuint)-1) {
				//NOTE: This is no longer considered an error, because dynamic shader levels
				//are going to be causing uniforms to be missing all the time.
				//
				//error("Unable to find uniform '%s'", uniform_names[i].c_str());
				//missingVars = true;
			}
			else {
				uniform_locations.push_back(location);
				uniform_vars.push_back(i);
			}
		}

		for(unsigned i = 0; i < uniform_locations.size(); ++i) {
			auto& v = vars[uniform_vars[i]];
			size_t size = 0;
			switch(v.type) {
			case VT_int: case VT_float: size = 1; break;
			case VT_int2: case VT_float2: size = 2; break;
			case VT_int3: case VT_float3: size = 3; break;
			case VT_int4: case VT_float4: size = 4; break;
			case VT_mat3: size = 9; break;
			}

			size *= v.count;
			uniform_cache.push_back(glProgram->cacheUniform(uniform_locations[i], size));
		}

		if(missingVars)
			return 4;
		else
			return 0;
	}

	virtual void addVariable(const std::string& name, const Variable& var) {
		uniform_names.push_back(name);
		Shader::addVariable(name, var);
	}

	virtual void bind(float* dynamic) const {
		if(!program) {
			glUseProgram(0);
			return;
		}

		auto glProgram = (GLShaderProgram*)program;
		if(auto programID = glProgram->program) {
			glUseProgram(programID);
		}
		else {
			glUseProgram(0);
			return;
		}

		const bool bindConst = lastBoundFrame != frameNumber || glProgram->lastShader != this;
		lastBoundFrame = frameNumber;
		glProgram->lastShader = this;

		if(dynamic) {
			float* floats = dynamic;

			for(size_t i = 0, cnt = uniform_locations.size(); i < cnt; ++i) {
				const Shader::Variable& var = vars[uniform_vars[i]];
				if(!bindConst && var.constant)
					continue;

				GLuint uniform = uniform_locations[i];
				void* uniformMem = (void*)&glProgram->mem_buffer[uniform_cache[i]];

				switch(var.type) {
					case VT_invalid:
					break;

					case VT_int:
						if(var.constant) {
							if(var._intcall)
								var._intcall(var._ints, var.count, var._args);

							if(memcmp(uniformMem, var._ints, var.count * 4) != 0) {
								glUniform1iv(uniform, var.count, var._ints);
								memcpy(uniformMem, var._ints, var.count * 4);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 4) != 0) {
								glUniform1iv(uniform, var.count, (int*)floats);
								memcpy(uniformMem, floats, var.count * 4);
							}
							floats += var.count;
						}
						break;
					case VT_int2:
						if(var.constant) {
							if(var._intcall)
								var._intcall(var._ints, var.count, var._args);

							if(memcmp(uniformMem, var._ints, var.count * 8) != 0) {
								glUniform2iv(uniform, var.count, var._ints);
								memcpy(uniformMem, var._ints, var.count * 8);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 8) != 0) {
								glUniform2iv(uniform, var.count, (int*)floats);
								memcpy(uniformMem, floats, var.count * 8);
							}
							floats += var.count * 2;
						}
						break;
					case VT_int3:
						if(var.constant) {
							if(var._intcall)
								var._intcall(var._ints, var.count, var._args);

							if(memcmp(uniformMem, var._ints, var.count * 12) != 0) {
								glUniform3iv(uniform, var.count, var._ints);
								memcpy(uniformMem, var._ints, var.count * 12);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 12) != 0) {
								glUniform3iv(uniform, var.count, (int*)floats);
								memcpy(uniformMem, floats, var.count * 12);
							}
							floats += var.count * 3;
						}
						break;
					case VT_int4:
						if(var.constant) {
							if(var._intcall)
								var._intcall(var._ints, var.count, var._args);

							if(memcmp(uniformMem, var._ints, var.count * 16) != 0) {
								glUniform4iv(uniform, var.count, var._ints);
								memcpy(uniformMem, var._ints, var.count * 16);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 16) != 0) {
								glUniform4iv(uniform, var.count, (int*)floats);
								memcpy(uniformMem, floats, var.count * 16);
							}
							floats += var.count * 4;
						}
						break;

					case VT_float:
						if(var.constant) {
							if(var._floatcall)
								var._floatcall(var._floats, var.count, var._args);

							if(memcmp(uniformMem, var._floats, var.count * 4) != 0) {
								glUniform1fv(uniform, var.count, var._floats);
								memcpy(uniformMem, var._floats, var.count * 4);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 4) != 0) {
								glUniform1fv(uniform, var.count, floats);
								memcpy(uniformMem, floats, var.count * 4);
							}
							floats += var.count;
						}
						break;
					case VT_float2:
						if(var.constant) {
							if(var._floatcall)
								var._floatcall(var._floats, var.count, var._args);

							if(memcmp(uniformMem, var._floats, var.count * 8) != 0) {
								glUniform2fv(uniform, var.count, var._floats);
								memcpy(uniformMem, var._floats, var.count * 8);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 8) != 0) {
								glUniform2fv(uniform, var.count, floats);
								memcpy(uniformMem, floats, var.count * 8);
							}
							floats += var.count * 2;
						}
						break;
					case VT_float3:
						if(var.constant) {
							if(var._floatcall)
								var._floatcall(var._floats, var.count, var._args);

							if(memcmp(uniformMem, var._floats, var.count * 12) != 0) {
								glUniform3fv(uniform, var.count, var._floats);
								memcpy(uniformMem, var._floats, var.count * 12);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 12) != 0) {
								glUniform3fv(uniform, var.count, floats);
								memcpy(uniformMem, floats, var.count * 12);
							}
							floats += var.count * 3;
						}
						break;
					case VT_float4:
						if(var.constant) {
							if(var._floatcall)
								var._floatcall(var._floats, var.count, var._args);

							if(memcmp(uniformMem, var._floats, var.count * 16) != 0) {
								glUniform4fv(uniform, var.count, var._floats);
								memcpy(uniformMem, var._floats, var.count * 16);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 16) != 0) {
								glUniform4fv(uniform, var.count, floats);
								memcpy(uniformMem, floats, var.count * 16);
							}
							floats += var.count * 4;
						}
						break;
					case VT_mat3:
						if(var.constant) {
							if(var._floatcall)
								var._floatcall(var._floats, var.count, var._args);

							if(memcmp(uniformMem, var._floats, var.count * 36) != 0) {
								glUniformMatrix3fv(uniform, var.count, false, var._floats);
								memcpy(uniformMem, var._floats, var.count * 36);
							}
						}
						else if(var._intcall) {
							if(memcmp(uniformMem, floats, var.count * 36) != 0) {
								glUniformMatrix3fv(uniform, var.count, false, floats);
								memcpy(uniformMem, floats, var.count * 36);
							}
							floats += var.count * 9;
						}
					NO_DEFAULT
				}
			}
		}
		else {
			for(size_t i = 0, cnt = uniform_locations.size(); i < cnt; ++i) {
				const Shader::Variable& var = vars[uniform_vars[i]];
				if(!bindConst && var.constant)
					continue;

				GLuint uniform = uniform_locations[i];
				void* uniformMem = (void*)&glProgram->mem_buffer[uniform_cache[i]];

				switch(var.type) {
					case VT_invalid:
					break;

					case VT_int:
						if(var._intcall)
							var._intcall(var._ints,var.count,var._args);
						if(memcmp(uniformMem, var._ints, var.count * 4) != 0) {
							glUniform1iv(uniform, var.count, var._ints);
							memcpy(uniformMem, var._ints, var.count * 4);
						}
						break;
					case VT_int2:
						if(var._intcall)
							var._intcall(var._ints,var.count,var._args);
						if(memcmp(uniformMem, var._ints, var.count * 8) != 0) {
							glUniform2iv(uniform, var.count, var._ints);
							memcpy(uniformMem, var._ints, var.count * 8);
						}
						break;
					case VT_int3:
						if(var._intcall)
							var._intcall(var._ints,var.count,var._args);
						if(memcmp(uniformMem, var._ints, var.count * 12) != 0) {
							glUniform3iv(uniform, var.count, var._ints);
							memcpy(uniformMem, var._ints, var.count * 12);
						}
						break;
					case VT_int4:
						if(var._intcall)
							var._intcall(var._ints,var.count,var._args);
						if(memcmp(uniformMem, var._ints, var.count * 16) != 0) {
							glUniform4iv(uniform, var.count, var._ints);
							memcpy(uniformMem, var._ints, var.count * 16);
						}
						break;

					case VT_float:
						if(var._floatcall)
							var._floatcall(var._floats,var.count,var._args);
						if(memcmp(uniformMem, var._floats, var.count * 4) != 0) {
							glUniform1fv(uniform, var.count, var._floats);
							memcpy(uniformMem, var._floats, var.count * 4);
						}
						break;
					case VT_float2:
						if(var._floatcall)
							var._floatcall(var._floats,var.count,var._args);
						if(memcmp(uniformMem, var._floats, var.count * 8) != 0) {
							glUniform2fv(uniform, var.count, var._floats);
							memcpy(uniformMem, var._floats, var.count * 8);
						}
						break;
					case VT_float3:
						if(var._floatcall)
							var._floatcall(var._floats,var.count,var._args);
						if(memcmp(uniformMem, var._floats, var.count * 12) != 0) {
							glUniform3fv(uniform, var.count, var._floats);
							memcpy(uniformMem, var._floats, var.count * 12);
						}
						break;
					case VT_float4:
						if(var._floatcall)
							var._floatcall(var._floats,var.count,var._args);
						if(memcmp(uniformMem, var._floats, var.count * 16) != 0) {
							glUniform4fv(uniform, var.count, var._floats);
							memcpy(uniformMem, var._floats, var.count * 16);
						}
						break;

					case VT_mat3:
						if(var._floatcall)
							var._floatcall(var._floats,var.count,var._args);
						if(memcmp(uniformMem, var._floats, var.count * 36) != 0) {
							glUniformMatrix3fv(uniform, var.count, false, var._floats);
							memcpy(uniformMem, var._floats, var.count * 36);
						}
						break;
					NO_DEFAULT
				}
			}
		}
	}

	void updateDynamicVars() const {
		for(size_t i = 0, cnt = uniform_locations.size(); i < cnt; ++i) {
			const Shader::Variable& var = vars[uniform_vars[i]];
			if(var.constant)
				continue;
			GLuint uniform = uniform_locations[i];
			void* uniformMem = (void*)&((GLShaderProgram*)program)->mem_buffer[uniform_cache[i]];

			switch(var.type) {
				case VT_invalid:
				break;

				case VT_int:
					if(var._intcall)
						var._intcall(var._ints,var.count,var._args);
					if(memcmp(uniformMem, var._ints, var.count * 4) != 0) {
						glUniform1iv(uniform, var.count, var._ints);
						memcpy(uniformMem, var._ints, var.count * 4);
					}
					break;
				case VT_int2:
					if(var._intcall)
						var._intcall(var._ints,var.count,var._args);
					if(memcmp(uniformMem, var._ints, var.count * 8) != 0) {
						glUniform2iv(uniform, var.count, var._ints);
						memcpy(uniformMem, var._ints, var.count * 8);
					}
					break;
				case VT_int3:
					if(var._intcall)
						var._intcall(var._ints,var.count,var._args);
					if(memcmp(uniformMem, var._ints, var.count * 12) != 0) {
						glUniform3iv(uniform, var.count, var._ints);
						memcpy(uniformMem, var._ints, var.count * 12);
					}
					break;
				case VT_int4:
					if(var._intcall)
						var._intcall(var._ints,var.count,var._args);
					if(memcmp(uniformMem, var._ints, var.count * 16) != 0) {
						glUniform4iv(uniform, var.count, var._ints);
						memcpy(uniformMem, var._ints, var.count * 16);
					}
					break;

				case VT_float:
					if(var._floatcall)
						var._floatcall(var._floats,var.count,var._args);
					if(memcmp(uniformMem, var._floats, var.count * 4) != 0) {
						glUniform1fv(uniform, var.count, var._floats);
						memcpy(uniformMem, var._floats, var.count * 4);
					}
					break;
				case VT_float2:
					if(var._floatcall)
						var._floatcall(var._floats,var.count,var._args);
					if(memcmp(uniformMem, var._floats, var.count * 8) != 0) {
						glUniform2fv(uniform, var.count, var._floats);
						memcpy(uniformMem, var._floats, var.count * 8);
					}
					break;
				case VT_float3:
					if(var._floatcall)
						var._floatcall(var._floats,var.count,var._args);
					if(memcmp(uniformMem, var._floats, var.count * 12) != 0) {
						glUniform3fv(uniform, var.count, var._floats);
						memcpy(uniformMem, var._floats, var.count * 12);
					}
					break;
				case VT_float4:
					if(var._floatcall)
						var._floatcall(var._floats,var.count,var._args);
					if(memcmp(uniformMem, var._floats, var.count * 16) != 0) {
						glUniform4fv(uniform, var.count, var._floats);
						memcpy(uniformMem, var._floats, var.count * 16);
					}
					break;

				case VT_mat3:
					if(var._floatcall)
						var._floatcall(var._floats,var.count,var._args);
					if(memcmp(uniformMem, var._floats, var.count * 36) != 0) {
						glUniformMatrix3fv(uniform, var.count, false, var._floats);
						memcpy(uniformMem, var._floats, var.count * 36);
					}
					break;
				NO_DEFAULT
			}
		}
	}

	void saveDynamicVars(float* buffer) const {
		float* floats = buffer;

		for(size_t i = 0, cnt = uniform_locations.size(); i < cnt; ++i) {
			const Shader::Variable& var = vars[uniform_vars[i]];
			if(var.constant)
				continue;

			switch(var.type) {
				case VT_invalid:
				break;

				case VT_int:
					if(var._intcall) {
						var._intcall((int*)floats,var.count,var._args);
						floats += var.count;
					}
					break;
				case VT_int2:
					if(var._intcall) {
						var._intcall((int*)floats,var.count,var._args);
						floats += var.count * 2;
					}
					break;
				case VT_int3:
					if(var._intcall) {
						var._intcall((int*)floats,var.count,var._args);
						floats += var.count * 3;
					}
					break;
				case VT_int4:
					if(var._intcall) {
						var._intcall((int*)floats,var.count,var._args);
						floats += var.count * 4;
					}
					break;

				case VT_float:
					if(var._floatcall) {
						var._floatcall(floats,var.count,var._args);
						floats += var.count;
					}
					break;
				case VT_float2:
					if(var._floatcall) {
						var._floatcall(floats,var.count,var._args);
						floats += var.count * 2;
					}
					break;
				case VT_float3:
					if(var._floatcall) {
						var._floatcall(floats,var.count,var._args);
						floats += var.count * 3;
					}
					break;
				case VT_float4:
					if(var._floatcall) {
						var._floatcall(floats,var.count,var._args);
						floats += var.count * 4;
					}
					break;

				case VT_mat3:
					if(var._floatcall) {
						var._floatcall(floats,var.constant,var._args);
						floats += var.constant * 9;
					}
				NO_DEFAULT
			}
		}
	}

	void loadDynamicVars(float* buffer) const {
		float* floats = buffer;

		for(size_t i = 0, cnt = uniform_locations.size(); i < cnt; ++i) {
			const Shader::Variable& var = vars[uniform_vars[i]];
			if(var.constant)
				continue;

			GLuint uniform = uniform_locations[i];
			void* uniformMem = (void*)&((GLShaderProgram*)program)->mem_buffer[uniform_cache[i]];

			switch(var.type) {
				case VT_invalid:
				break;

				case VT_int:
					if(var._intcall) {
						if(memcmp(uniformMem, floats, var.count * 4) != 0) {
							glUniform1iv(uniform, var.count, (int*)floats);
							memcpy(uniformMem, floats, var.count * 4);
						}
						floats += var.count;
					}
					break;
				case VT_int2:
					if(var._intcall) {
						if(memcmp(uniformMem, floats, var.count * 8) != 0) {
							glUniform2iv(uniform, var.count, (int*)floats);
							memcpy(uniformMem, floats, var.count * 8);
						}
						floats += var.count * 2;
					}
					break;
				case VT_int3:
					if(var._intcall) {
						if(memcmp(uniformMem, floats, var.count * 12) != 0) {
							glUniform3iv(uniform, var.count, (int*)floats);
							memcpy(uniformMem, floats, var.count * 12);
						}
						floats += var.count * 3;
					}
					break;
				case VT_int4:
					if(var._intcall) {
						if(memcmp(uniformMem, floats, var.count * 16) != 0) {
							glUniform4iv(uniform, var.count, (int*)floats);
							memcpy(uniformMem, floats, var.count * 16);
						}
						floats += var.count * 4;
					}
					break;

				case VT_float:
					if(var._floatcall) {
						if(memcmp(uniformMem, floats, var.count * 4) != 0) {
							glUniform1fv(uniform, var.count, floats);
							memcpy(uniformMem, floats, var.count * 4);
						}
						floats += var.count;
					}
					break;
				case VT_float2:
					if(var._floatcall) {
						if(memcmp(uniformMem, floats, var.count * 8) != 0) {
							glUniform2fv(uniform, var.count, floats);
							memcpy(uniformMem, floats, var.count * 8);
						}
						floats += var.count * 2;
					}
					break;
				case VT_float3:
					if(var._floatcall) {
						if(memcmp(uniformMem, floats, var.count * 12) != 0) {
							glUniform3fv(uniform, var.count, floats);
							memcpy(uniformMem, floats, var.count * 12);
						}
						floats += var.count * 3;
					}
					break;
				case VT_float4:
					if(var._floatcall) {
						if(memcmp(uniformMem, floats, var.count * 16) != 0) {
							glUniform4fv(uniform, var.count, floats);
							memcpy(uniformMem, floats, var.count * 16);
						}
						floats += var.count * 4;
					}
					break;

				case VT_mat3:
					if(var._floatcall) {
						if(memcmp(uniformMem, floats, var.count * 36) != 0) {
							glUniformMatrix3fv(uniform, var.count, false, floats);
							memcpy(uniformMem, floats, var.count * 36);
						}
						floats += var.count * 9;
					}
					break;
				NO_DEFAULT
			}
		}
	}
};

Shader* createGLShader() {
	return new GLShader();
}

ShaderProgram* createGLShaderProgram(const char* vertex_shader, const char* fragment_shader) {
	return new GLShaderProgram(vertex_shader, fragment_shader);
}

};
