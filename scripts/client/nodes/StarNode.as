
//Draws the physical star, its corona, and a distant star sprite
final class StarNodeScript {
	//double coronaRot = randomd(-pi,pi);
	
	StarNodeScript(Node& node) {
		node.transparent = true;
		node.customColor = true;
	}

	void render(Node& node) {
		double dist = node.sortDistance / (250.0 * node.abs_scale * pixelSizeRatio);
		
		if(dist < 1.0) {
			drawBuffers();
			node.applyTransform();
			
			material::StarSurface.switchTo();
			model::Sphere_max.draw(node.sortDistance / (node.abs_scale * pixelSizeRatio));
			
			/*vec4f pos;
			for(uint i = 0; i < 8; ++i) {
				float angle = float(int(i) - 6) * -0.24f * pi;
				pos.x = cos(angle);
				pos.y = sin(angle);
				pos.w = angle + (pi * 0.5);
				
				shader::BEZIER_POINTS[i] = pos;
			}
			
			applyAbsTransform(vec3d(0,1.0,0), vec3d(0.2), quaterniond());
			material::Prominence.switchTo();
			model::Prominence.draw();
			undoTransform();*/
			
			undoTransform();
			
			vec3d upLeft, upRight, center = node.abs_position;
			getBillboardVecs(center, upLeft, upRight, 0.0);
			
			upLeft *= node.abs_scale * 1.5;
			upRight *= node.abs_scale * 1.5;
			
			drawPolygonStart(PT_Quads, 1, material::Corona);
			drawPolygonPoint(center + upLeft, vec2f(0,0));
			drawPolygonPoint(center + upRight, vec2f(1,0));
			drawPolygonPoint(center - upLeft, vec2f(1,1));
			drawPolygonPoint(center - upRight, vec2f(0,1));
			drawPolygonEnd();
		}
		
		if(dist > 0.5) {
			Color col(node.color);
			col.a = dist > 1.0 ? 255 : int((dist - 0.5)*255.0/0.5);
			renderBillboard(material::DistantStar, node.abs_position, node.abs_scale * 32.0, 0.0, col);
		}
	}
};
