//Radius added to every entry
const double ExtraRadius = 100.0;
const double BorderThickness = 150.0;

bool SHOW_TERRITORY_BORDERS = true;
void setTerritoryBordersShown(bool enabled) {
	SHOW_TERRITORY_BORDERS = enabled;
}

bool getTerritoryBordersShown() {
	return SHOW_TERRITORY_BORDERS;
}

bool angleFacing(double a, double b) {
	double diff = angleDiff(a,b);
	return diff > -pi * 0.5 && diff < pi * 0.5;
}

final class Sphere {
	vec3d pos;
	double radius;
	double angle;
	double dist;
	int id;
	int count = 1;
	bool edge;
	
	Sphere(int ID, const vec3d& Pos, double Radius, bool Edge) {
		id = ID;
		radius = Radius;
		pos = Pos;
		edge = Edge;
	}
	
	void updateAngle(const vec3d& center) {
		angle = vec2d(pos.x - center.x, pos.z - center.z).radians();
		dist = center.distanceTo(pos);
	}
	
	int opCmp(const Sphere@ other) const {
		double diff = angle - other.angle;
		if(diff > 0)
			return 1;
		else if(diff < 0)
			return -1;
		else
			return 0;
	}
	
	bool include(Sphere@ left, Sphere@ right) {
		if(dist < left.dist && abs(angleDiff(left.angle, angle)) < pi * (5.0/180.0))
			return false;
		if(dist < right.dist && abs(angleDiff(right.angle, angle)) < pi * (5.0/180.0))
			return false;
	
		double leftTangent = vec2d(left.pos.x - pos.x, left.pos.z - pos.z).radians() - (pi * 0.5);
		if(!angleFacing(leftTangent, angle))
			leftTangent += pi;
		
		double rightTangent = vec2d(right.pos.x - pos.x, right.pos.z - pos.z).radians() - (pi * 0.5);
		if(!angleFacing(rightTangent, angle))
			rightTangent += pi;
		
		double diff = angleDiff(rightTangent,leftTangent);
		
		return diff > -pi * 0.31;
	}
	
	bool generateVerts(Sphere@ left, Sphere@ right, array<vec3d>@ verts) {	
		//Get angle to tangent collision, choosing the tangent facing away from the center
		double leftTangent = vec2d(left.pos.x - pos.x, left.pos.z - pos.z).radians() - (pi * 0.5);
		if(!angleFacing(leftTangent, angle))
			leftTangent += pi;
		
		double rightTangent = vec2d(right.pos.x - pos.x, right.pos.z - pos.z).radians() - (pi * 0.5);
		if(!angleFacing(rightTangent, angle))
			rightTangent += pi;
		
		double diff = angleDiff(rightTangent,leftTangent);
		
		//Curve around the edge of this sphere
		if(diff > 0) {
			int points = max(3, int(diff / 0.1309)); //7.5 degrees per point
			
			for(int i = 0; i < points; ++i) {
				double a = leftTangent + (diff * double(i) / double(points));
				vec3d dir(cos(a), 0, sin(a));
				verts.insertLast(pos + dir * radius);
				verts.insertLast(pos + dir * (radius - BorderThickness));
			}
		}
		else if(diff > -pi * 0.31) {
			//Bezier interpolation between tangent lines
			vec3d leftDir(cos(leftTangent), 0, sin(leftTangent));
			line3dd leftLine = line3dd(left.pos + leftDir * left.radius, pos + leftDir * radius);
			
			vec3d rightDir(cos(rightTangent), 0, sin(rightTangent));
			line3dd rightLine = line3dd(right.pos + rightDir * right.radius, pos + rightDir * radius);
			
			for(int i = 0; i < 15; ++i) {
				double p = 0.1 + (0.8 * double(i)/14.0);
				
				verts.insertLast(leftLine.midpoint.interpolate(leftLine.end, p).interpolate( rightLine.end.interpolate(rightLine.midpoint, p), p));
				verts.insertLast(verts[verts.length-1] + leftDir.interpolate(rightDir, p).normalized(-BorderThickness));
			}
		}
		else {
			return false;
		}
		
		return true;
	}
};

