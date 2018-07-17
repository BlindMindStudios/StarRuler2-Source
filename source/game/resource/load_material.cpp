#include "main/references.h"
#include "main/logging.h"
#include "main/initialization.h"
#include "render/render_state.h"
#include "resource/library.h"
#include "compat/misc.h"
#include "str_util.h"
#include "num_util.h"
#include "threads.h"
#include "files.h"
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <functional>
#include <tuple>
#include <queue>
#include <stdint.h>

#include "main/profiler.h"

extern bool cancelAssets;

namespace resource {

umap<std::string, render::SpriteMode> INIT_VAR(spriteModes) {
	spriteModes["Horizontal"] = render::SM_Horizontal;
	spriteModes["Vertical"] = render::SM_Vertical;
} INIT_VAR_END;

umap<std::string, render::FaceCulling> INIT_VAR(cullingModes) {
	cullingModes["None"] = render::FC_None;
	cullingModes["Front"] = render::FC_Front;
	cullingModes["Back"] = render::FC_Back;
	cullingModes["Both"] = render::FC_Both;
} INIT_VAR_END;

umap<std::string, render::DepthTest> INIT_VAR(depthTests) {
	depthTests["Never"] = render::DT_Never;
	depthTests["Less"] = render::DT_Less;
	depthTests["LessEqual"] = render::DT_LessEqual;
	depthTests["Equal"] = render::DT_Equal;
	depthTests["GreaterEqual"] = render::DT_GreaterEqual;
	depthTests["Greater"] = render::DT_Greater;
	depthTests["Always"] = render::DT_Always;
	depthTests["NoDepthTest"] = render::DT_NoDepthTest;
} INIT_VAR_END;

umap<std::string, render::TextureWrap> INIT_VAR(textureWraps) {
	textureWraps["Repeat"] = render::TW_Repeat;
	textureWraps["Clamp"] = render::TW_Clamp;
	textureWraps["ClampEdge"] = render::TW_ClampEdge;
	textureWraps["Mirror"] = render::TW_Mirror;
} INIT_VAR_END;

umap<std::string, render::TextureFilter> INIT_VAR(textureFilters) {
	textureFilters["Linear"] = render::TF_Linear;
	textureFilters["Nearest"] = render::TF_Nearest;
} INIT_VAR_END;

umap<std::string, render::DrawMode> INIT_VAR(drawModes) {
	drawModes["Line"] = render::DM_Line;
	drawModes["Fill"] = render::DM_Fill;
} INIT_VAR_END;

umap<std::string, render::BaseMaterial> INIT_VAR(baseMats) {
	baseMats["Solid"] = render::MAT_Solid;
	baseMats["Add"] = render::MAT_Add;
	baseMats["Alpha"] = render::MAT_Alpha;
	baseMats["Font"] = render::MAT_Font;
	baseMats["Overlay"] = render::MAT_Overlay;
} INIT_VAR_END;

const unsigned DRIVER_MIPMAP_SIZE = 512 * 512;

struct QueuedTexture {
	int priority;
	std::vector<Image*> images;
	render::Texture* tex;
	std::string filename;
	bool mipmap;
	bool cachePixels;
	mutable unsigned row, lod;

	QueuedTexture(render::Texture* dest, int Priority, Image* source, bool Mipmap, bool CachePixels)
		: priority(Priority), tex(dest), mipmap(Mipmap), cachePixels(CachePixels), row(0), lod(0)
	{
		images.push_back(source);
	}

	QueuedTexture(render::Texture* dest, int Priority, const std::string& source, bool Mipmap, bool CachePixels)
		: priority(Priority), tex(dest), filename(source), mipmap(Mipmap), cachePixels(CachePixels), row(0), lod(0)
	{
	}

	//Loads the image, returning the number of bytes loaded
	// If true was returned, the image is done loading or there was a failure
	// The number of bytes loaded may exceed maxBytes - it is only a soft limit
	bool load(unsigned maxBytes, unsigned& loadedBytes);

	bool operator<(const QueuedTexture& other) const {
		return priority < other.priority;
	}

