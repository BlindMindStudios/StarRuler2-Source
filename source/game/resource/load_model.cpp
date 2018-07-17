#include "main/references.h"
#include "main/initialization.h"
#include "main/logging.h"
#include "render/render_mesh.h"
#include "resource/library.h"
#include "str_util.h"
#include "num_util.h"
#include "util/mesh_generation.h"
#include "threads.h"
#include "files.h"
#include <iostream>
#include <fstream>
#include <string>
#include <tuple>

#include "render/x_loader.h"
#include "render/obj_loader.h"
#include "render/bmf_loader.h"
#include "render/ogex_loader.h"

bool useModelCache = false;
extern bool cancelAssets;

namespace resource {


threads::Signal unqueuedMeshes;

threads::Mutex queuedMeshLock;
std::vector<std::tuple<Mesh*,render::RenderMesh*>> queuedMeshes;

bool Library::hasQueuedMeshes() {
	return !unqueuedMeshes.check(0) || !queuedMeshes.empty();
}

bool Library::processMeshes(int maxPriority, int amount) {
	if(queuedMeshes.empty())
		return false;

	//TODO: Probably this has a race condition (threads end while this loop is running)
	queuedMeshLock.lock();
	while(!queuedMeshes.empty()) {
		auto& pair = queuedMeshes.back();
		std::get<1>(pair)->resetToMesh( *std::get<0>(pair) );
		delete std::get<0>(pair);
		queuedMeshes.pop_back();
	}
	queuedMeshLock.release();

	return true;
}

struct MeshLoadData {
	bool isSphere;
	bool makeTangents;
	std::string fileName;
	unsigned width, height;
	
	render::RenderMesh* rMesh;
	const render::RenderMesh* lodMesh;
	double lodDist;

