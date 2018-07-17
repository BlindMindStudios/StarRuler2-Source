#include "resource/library.h"
#include "main/console.h"
#include "main/logging.h"
#include "files.h"
#include <set>

#include "render/gl_shader.h"

namespace resource {

threads::Mutex reloadTextureMutex;
std::set<std::string> reloadTextures;

threads::Mutex reloadShaderMutex;
std::set<std::string> reloadShaders;

threads::Mutex reloadSkinMutex;
std::set<std::string> reloadSkins;

void Library::clearWatchedResources() {
	clearWatches();

	{
		threads::Lock lock(reloadTextureMutex);
		reloadTextures.clear();
	}

	{
		threads::Lock lock(reloadShaderMutex);
		reloadShaders.clear();
	}

	{
		threads::Lock lock(reloadSkinMutex);
		reloadSkins.clear();
	}
}

void Library::watchTexture(const std::string& filename) {
	//info("Watching texture '%s'", filename.c_str());
	watchFile(filename, [filename]() -> bool {
		threads::Lock lock(reloadTextureMutex);
		if(reloadTextures.find(filename) == reloadTextures.end()) {
			reloadTextures.insert(filename);
			info("Reloading texture '%s'", filename.c_str());
		}
		return true;
	});
}

void Library::watchSkin(const std::string& filename) {
	//info("Watching skin '%s'", filename.c_str());
	watchFile(filename, [filename]() -> bool {
		threads::Lock lock(reloadSkinMutex);
		if(reloadSkins.find(filename) == reloadSkins.end()) {
			reloadSkins.insert(filename);
			info("Reloading skin '%s'", filename.c_str());
		}
		return true;
	});
}

void Library::watchShader(const std::string& shadername, const std::string& filename) {
	std::string absFilename = getAbsolutePath(filename);
	//info("Watching shader '%s' (%s)", shadername.c_str(), filename.c_str());
	watchFile(filename, [absFilename,shadername]() -> bool {
		threads::Lock lock(reloadShaderMutex);
		if(reloadShaders.find(absFilename) == reloadShaders.end()) {
			reloadShaders.insert(shadername);
		}
		return true;
	});
}

void Library::reloadWatchedResources() {
	if(!reloadTextures.empty()) {
		threads::Lock lock(reloadTextureMutex);
		foreach(name, reloadTextures) {
			auto tex = texture_files.find(*name);
			if(tex == texture_files.end())
				continue;
			if(tex->second == 0)
				continue;

			Image* img = loadImage(name->c_str());
			if(img) {
				tex->second->load(*img, tex->second->hasMipMaps);
				delete img;
			}
		}

		reloadTextures.clear();

		//Mark all spritesheets as dirty, or they won't properly handle changes in resolution
		foreach(sheet,spritesheets)
			sheet->second->dirty = true;
	}

	if(!reloadShaders.empty()) {
		threads::Lock lock(reloadShaderMutex);
		foreach(name, reloadShaders) {
			auto program = programs.find(*name);
			if(program != programs.end()) {
				if(program->second->compile() != 0)
					error("-In Shader Program '%s'", program->first.c_str());
				foreach(shader, shaders) {
					if(shader->second->program == program->second) {
						info("Reloading shader (%s)", shader->first.c_str());
						if(shader->second->compile() != 0)
							error("-In Shader '%s'", shader->first.c_str());
					}
				}
			}
		}

		reloadShaders.clear();
	}

	if(!reloadSkins.empty()) {
		threads::Lock lock(reloadShaderMutex);
		foreach(name, reloadSkins) {
			auto skin = skin_files.find(*name);
			if(skin != skin_files.end())
				loadSkin(*name, skin->second);
		}

		reloadSkins.clear();
	}
}

void Library::bindHotloading() {
	console.addCommand("reload", [this](argList& args) {
		if(args.empty()) {
			console.printLn("Specify exact name of shader to reload");
			return;
		}

		auto shader = shaders.find(args[0]);
		if(shader != shaders.end()) {
			int result = shader->second->compile();
			if(result == 0)
				console.printLn("Successfully recompiled shader");
			else
				error("Recompilation of '%s' failed", shader->first.c_str());
		}
		else {
			std::string path = getAbsolutePath(args[0]);
			auto tex = texture_files.find(path);
			if(tex != texture_files.end()) {
				if(tex->second) {
					Image* img = loadImage(path.c_str());
					if(img) {
						tex->second->load(*img, tex->second->hasMipMaps);
						console.printLn("Texture reloaded");
						delete img;
					}
				}
				else {
					console.printLn("Texture type cannot be reloaded");
				}
			}
			else {
				console.printLn("No Shader or Texture match found");
			}
		}
	}, true );
}

};