	void clearImages() {
		for(auto i = images.begin(); i != images.end(); ++i)
			delete *i;
		images.clear();
	}
};

threads::Mutex queuedImagesLock;
std::priority_queue<QueuedTexture> queuedImages;

threads::Mutex queuedTexturesLock;
std::priority_queue<QueuedTexture> queuedTextures;

threads::Mutex texIdentLock;
std::unordered_map<std::string,render::Texture*> texNames;

unsigned maxTexSize = 0;

void Library::clearTextures() {
	texNames.clear();
	maxTexSize = 0;
}

bool Library::hasQueuedImages() {
	return !queuedImages.empty();
}

unsigned getMaxTextureSize() {
	if(maxTexSize == 0) {
		auto* texQuality = devices.settings.engine.getSetting("iTextureQuality");
		if(texQuality) {
			switch(texQuality->getInteger()) {
				case 0: maxTexSize = 256; break;
				case 1: maxTexSize = 512; break;
				case 2: maxTexSize = 1024; break;
				case 3: maxTexSize = 2048; break;
				case 4: maxTexSize = 4096; break;
				default:
				case 5: maxTexSize = 8192; break;
			}
		}
		else {
			maxTexSize = 65536;
		}
	}

	return maxTexSize * maxTexSize;
}

bool Library::processImages(int maxPriority, int amount) {
	bool processedAny = false;
	int processed = 0;
	while(!queuedImages.empty()) {
		queuedImagesLock.lock();
		if(queuedImages.empty()) {
			queuedImagesLock.release();
			break;
		}

		auto elem = queuedImages.top();
		if(elem.priority < maxPriority) {
			queuedImagesLock.release();
			break;
		}

		if(elem.tex)
			textures.push_back(elem.tex);

		queuedImages.pop();
		queuedImagesLock.release();

		if(cancelAssets)
			continue;

		processedAny = true;

		if(!elem.filename.empty()) {
			Image* img = loadImage(elem.filename.c_str());

			if(!img) {
				error("Error: Could not load image '%s'", elem.filename.c_str());
				continue;
			}

			unsigned texSize = getMaxTextureSize();
			while(img->width * img->height > texSize) {
				auto* prev = img;
				img = img->makeMipmap();
				delete prev;
			}

			elem.images.push_back(img);

			//Loading images this way causes weirdness
			/*if(elem.mipmap && img->width * img->height > DRIVER_MIPMAP_SIZE) {
				while(img->width > 2 && img->height > 2) {
					img = img->makeMipmap();
					if(img)
						elem.images.push_back(img);
					else
						break;
				}
			}*/
		}

		++processed;

		queuedTexturesLock.lock();
		queuedTextures.push(elem);
		queuedTexturesLock.release();

		if(processed >= amount)
			break;
	}

	return processedAny;
}

bool Library::hasQueuedTextures() {
	return !queuedTextures.empty();
}

bool QueuedTexture::load(unsigned maxBytes, unsigned& loadedBytes) {
	if(images.empty())
		return true;
	if(!tex) {
		clearImages();
		return true;
	}

	if(loadedBytes >= maxBytes)
		return false;
	
	Image* img = images.front();
	unsigned rowBytes = img->width * ColorDepths[img->format];
	unsigned loadRows = (maxBytes - loadedBytes) / rowBytes;
	if(loadRows == 0)
		loadRows = 1;
	if(loadRows > img->height - row)
		loadRows = img->height - row;
	loadedBytes += rowBytes * loadRows;

	if(lod == 0/* && loadRows == img->height && img->width * img->height <= DRIVER_MIPMAP_SIZE*/) {
		tex->load(*img, mipmap, cachePixels);
		clearImages();
		return true;
	}
	else {
		if(row == 0)
			tex->loadStart(*img, mipmap, cachePixels, lod);
		tex->loadPartial(*img, recti(0, row, img->width, row+loadRows), cachePixels, lod);
		row += loadRows;

		if(row == img->height) {
			delete img;
			images.erase(images.begin());

			tex->loadFinish(mipmap && images.empty(), lod);
			if(!mipmap || images.empty())
				return true;

			//Reset for the next LOD
			lod += 1;
			row = 0;
			return load(maxBytes, loadedBytes);
		}
	}

	return false;
}

bool Library::processTextures(int maxPriority, bool singleFrame) {
	bool processedAny = false;
	const unsigned frameByteLimit = 1024 * 1024 * 4;
	int64_t byteLimit = singleFrame ? frameByteLimit : 0xffffffff;

	while(!queuedTextures.empty()) {
		queuedTexturesLock.lock();
		if(queuedTextures.empty()) {
			queuedTexturesLock.release();
			break;
		}


		auto tex = queuedTextures.top();
		if(tex.priority < maxPriority) {
			queuedTexturesLock.release();
			break;
		}

		queuedTextures.pop();

		//Track filenames even if we can't load the resource at the moment, in case the file is created while we're running
		if(tex.tex && !tex.filename.empty())
			texture_files[tex.filename] = tex.tex;

		queuedTexturesLock.release();

		if(cancelAssets)
			continue;

		processedAny = true;
		
		unsigned loaded = 0;
		if(!tex.load(byteLimit, loaded)) {
			threads::Lock lock(queuedTexturesLock);
			queuedTextures.push(tex);
		}

		byteLimit -= (int64_t)loaded;

		if(byteLimit <= 0)
			break;
	}

	return processedAny;
}

render::Texture* queueImage(const std::string& abs_file, int priority = -20, bool mipmap = true, bool cachePixels = false, bool cubemap = false) {
	bool queue = false;
	render::Texture* tex;
	{
		texIdentLock.lock();
		render::Texture*& pTex = texNames[abs_file];
		if(pTex == 0) {
			if(cubemap)
				pTex = render::RenderDriver::createCubemap();
			else
				pTex = render::RenderDriver::createTexture();
			queue = true;
		}
		tex = pTex;
		texIdentLock.release();
	}

	if(queue) {
		queuedImagesLock.lock();
		resource::QueuedTexture queued = resource::QueuedTexture(tex, priority, abs_file, mipmap, cachePixels);
		queuedImages.push(queued);
		queuedImagesLock.release();
	}

	return tex;
}

render::Texture* queueImage(Image* img, int priority, bool mipmap, bool cachePixels) {
	render::Texture* tex = render::RenderDriver::createTexture();

	queuedTexturesLock.lock();
	resource::QueuedTexture queued = resource::QueuedTexture(tex, priority, img, mipmap, cachePixels);
	queuedTextures.push(queued);
	queuedTexturesLock.release();

	return tex;
}

void queueTextureUpdate(render::Texture* tex, Image* img, int priority, bool mipmap, bool cachePixels) {
	queuedTexturesLock.lock();
	resource::QueuedTexture queued = resource::QueuedTexture(tex, priority, img, mipmap, cachePixels);
	queuedTextures.push(queued);
	queuedTexturesLock.release();
}

void Library::loadMaterials(const std::string& filename) {
	DataHandler datahandler;

	render::RenderState* state = nullptr;
	render::SpriteSheet* sheet = nullptr;
	render::MaterialGroup* group = nullptr;
	std::string matName;
	int priority = -61;
	bool texdefs = false;

	//Initialization handling
	datahandler("SpriteSheet", [&](std::string& value) {
		matName = value;
		priority = -61;
		group = nullptr;
		sheet = new render::SpriteSheet();
		state = &sheet->material;
		spritesheets[matName] = sheet;
		sheet_indices[sheet] = (unsigned)spritesheet_names.size();
		spritesheet_names.push_back(matName);
		texdefs = false;
	});

	datahandler("Material", [&](std::string& value) {
		matName = value;
		sheet = 0;
		group = nullptr;
		priority = -61;
		if(materials.find(matName) != materials.end()) {
			error("Duplicate material: %s", matName.c_str());
			state = materials[matName];
			*state = render::RenderState();
		}
		else {
			state = new render::RenderState();
			state->constant = true;
		}

		materials[matName] = state;
		mat_indices[state] = (unsigned)material_names.size();
		material_names.push_back(matName);
		texdefs = false;
	});

	datahandler("MaterialGroup", [&](std::string& value) {
		matName = value;
		sheet = nullptr;
		state = nullptr;
		group = new render::MaterialGroup();
		group->prefix = value + "_";
		matGroups[value] = group;
	});

	datahandler("Template", [&](std::string& value) {
		if(!group)
			return;

		auto it = materials.find(value);
		if(it != materials.end())
			group->base = *it->second;
		else
			error("Could not find template material '%s' for '%s'", value.c_str(), matName.c_str());
	});

	datahandler("Prefix", [&](std::string& value) {
		if(!group)
			return;

		group->prefix = value;
	});

	datahandler("Folder", [&](std::string& value) {
		if(!group)
			return;

		auto& g = *group;
		auto& mats = materials;
		auto& inds = mat_indices;
		auto& names = material_names;
		int texPriority = priority;

		devices.mods.listFiles(value, "*.png", [&](const std::string& filename) {
			std::string id = g.prefix + getBasename(filename, false);
			makeIdentifier(id);
			auto* mat = new render::RenderState();

			*mat = g.base;
			mat->constant = true;

			mats[id] = mat;
			inds[mat] = (unsigned)names.size();
			names.push_back(id);

			g.names.push_back(id);
			g.materials.push_back(mat);

			if(load_resources) {
				mat->textures[0] = queueImage(filename, texPriority, mat->mipmap, mat->cachePixels);
				if(watch_resources)
					devices.library.watchTexture(filename);
			}
		}, true);
	});

	datahandler("Inherit", [&](std::string& value) {
		if(!state)
			return;

		auto it = materials.find(value);
		if(it != materials.end())
			*state = *it->second;
		else
			error("Could not find material '%s' to inherit for '%s'", value.c_str(), matName.c_str());
	});

	//Renderstate members
	HANDLE_BOOL(datahandler, "DepthWrite", state, depthWrite);
	HANDLE_ENUM(datahandler, "DepthTest", state, depthTest, depthTests);
	HANDLE_ENUM(datahandler, "Culling", state, culling, cullingModes);
	HANDLE_BOOL(datahandler, "Lighting", state, lighting);
	HANDLE_BOOL(datahandler, "NormalizeNormals", state, normalizeNormals);
	HANDLE_ENUM_W(datahandler, "Shader", state, shader, shaders, load_resources);
	HANDLE_NUM(datahandler, "Shininess", state, shininess);
	HANDLE_ENUM(datahandler, "WrapVertical", state, wrapVertical, textureWraps);
	HANDLE_ENUM(datahandler, "WrapHorizontal", state, wrapHorizontal, textureWraps);
	HANDLE_ENUM(datahandler, "FilterMin", state, filterMin, textureFilters);
	HANDLE_ENUM(datahandler, "FilterMag", state, filterMag, textureFilters);
	HANDLE_ENUM(datahandler, "DrawMode", state, drawMode, drawModes);
	HANDLE_ENUM(datahandler, "Blend", state, baseMat, baseMats);

	datahandler("Mipmap", [&](std::string& value) {
		if(!state)
			return;
		if(texdefs) {
			warn("Warning: Mipmap statement should be before texture"
				" declarations.\n    %s", datahandler.position().c_str());
		}
		state->mipmap = toBool(value);
	});

	datahandler("CachePixels", [&](std::string& value) {
		if(!state)
			return;
		state->cachePixels = toBool(value);
	});

	datahandler("LoadPriority", [&](std::string& value) {
		if(value == "Critical" || value == "Menu")
			priority = 10;
		else if(value == "Game")
			priority = -10;
		else if(value == "High")
			priority = -31;
		else if(value == "Low")
			priority = -91;
		else
			priority = -111 + toNumber<int>(value);
	});

	datahandler("Alpha", [&](std::string& value) {
		if(!state)
			return;

		if(toBool(value))
			state->baseMat = render::MAT_Alpha;
		else
			state->baseMat = render::MAT_Solid;
	});

	datahandler("Diffuse", [&](std::string& value) {
		int r,g,b,a;
		if(int args = sscanf(value.c_str(),"#%2x%2x%2x%2x", &r,&g,&b,&a)) {
			if(args == 3)
				state->diffuse = Colorf(Color(r,g,b));
			else if(args == 4)
				state->diffuse = Colorf(Color(r,g,b,a));
		}
		else {
			sscanf(value.c_str(), "%f,%f,%f,%f", &state->diffuse.r, &state->diffuse.g, &state->diffuse.b, &state->diffuse.a);
		}
	});

	datahandler("Specular", [&](std::string& value) {
		int r,g,b,a;
		if(int args = sscanf(value.c_str(),"#%2x%2x%2x%2x", &r,&g,&b,&a)) {
			if(args == 3)
				state->specular = Colorf(Color(r,g,b));
			else if(args == 4)
				state->specular = Colorf(Color(r,g,b,a));
		}
		else {
			sscanf(value.c_str(), "%f,%f,%f,%f", &state->specular.r, &state->specular.g, &state->specular.b, &state->specular.a);
		}
	});

	//Spritesheet members
	HANDLE_ENUM(datahandler, "Mode", sheet, mode, spriteModes);

	datahandler("Size", [&](std::string& value) {
		if(!sheet)
			return;

		std::vector<std::string> args;
		split(value, args, ',');

		if(args.size() != 2)
			return;

		sheet->width = toNumber<int>(args[0]);
		sheet->height = toNumber<int>(args[1]);
	});

	datahandler("Spacing", [&](std::string& value) {
		if(!sheet)
			return;

		sheet->spacing = toNumber<int>(value);
	});

	datahandler.defaultHandler([&](std::string& key, std::string& value) {
		if(key.size() >= 7 && (key.compare(0, 7, "Texture") == 0 || key.compare(0, 7, "Cubemap") == 0)) {
			//Figure out the texture number to set
			int texNum = 0;
			texdefs = true;
			if (key.size() > 7) {
				std::string num = key.substr(7, key.size() - 7);
				texNum = min_(toNumber<int>(num)-1, RENDER_MAX_TEXTURES);
			}

			value = getAbsolutePath( devices.mods.resolve(value) );
			if(load_resources) {
				state->textures[texNum] = queueImage(value, priority, state->mipmap, state->cachePixels, key[0] == 'C');
				if(watch_resources)
					watchTexture(value);
			}
		}
	});

	datahandler.read(filename);
}

std::string Library::getSpriteDesc(const render::Sprite& sprt) const {
	std::string ret;
	if(sprt.mat) {
		auto it = mat_indices.find(sprt.mat);
		if(it != mat_indices.end())
			ret = material_names[it->second];
	}
	else {
		auto it = sheet_indices.find(sprt.sheet);
		if(it == sheet_indices.end())
			return ret;
		ret += spritesheet_names[it->second];
		ret += "::";
		ret += toString(sprt.index);
	}
	if(sprt.color.color != 0xffffffff) {
		ret += "*";
		ret += toString(sprt.color);
	}
	return ret;
}

};