class TerritoryNodeScript {
	vec3d inner_center, edge_center;
	array<vec3d> inner_verts, edge_verts;
	array<Sphere@> spheres;
	int innerCount = 0;
	bool delta = false;
	Empire@ owner = defaultEmpire;

	TerritoryNodeScript(Node& node) {
		node.scale = 1000000000.0;
		node.rebuildTransform();
	}

	void setOwner(Empire@ emp) {
		@owner = emp;
	}

	void addInner(Node& node, int sysId, vec3d position, double radius) {
		for(uint i = 0, cnt = spheres.length; i < cnt; ++i) {
			if(spheres[i].id == sysId) {
				if(spheres[i].edge) {
					++innerCount;
					node.visible = true;
				}
				spheres[i].count++;
				spheres[i].edge = false;
				delta = true;
				return;
			}
		}
		spheres.insertLast(Sphere(sysId, position, radius + ExtraRadius, false));
		delta = true;

		++innerCount;
		node.visible = true;
	}

	void addEdge(int sysId, vec3d position, double radius) {
		for(uint i = 0, cnt = spheres.length; i < cnt; ++i) {
			if(spheres[i].id == sysId) {
				spheres[i].count++;
				return;
			}
		}
		spheres.insertLast(Sphere(sysId, position, radius + ExtraRadius, true));
		delta = true;
	}

	void removeInner(Node& node, int sysId) {
		for(uint i = 0, cnt = spheres.length; i < cnt; ++i) {
			if(spheres[i].id == sysId) {
				if(--spheres[i].count == 0) {
					spheres.removeAt(i);
					delta = true;
				}
				else {
					spheres[i].edge = true;
					delta = true;
				}
				break;
			}
		}

		--innerCount;
		node.visible = innerCount != 0;
	}

	void removeEdge(int sysId) {
		for(uint i = 0, cnt = spheres.length; i < cnt; ++i) {
			if(spheres[i].id == sysId) {
				if(--spheres[i].count == 0) {
					spheres.removeAt(i);
					delta = true;
				}
				break;
			}
		}
	}
	
	void rebuildPortion(array<Sphere@>& regions, array<vec3d>& verts, vec3d& center) {
		center.set(0,0,0);
		if(regions.length == 0) {
			verts.length = 0;
			return;
		}

		double rad = 0;
		for(uint i = 0; i < regions.length; ++i) {
			center += regions[i].pos;
			rad = max(rad, regions[i].radius);
		}
		center /= double(regions.length);
		
		//Update the angles for each sphere and sort
		for(uint i = 0; i < regions.length; ++i) {
			regions[i].updateAngle(center);
			regions[i].radius = rad;
		}
		
		regions.sortAsc();
		array<Sphere@>@ final = array<Sphere@>(), temp = @regions;
		
		if(temp.length > 1) {
			bool changed = false;
			while(true) {
				Sphere@ prev = temp[temp.length-1];
				for(int i = 0, cnt = temp.length; i < cnt; ++i) {
					Sphere@ sphere = temp[i];
					Sphere@ right = temp[(i+1) % cnt];
					if(sphere.include(prev, right)) {
						final.insertLast(sphere);
						@prev = sphere;
					}
					else {
						changed = true;
					}
				}
				
				if(final.length < 3)
					break;
				
				if(changed) {
					changed = false;
					@temp = @final;
					@final = array<Sphere@>();
				}
				else {
					break;
				}
			}
		}
		else {
			final.insertLast(temp[0]);
		}
		
		verts.length = 0;		
		if(final.length == 1) {
			Sphere@ sphere = final[0];
			for(int i = 0; i < 48; ++i) {
				double a = double(i) * twopi / 48.0;
				vec3d dir(cos(a), 0, sin(a));
				verts.insertLast(sphere.pos + dir * sphere.radius);
				verts.insertLast(sphere.pos + dir * (sphere.radius - BorderThickness));
			}
		}
		else if(final.length == 2) {
			for(int s = 0; s < 2; ++s) {
				Sphere@ sphere = final[s];
				for(int i = 0; i < 24; ++i) {
					double a = double(i) * pi / 24.0 + (sphere.angle - pi * 0.5);
					vec3d dir(cos(a), 0, sin(a));
					verts.insertLast(sphere.pos + dir * sphere.radius);
					verts.insertLast(sphere.pos + dir * (sphere.radius - BorderThickness));
				}
			}
		}
		else {
			Sphere@ prev = final[final.length-1];
			for(int i = 0, cnt = final.length; i < cnt; ++i) {
				Sphere@ right = final[(i+1) % cnt];
				if(final[i].generateVerts(prev, right, verts))
					@prev = final[i];
			}
		}
	}
	
