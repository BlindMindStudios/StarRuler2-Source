#pragma once

#include "quaternion.h"
#include "vec2.h"
#include "line3d.h"
#include "util/refcount.h"
#include "aabbox.h"

namespace render {

class Camera : public AtomicRefCounted {
private:
	quaterniond rotation;
	vec3d center;
	double radius;
	
	AABBoxd positionBound;
	double maxDist;

	vec3d qd_zoom_point;
	vec3d qd_zoom_line;

	vec3d qd_world_motion;
	vec3d qd_cam_motion;
	vec3d qd_abs_motion;
	double qd_yaw, qd_pitch, qd_roll, qd_zoom;
	double qd_abs_yaw, qd_abs_pitch;
	double qd_zoom_min_distance;

	double zNear, zFar, fov, aspect, pxWidth, pxHeight;

	bool objectCamera;
	bool linearZoom;
	bool lockedRotation;

public:
	void yaw(double radians, bool snap = false);
	void pitch(double radians, bool snap = false);
	void abs_yaw(double radians, bool snap = false);
	void abs_pitch(double radians, bool snap = false);
	void roll(double radians, bool snap = false);
	void zoom(double factor);
	void snap();
	void snapTranslation();

	void setRadius(double radius);
	double getRadius();

	void abs_yaw_to(double yaw, bool snap = false);
	void abs_pitch_to(double pitch, bool snap = false);

	void move_cam(const vec3d& motion);
	void move_cam_abs(const vec3d& motion);
	void move_world(const vec3d& motion);
	void move_world_abs(const vec3d& motion);
	void move_abs(const vec3d& motion);

	void zoomTo(double factor, const vec3d& towards, double minDistance = 0);
	void zoomAlong(double factor, const vec3d& line);

	void animatePercentage(double pct);
	void animate(double seconds);

	void setLinearZoom(bool linear);
	void setLockedRotation(bool locked);

	void setPositionBound(const vec3d& minimum, const vec3d& maximum);
	void setMaxDistance(double dist);

	//Returns the angle in physical screen space
	//that a particular point is directed in from the
	//center of the screen
	double screenAngle(const vec3d& toPoint) const;
	vec2i screenPos(const vec3d& point) const;

	//Returns a ray starting at the near Z plane, ending at the
	//far Z plane, with each endpoint being at <x,y> on the screen in
	//normalized coordinates [0,1]
	line3dd screenToRay(double x, double y) const;
	
	vec3d getMovedPosition(vec3d pos, double pct) const;
	vec3d getFinalPosition() const;
	vec3d getPosition() const;
	vec3d getFacing() const;
	vec3d getUp() const;
	vec3d getRight() const;
	quaterniond getRotation() const;

	vec3d getLookAt() const;
	vec3d getFinalLookAt() const;
	double getDistance() const;

	double getYaw() const;
	double getPitch() const;
	double getRoll() const;

	//Returns whether the camera is currently upside down
	bool inverted();

	void setObjectCamera(bool ObjectCamera);
	void toLookAt(vec3d& cameraPosition, vec3d& cameraLookAt, vec3d& cameraUp) const;
	void setRenderConstraints(double ZNear, double ZFar, double FOV_degrees, double Aspect, double w, double h);
	void resetRotation();
	void resetZoom();

	Camera();
};

};