	MeshLoadData() : isSphere(false), makeTangents(false), width(0), height(0), lodMesh(0), lodDist(1) { }
};

threads::atomic_int activeMeshThreads;

threads::threadreturn threadcall LoadMesh(void* loadData) {
	MeshLoadData& data = *(MeshLoadData*)loadData;

	Mesh* mesh = 0;

	while(++activeMeshThreads > 4) {
		--activeMeshThreads;
		threads::sleep(5);
	}

	if(cancelAssets) {	
		--activeMeshThreads;
		unqueuedMeshes.signalDown();
		delete &data;
		return 0;
	}


	//Create raw mesh
	if(data.isSphere) {
		mesh = generateSphereMesh(data.height, data.width);
	}
	else {
		mesh = new Mesh();
		//TODO: Make work if multiple meshes happen to have the same name, especially on Windows
		std::string cacheModel = devices.mods.getProfile("model_cache") + "/" + getBasename(data.fileName);
		std::string sourceModel = devices.mods.resolve(data.fileName);

		if(useModelCache && fileExists(cacheModel) && (getModifiedTime(cacheModel) - getModifiedTime(sourceModel)) >= 0) {
			render::loadBinaryMesh(cacheModel.c_str(), *mesh);
			if(mesh->faces.empty())
				goto failedCache;
		}
		else {
failedCache:
			if(fileExists(sourceModel)) {
				if(match(sourceModel.c_str(), ".x"))
					render::loadMeshX(sourceModel.c_str(), *mesh);
				else if(match(sourceModel.c_str(), ".ogex"))
					render::loadMeshOGEX(sourceModel.c_str(), *mesh);
				else
					render::loadMeshOBJ(sourceModel.c_str(), *mesh);

				if(!mesh->faces.empty() && useModelCache)
					render::saveBinaryMesh(cacheModel.c_str(), *mesh);
			}
			else {
				error("Could not find model file '%s'", sourceModel.c_str());
			}
		}
	}

	if(!mesh || mesh->faces.empty())
		error("Could not load mesh '%s'", data.fileName.c_str());

	//Queue mesh for the main thread to generate the GL mesh
	if(mesh) {
		//Calculate tangents and binormals
		if(data.makeTangents) {
			mesh->tangents.resize(mesh->vertices.size());
			std::vector<vec3f> binormals(mesh->vertices.size());

			for(auto i = mesh->faces.begin(), end = mesh->faces.end(); i != end; ++i) {
				auto& face = *i;
				
				auto& a = mesh->vertices[face.a];
				auto& b = mesh->vertices[face.b];
				auto& c = mesh->vertices[face.c];

				vec3f d1 = b.position - a.position;
				vec3f d2 = c.position - a.position;
				
				vec2f s = vec2f(b.u - a.u, c.u - a.u);
				vec2f t = vec2f(b.v - a.v, c.v - a.v);

				float r = (s.x * t.y - s.y * t.x);
				if(r < 0.0001f && r > -0.0001f)
					continue;
				r = 1.f / r;
				vec3f bnDir = ((d2 * s.x) - (d1 * s.y)) * r;
				vec3f td = ((d1 * t.y) - (d2 * t.x)) * r;

				vec4f tanDir = vec4f(td.x, td.y, td.z, 0.f);
				
				mesh->tangents[face.a] += tanDir; if(mesh->tangents[face.a].zero()) mesh->tangents[face.a] = tanDir;
				mesh->tangents[face.b] += tanDir; if(mesh->tangents[face.b].zero()) mesh->tangents[face.b] = tanDir;
				mesh->tangents[face.c] += tanDir; if(mesh->tangents[face.c].zero()) mesh->tangents[face.c] = tanDir;
				
				binormals[face.a] += bnDir; if(binormals[face.a].zero()) binormals[face.a] = bnDir;
				binormals[face.b] += bnDir; if(binormals[face.b].zero()) binormals[face.b] = bnDir;
				binormals[face.c] += bnDir; if(binormals[face.c].zero()) binormals[face.c] = bnDir;
			}

			for(unsigned i = 0; i < mesh->vertices.size(); ++i) {
				auto& vertex = mesh->vertices[i];
				auto& tangent = mesh->tangents[i];

				vec3f t = vec3f(tangent.x, tangent.y, tangent.z);

				bool handedness = (vertex.normal.cross(t).dot(binormals[i]) > 0.f);

				//Restrict to tangent plane
				t = (t - vertex.normal * vertex.normal.dot(t)).normalized();
				
				tangent.x = t.x;
				tangent.y = t.y;
				tangent.z = t.z;
				tangent.w = handedness ? 1.f : -1.f;
			}
		}

		if(!mesh->colors.empty() && mesh->colors.size() < mesh->vertices.size())
			mesh->colors.resize(mesh->vertices.size());

		//TODO: Handle an invalid mesh being loaded (the referenced mesh must be valid, but we have no data to load in)
		if(data.lodMesh)
			data.rMesh->setLOD(data.lodDist, data.lodMesh);
		queuedMeshLock.lock();
		queuedMeshes.push_back(std::tuple<Mesh*,render::RenderMesh*>(mesh,data.rMesh));
		queuedMeshLock.release();
	}
	
	--activeMeshThreads;

	unqueuedMeshes.signalDown();
	delete &data;
	return 0;
}

void Library::loadModels(const std::string& filename) {
	MeshLoadData* meshData = 0;

	DataHandler datahandler;

	auto makeModel = [&](bool final) {
		if(load_resources && meshData) {
			unqueuedMeshes.signalUp();
			threads::createThread(LoadMesh,meshData);
		}

		if(!final)
			meshData = new MeshLoadData();
	};

	datahandler("Model", [&](std::string& value) {
		makeModel(false);
		if(load_resources)
			meshData->rMesh = devices.render->createMesh(Mesh());
		else
			meshData->rMesh = errors.mesh;
		
		meshes[value] = meshData->rMesh;
	});

	datahandler("Mesh", [&](std::string& value) {
		meshData->fileName = value;
	});

	datahandler("Tangents", [&](std::string& value) {
		meshData->makeTangents = toBool(value, true);
	});

	datahandler("Sphere", [&](std::string& value) {
		if(sscanf(value.c_str(), "%d x %d", &meshData->width, &meshData->height) == 2 && meshData->width > 0 && meshData->height > 0 && meshData->width*meshData->height < 256*256)
			meshData->isSphere = true;
	});

	datahandler("LOD", [&](std::string& value) {
		char name[256];

		if(sscanf(value.c_str(), " %255s > %lf", name, &meshData->lodDist) == 2)
			meshData->lodMesh = &getMesh(name);
	});

	datahandler.read(filename);
	makeModel(true);
}

};
