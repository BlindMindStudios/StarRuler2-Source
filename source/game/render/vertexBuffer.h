#pragma once
#include "vec3.h"
#include "vec2.h"
#include "color.h"
#include <vector>
#include <deque>

namespace scene {
	class Node;
};

namespace render {
	struct RenderState;

	extern unsigned vbFloatLimit, vbMaxSteps;

	enum FlushCause {
		FC_Forced,
		FC_VertexLimit,
		FC_StepLimit,
		FC_ShaderLimit,
		FC_COUNT
	};

	extern unsigned vbFlushCounts[FC_COUNT];

	struct RenderStep {
		const RenderState* material;
		float* shaderCache;
		unsigned short indexOffset;
		unsigned short vertStart, vertEnd;
		bool lines;
	};

	struct VertexTCV {
		vec2f uv;
		Color col;
		vec3f pos;

		inline void set(const vec3f& Pos) {
			col = Color();
			uv = vec2f();
			pos = Pos;
		}

		inline void set(const vec2f& UV) {
			col = Color();
			uv = UV;
			pos = vec3f();
		}

		inline void set(Color Col) {
			col = Col;
			uv = vec2f();
			pos = vec3f();
		}

		inline void set(const vec3f& Pos, const vec2f& UV) {
			col = Color();
			uv = UV;
			pos = Pos;
		}

		inline void set(const vec3f& Pos, const vec2f& UV, Color Col) {
			col = Col;
			uv = UV;
			pos = Pos;
		}
	};

	struct VertexCV {
		Color col;
		vec3f pos;
	};

	struct VertexTV {
		vec2f uv;
		vec3f pos;
	};

	class VertexBufferTCV {
		RenderStep* last;
		std::deque<unsigned> vertBuffer, indBuffer;
		std::vector<VertexTCV> vertices;
		std::vector<unsigned short> indices;
		std::vector<RenderStep> steps;
		float* shaderBuffer, *pNextShaderBuffer;
		unsigned shaderBufferSize;

		void flushRetainingLast(FlushCause reason);
		void duplicateLast();

	public:
		static VertexBufferTCV* fetch(const RenderState* mat);
		VertexTCV* request(unsigned polygons, unsigned polyType);
		void draw(FlushCause reason = FC_Forced);

		VertexBufferTCV();
		~VertexBufferTCV();
	};

	//Renders out all pending vertex buffers
	void renderVertexBuffers();

};