	void rebuild() {
		delta = false;
		
		array<Sphere@> inner;
		
		//Copy over all inner spheres
		for(int i = 0, cnt = spheres.length; i < cnt; ++i)
			if(!spheres[i].edge)
				inner.insertLast(spheres[i]);
		
		rebuildPortion(spheres, edge_verts, edge_center);
		rebuildPortion(inner, inner_verts, inner_center);
	}
	
	bool preRender(Node& node) {
		if(delta)
			rebuild();
		return inner_verts.length != 0 && owner !is null;
	}

	void render(Node& node) {
		if(SHOW_TERRITORY_BORDERS) {
			vec2f innerUV(0,0), outerUV(1,0);
			vec2f innerUV_r(0,1), outerUV_r(1,1);
			if(owner is playerEmpire) {
				drawPolygonStart(edge_verts.length, material::Territory, Color(0xffffff80));
					for(int i = 0, cnt = edge_verts.length; i < cnt; i += 2) {
						drawPolygonPoint(edge_verts[i], outerUV);
						drawPolygonPoint(edge_verts[(i+2)%cnt], outerUV);
						drawPolygonPoint(edge_verts[(i+1)%cnt], innerUV);
						
						drawPolygonPoint(edge_verts[(i+2)%cnt], outerUV);
						drawPolygonPoint(edge_verts[(i+3)%cnt], innerUV);
						drawPolygonPoint(edge_verts[(i+1)%cnt], innerUV);
					}
				drawPolygonEnd();
			}

			double offset = 0;
			bool stipple = false;
			Empire@ master = owner.SubjugatedBy;
			if(master !is null) {
				stipple = true;
				master.color.toVec4(shader::STIPPLE_COLOR);
			}
			else {
				shader::STIPPLE_COLOR = vec4f(0.f, 0.f, 0.f, 0.f);
			}

			drawPolygonStart(inner_verts.length, material::Territory, owner.color);
				for(int i = 0, cnt = inner_verts.length; i < cnt; i += 2) {
					if(stipple) {
						outerUV.y = offset;
						innerUV.y = offset;
						offset += inner_verts[i].distanceTo(inner_verts[(i+2)%cnt]);
						outerUV_r.y = offset;
						innerUV_r.y = offset;
					}

					drawPolygonPoint(inner_verts[i], outerUV);
					drawPolygonPoint(inner_verts[(i+2)%cnt], outerUV_r);
					drawPolygonPoint(inner_verts[(i+1)%cnt], innerUV);
					
					drawPolygonPoint(inner_verts[(i+2)%cnt], outerUV_r);
					drawPolygonPoint(inner_verts[(i+3)%cnt], innerUV_r);
					drawPolygonPoint(inner_verts[(i+1)%cnt], innerUV);
				}
			drawPolygonEnd();
		}
	}
};
