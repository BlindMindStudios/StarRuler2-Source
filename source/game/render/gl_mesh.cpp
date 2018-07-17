#include "compat/gl.h"
#include "vertex.h"
#include "vec3.h"
#include "mesh.h"
#include "render/render_mesh.h"
#include "render/gl_mesh.h"
#include "render/driver.h"
#include "main/references.h"

#include <assert.h>

namespace render {

bool vertexArraysAvailable = false, vertArraysChecked = false;

bool useVertexArrays() {
	if(vertArraysChecked)
		return vertexArraysAvailable;

	vertexArraysAvailable = GLEW_ARB_vertex_array_object;
	vertArraysChecked = true;
	return vertexArraysAvailable;
}

const RenderMesh* lastRenderedMesh = 0;

class GLMesh : public RenderMesh {
	bool valid;
public:
	GLuint vertex_buffer;
	GLuint element_buffer;
	GLuint tangent_buffer;
	GLuint color_buffer;
	GLuint uv2_buffer;

	GLuint vertex_array;

	unsigned int vertices;
	unsigned int faces;

	AABBoxf bbox;
	Mesh mesh;

	double lod_distance;
	const RenderMesh* lod;

	GLMesh() : valid(false), lod_distance(1), lod(0), tangent_buffer(0), vertex_array(0), color_buffer(0), uv2_buffer(0) {
	}

	GLMesh(const Mesh& mesh) : valid(false), lod_distance(1), lod(0), tangent_buffer(0), vertex_array(0), color_buffer(0), uv2_buffer(0) {
		resetToMesh(mesh);
	}

	~GLMesh() {
		clear();
	}

	const Mesh& getMesh() const {
		return mesh;
	}

	void clear() {
		if(!valid)
			return;
		
		glDeleteVertexArrays(1, &vertex_array);
		glDeleteBuffers(1, &vertex_buffer);
		glDeleteBuffers(1, &element_buffer);
		if(tangent_buffer != 0) {
			glDeleteBuffers(1, &tangent_buffer);
			tangent_buffer = 0;
		}
		if(color_buffer != 0) {
			glDeleteBuffers(1, &color_buffer);
			color_buffer = 0;
		}
		if(uv2_buffer != 0) {
			glDeleteBuffers(1, &uv2_buffer);
			uv2_buffer = 0;
		}

		valid = false;
	}

	void setupBuffers() const {
		glDisableClientState(GL_VERTEX_ARRAY);
		glDisableClientState(GL_COLOR_ARRAY);
		glDisableClientState(GL_TEXTURE_COORD_ARRAY);

		glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
		glEnableVertexAttribArray(0);
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex,position));

		glEnableVertexAttribArray(1);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex,u));

		glEnableVertexAttribArray(2);
		glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex,normal));

		if(tangent_buffer) {
			glBindBuffer(GL_ARRAY_BUFFER, tangent_buffer);
			glEnableVertexAttribArray(3);
			glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, sizeof(vec4f), nullptr);
		}
		else {
			glDisableVertexAttribArray(3);
		}

		if(color_buffer) {
			glBindBuffer(GL_ARRAY_BUFFER, color_buffer);
			glEnableVertexAttribArray(4);
			glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, sizeof(Colorf), nullptr);
		}
		else {
			glDisableVertexAttribArray(4);
		}

		if(uv2_buffer) {
			glBindBuffer(GL_ARRAY_BUFFER, uv2_buffer);
			glEnableVertexAttribArray(5);
			glVertexAttribPointer(5, 4, GL_FLOAT, GL_FALSE, sizeof(vec4f), nullptr);
		}
		else {
			glDisableVertexAttribArray(5);
		}

		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, element_buffer);
	}

	void resetToMesh(const Mesh& mesh) {
		this->mesh = mesh;
		clear();

		if(mesh.vertices.empty() || mesh.faces.empty())
			return;

		devices.render->reportErrors();

		// Generate vertex buffer
		vertices = (unsigned)mesh.vertices.size();
		glGenBuffers(1, &vertex_buffer);
		glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
		glBufferData(GL_ARRAY_BUFFER, vertices * sizeof(Vertex),
					 &mesh.vertices[0], GL_STATIC_DRAW);

		if(!mesh.tangents.empty()) {
			glGenBuffers(1, &tangent_buffer);
			glBindBuffer(GL_ARRAY_BUFFER, tangent_buffer);
			glBufferData(GL_ARRAY_BUFFER, mesh.tangents.size() * sizeof(vec4f), mesh.tangents.data(), GL_STATIC_DRAW);
		}

		if(!mesh.colors.empty()) {
			glGenBuffers(1, &color_buffer);
			glBindBuffer(GL_ARRAY_BUFFER, color_buffer);
			glBufferData(GL_ARRAY_BUFFER, mesh.colors.size() * sizeof(Colorf), mesh.colors.data(), GL_STATIC_DRAW);
		}

		if(!mesh.uvs2.empty()) {
			glGenBuffers(1, &uv2_buffer);
			glBindBuffer(GL_ARRAY_BUFFER, uv2_buffer);
			glBufferData(GL_ARRAY_BUFFER, mesh.uvs2.size() * sizeof(vec4f), mesh.uvs2.data(), GL_STATIC_DRAW);
		}
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		// Generate element buffer
		faces = (unsigned)mesh.faces.size();
		glGenBuffers(1, &element_buffer);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, element_buffer);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, faces * sizeof(Mesh::Face),
					 &mesh.faces[0], GL_STATIC_DRAW);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

		devices.render->reportErrors("Filling mesh buffers");

		if(useVertexArrays()) {
			glGenVertexArrays(1, &vertex_array);
			glBindVertexArray(vertex_array);
			setupBuffers();
			glBindVertexArray(0);

			devices.render->reportErrors("Setting up mesh vertex array");
		}

		//Generate Bounding Box
		for(unsigned i = 0; i < vertices; ++i)
			bbox.addPoint(mesh.vertices[i].position);

		valid = true;
	}
	
	const RenderMesh* selectLOD(double distance) const {
		if(lod && distance > lod_distance)
			return lod->selectLOD(distance);
		return this;
	}

	void setLOD(double distance, const RenderMesh* mesh) {
		lod_distance = distance;
		lod = mesh;
	}

	const AABBoxf& getBoundingBox() const {
		return bbox;
	}

	unsigned getMeshBytes() const {
		if(!valid)
			return 0;

		return (vertices * sizeof(float) * 8) + (faces * 3 * sizeof(short));
	}

	void render() const {
		if(lastRenderedMesh != this) {
			//We only need to check valid here, because we can't be the rendered mesh if we aren't valid
			if(!valid)
				return;
			lastRenderedMesh = this;
			if(vertex_array)
				glBindVertexArray(vertex_array);
			else
				setupBuffers();
		}

		glDrawElements(
			GL_TRIANGLES, //Mode
			3 * faces, //Total amount of vertices
			GL_UNSIGNED_SHORT, //Index type
			(void*)0 //Offset
		);
	}
};

RenderMesh* createGLMesh(const Mesh& mesh) {
	return new GLMesh(mesh);
}

};
