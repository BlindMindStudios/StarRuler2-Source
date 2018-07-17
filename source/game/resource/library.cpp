#include "render/render_state.h"
#include "main/references.h"
#include "resource/library.h"
#include "scene/particle_system.h"
#include "ISoundSource.h"
#include "files.h"
#include "str_util.h"
#include "num_util.h"
#include <iostream>
#include <fstream>
#include <string>

namespace resource {

void Library::clear() {
	foreach(mat, materials)
		delete mat->second;
	materials.clear();
	material_names.clear();

	foreach(mat, matGroups)
		delete mat->second;
	matGroups.clear();

	foreach(sheet, spritesheets)
		delete sheet->second;
	spritesheets.clear();
	spritesheet_names.clear();

	foreach(tex, textures)
		delete *tex;
	textures.clear();
	texture_files.clear();
	clearTextures();

	foreach(mesh, meshes)
		if(mesh->second != errors.mesh)
			delete mesh->second;
	meshes.clear();

	foreach(shader, shaders)
		delete shader->second;
	shaders.clear();
	settingsShaders.clear();

	foreach(program, programs)
		delete program->second;
	programs.clear();

	foreach(font, font_list)
		delete *font;
	font_list.clear();
	fonts.clear();

	foreach(skin, skins)
		delete skin->second;
	skin_files.clear();
	skins.clear();

	foreach(sound, sounds)
		delete sound->second;
	sounds.clear();

	clearWatchedResources();

	delete errors.texture;
	errors.texture = 0;
	errors.material.textures[0] = 0;

	delete errors.mesh;
	errors.mesh = 0;

	mat_indices.clear();
}
void Library::prepErrorResources() {
	if(!devices.render) {
		errors.material.constant = true;
		errors.mesh = new ErrorMesh();
		return;
	}

	errors.particleSystem = scene::createDummyParticleSystem();

	errors.material.constant = true;
	errors.material.lighting = false;

	errors.skin.materialName = "~invalid_skin";
	errors.mesh = devices.render->createMesh(Mesh());

	render::RenderState* img2d = new render::RenderState();
	img2d->baseMat = render::MAT_Alpha;
	img2d->lighting = false;
	img2d->depthTest = render::DT_NoDepthTest;
	img2d->depthWrite = false;
	img2d->constant = true;
	materials["Image2D"] = img2d;
	material_names.push_back("Image2D");
	mat_indices[img2d] = material_names.size();
}

void Library::generateErrorResources() {
	if(!devices.render)
		return;

	{ //Checkboard error image
		Image img(64,64,FMT_RGB);
		for(unsigned r = 0; r < 64; ++r)
			for(unsigned x = 0; x < 64; ++x)
				img.rgb[x+(r*64)] = (x/2 % 2) ^ (r/2 % 2) ? ColorRGB(0,0,0) : ColorRGB(255,0,255);
		errors.texture = devices.render->createTexture(img);
		errors.material.textures[0] = errors.texture;
	}

	{ //Tetrahedron error mesh
		Mesh mesh;
		mesh.vertices.push_back( Vertex(vec3f(0,1,0)) );
		mesh.vertices.push_back( Vertex(vec3f(1,0,0)) );
		mesh.vertices.push_back( Vertex(vec3f(-1,0,1)) );
		mesh.vertices.push_back( Vertex(vec3f(-1,0,-1)) );
		
		mesh.faces.push_back(Mesh::Face(0,1,2));
		mesh.faces.push_back(Mesh::Face(0,2,3));
		mesh.faces.push_back(Mesh::Face(0,3,1));
		mesh.faces.push_back(Mesh::Face(1,2,3));

		errors.mesh->resetToMesh(mesh);
	}
}

void Library::load(ResourceType type, const std::string& filename) {
	switch(type) {
	case RT_Sound:
		loadSounds(filename);
	break;
	case RT_Material:
	case RT_SpriteSheet:
		loadMaterials(filename);
	break;
	case RT_Mesh:
		loadModels(filename);
	break;
	case RT_Font:
		loadFonts(filename);
	break;
	case RT_Shader:
		loadShaders(filename);
	break;
	case RT_Skin:
		loadSkins(filename);
	break;
	case RT_ParticleSystem:
		{
			auto* pSys = scene::loadParticleSystem(filename);
			if(pSys)
				particleSystems[getBasename(filename,false)] = pSys;
		}
	break;
	}
}

void Library::loadDirectory(ResourceType type, const std::string& filename) {
	std::vector<std::string> files;
	std::string dirname(filename);

	listDirectory(dirname, files);
	foreach(it, files) {
		std::string& file = *it;
		if(file.size() < 4)
			continue;
		if(!file.compare(file.size() - 4, 4, ".txt"))
			load(type, path_join(dirname, file));
	}
}

Library::ResourceAccessor Library::operator[](const char* name) const {
	ResourceAccessor access;
	access.source = this;
	access.name = name;
	return access;
}

#define access_ref(type, func) \
	Library::ResourceAccessor::operator const type &() { return source->func(name); }\
	Library::ResourceAccessor::operator const type *() { return &source->func(name); }

#define access_ptr(type, func) \
	Library::ResourceAccessor::operator const type &() { return *source->func(name); }\
	Library::ResourceAccessor::operator const type *() { return source->func(name); }

access_ref(render::RenderMesh, getMesh);
access_ref(render::RenderState, getMaterial);
access_ref(render::Font, getFont);
access_ref(render::SpriteSheet, getSpriteSheet);
access_ref(gui::skin::Skin, getSkin);

access_ptr(Sound, getSound);
access_ptr(render::Shader, getShader);

const render::RenderState& Library::getErrorMaterial() const {
	return errors.material;
}

const render::Texture* Library::getErrorTexture() const {
	return errors.texture;
}

const render::SpriteSheet& Library::getErrorSpriteSheet() const {
	return errors.spriteSheet;
}

const render::RenderState& Library::getMaterial(const std::string& name) const {
	auto mat = materials.find(name);
	if(mat == materials.end())
		return errors.material;
	else
		return *mat->second;
}

const render::MaterialGroup& Library::getMaterialGroup(const std::string& name) const {
	auto mat = matGroups.find(name);
	if(mat == matGroups.end())
		return errors.group;
	else
		return *mat->second;
}

const render::SpriteSheet& Library::getSpriteSheet(const std::string& name) const {
	auto sheet = spritesheets.find(name);
	if(sheet == spritesheets.end())
		return errors.spriteSheet;
	else
		return *sheet->second;
}

const render::RenderMesh& Library::getMesh(const std::string& name) const {
	auto mesh = meshes.find(name);
	if(mesh == meshes.end())
		return *errors.mesh;
	else
		return *mesh->second;
}

const gui::skin::Skin& Library::getSkin(const std::string& name) const {
	auto skin = skins.find(name);
	if(skin == skins.end())
		return errors.skin;
	else
		return *skin->second;
}

const scene::ParticleSystemDesc* Library::getParticleSystem(const std::string& name) const {
	auto sys = particleSystems.find(name);
	if(sys == particleSystems.end())
		return errors.particleSystem;
	else
		return sys->second;
}


//TODO: Decide how to handle the error font (it should still render some text)
const render::Font& Library::getFont(const std::string& name) const {
	auto font = fonts.find(name);
	if(font == fonts.end())
		return *fonts.begin()->second;
	else
		return *font->second;
}

const render::Shader* Library::getShader(const std::string& name) const {
	auto shader = shaders.find(name);
	if(shader == shaders.end())
		return 0;
	else
		return shader->second;
}

const Sound* Library::getSound(const std::string& name) const {
	auto sound = sounds.find(name);
	if(sound == sounds.end())
		return 0;
	else
		return sound->second;
}

render::Sprite Library::getSprite(const std::string& desc) {
	render::Sprite sprt;
	std::string tmp = desc;
	auto pos = desc.find("*");
	if(pos != std::string::npos && pos < tmp.size() - 1) {
		sprt.color = toColor(trim(tmp.substr(pos+1)));
		tmp = trim(tmp.substr(0, pos));
	}
	pos = tmp.find("::");
	if(pos == std::string::npos || pos >= tmp.size() - 2) {
		auto sheet = spritesheets.find(tmp);
		if(sheet != spritesheets.end()) {
			sprt.sheet = sheet->second;
			sprt.index = 0;
		}
		else {
			auto img = materials.find(tmp);
			if(img != materials.end()) {
				sprt.mat = img->second;
		}
		}
	}
	else {
		sprt.sheet = &getSpriteSheet(tmp.substr(0, pos));
		sprt.index = toNumber<unsigned>(tmp.substr(pos+2));
	}
	return sprt;
}

};
