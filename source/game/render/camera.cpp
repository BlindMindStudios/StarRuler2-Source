#include "render/camera.h"
#include "constants.h"
#include <stdio.h>

namespace render {

const double pctPerSecond = 0.9999;

Camera::Camera()
	: radius(300), qd_yaw(0), qd_pitch(0), qd_roll(0), qd_zoom(1), qd_zoom_min_distance(0), positionBound(vec3d(-1e7), vec3d(1e7)), maxDist(1e7),
	qd_abs_yaw(0), qd_abs_pitch(0), zNear(1), zFar(1000), fov(0.8), aspect(1), objectCamera(false), linearZoom(false), lockedRotation(true)
{
}

void Camera::yaw(double radians, bool snap) {
	if(snap)
		rotation = rotation * quaterniond::fromAxisAngle(vec3d::up(), radians);
	else
		qd_yaw += radians;
}

void Camera::pitch(double radians, bool snap) {
	if(snap) {
		rotation = rotation * quaterniond::fromAxisAngle(vec3d::right(), radians);
		rotation.normalize();
	}
	else {
		qd_pitch += radians;
	}
}

void Camera::abs_yaw(double radians, bool snap) {
	if(snap) {
		rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::up(), radians);
		rotation.normalize();
	}
	else {
		qd_abs_yaw += radians;
	}
}

void Camera::abs_yaw_to(double radians, bool snap) {
	if(snap) {
		double amount = getYaw() - radians;
		rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::up(), amount);
	}
	else
		qd_abs_yaw = getYaw() - radians;
}

void Camera::abs_pitch(double radians, bool snap) {
	if(snap) {
		rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::right(), radians);
		rotation.normalize();
	}
	else {
		qd_abs_pitch += radians;
	}
}

void Camera::abs_pitch_to(double radians, bool snap) {
	if(snap) {
		double amount = getPitch() - radians;
		rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::right(), amount);
	}
	else {
		qd_abs_pitch = getPitch() - radians;
	}
}

void Camera::roll(double radians, bool snap) {
	if(snap)
		rotation = rotation * quaterniond::fromAxisAngle(vec3d::front(), radians);
	else
		qd_roll += radians;
}

void Camera::zoom(double factor) {
	qd_zoom *= factor;
	qd_zoom_point = vec3d();
	qd_zoom_min_distance = 0;
}

void Camera::zoomTo(double factor, const vec3d& towards, double minDistance) {
	qd_zoom *= factor;
	qd_zoom_point = towards;
	qd_zoom_line = vec3d();
	qd_zoom_min_distance = minDistance;
}

void Camera::zoomAlong(double factor, const vec3d& line) {
	qd_zoom *= factor;
	qd_zoom_line = line;
	qd_zoom_point = vec3d();
	qd_zoom_min_distance = 0;
}

void Camera::setRadius(double amount) {
	radius = amount;
	if(radius > maxDist)
		radius = maxDist;
	if(radius < 0)
		radius = 1.0;
}

double Camera::getRadius() {
	return radius;
}

void Camera::move_world(const vec3d& motion) {
	qd_world_motion += motion * radius;
}

void Camera::move_world_abs(const vec3d& motion) {
	qd_world_motion += motion;
}

void Camera::move_cam(const vec3d& motion) {
	qd_cam_motion += motion * radius;
}

void Camera::move_cam_abs(const vec3d& motion) {
	qd_cam_motion += motion;
}

void Camera::move_abs(const vec3d& motion) {
	qd_abs_motion += motion;
}

void Camera::setPositionBound(const vec3d& minimum, const vec3d& maximum) {
	positionBound = AABBoxd(minimum, maximum);
}

void Camera::setMaxDistance(double dist) {
	maxDist = dist;
}

void Camera::setRenderConstraints(double ZNear, double ZFar, double FOV, double Aspect, double w, double h) {
	zNear = ZNear;
	zFar = ZFar;
	fov = FOV * (twopi / 360.0);
	aspect = Aspect;
	pxWidth = w;
	pxHeight = h;
}

bool Camera::inverted() {
	return getUp().y <= 0;
}

vec3d Camera::getPosition() const {
	if(objectCamera)
		return center;
	else
		return center + (rotation * vec3d::front(-radius));
}

vec3d Camera::getMovedPosition(vec3d pos, double pct) const {
	//Camera motion
	if(qd_cam_motion.getLength() > 0.00001) {
		vec3d cam_x = rotation * vec3d::right(); cam_x.normalize();
		vec3d cam_y = rotation * vec3d::up();    cam_y.normalize();
		vec3d cam_z = rotation * vec3d::front(); cam_z.normalize();

		pos += (cam_x * qd_cam_motion.x * pct) + (cam_y * qd_cam_motion.y * pct) + (cam_z * qd_cam_motion.z * pct);
	}

	//World motion
	if(qd_world_motion.getLength() > 0.00001) {
		vec3d world_x = rotation * vec3d::right(); world_x.y = 0; world_x.normalize();
		vec3d world_y = rotation * vec3d::up();    world_y.x = 0; world_y.z = 0; world_y.normalize();
		vec3d world_z = rotation * vec3d::front(); world_z.y = 0; world_z.normalize();

		pos += (world_x * qd_world_motion.x * pct) + (world_y * qd_world_motion.y * pct) + (world_z * qd_world_motion.z * pct);
	}

	//Absolute motion
	if(qd_abs_motion.getLength() > 0.00001)
		pos += qd_abs_motion * pct;

	pos = pos.elementMax(positionBound.minimum).elementMin(positionBound.maximum);

	return pos;
}

vec3d Camera::getFinalPosition() const {
	return getMovedPosition(getPosition(), 1.0);
}

vec3d Camera::getFacing() const {
	return rotation * vec3d::front();
}

vec3d Camera::getRight() const {
	return rotation * vec3d::right();
}

vec3d Camera::getUp() const {
	return (rotation * vec3d::up()).normalized();
}

quaterniond Camera::getRotation() const {
	return rotation;
}

vec3d Camera::getLookAt() const {
	return center;
}

vec3d Camera::getFinalLookAt() const {
	return getMovedPosition(getLookAt(), 1.0);
}

double Camera::getDistance() const {
	return radius;
}

double Camera::getYaw() const {
	vec3d rotated = rotation * vec3d::front();
	return atan2(rotated.z, rotated.x);
}

double Camera::getPitch() const {
	return 0.0;
}

double Camera::getRoll() const {
	return 0.0;
}

vec2i Camera::screenPos(const vec3d& point) const {
	//Transform to camera space
	vec3d transformed = rotation.inverted() * (point - getPosition());

	//Transform to OpenGL's space
	vec3d converted = vec3d(vec3d::right().dot(transformed), vec3d::up().dot(transformed), -vec3d::front().dot(transformed));

	Matrix projection = Matrix::projection(fov / (twopi / 360.0), aspect, zNear, zFar);

	//Apply projection and return final result (Left-Right and Top-Bottom are x[-1,1] and y[-1,1])
	vec4d pos = projection * vec4d(converted.x, converted.y, converted.z, 1.0);
	pos.x /= -pos.w; pos.y /= -pos.w;

	return vec2i((int)(pxWidth * (pos.x + 1.0) * 0.5), (int)(pxHeight * (pos.y + 1.0) * 0.5));
}

double Camera::screenAngle(const vec3d& toPoint) const {
	quaterniond inv = rotation.inverted();
	vec3d cam = inv * center;
	vec3d pos = inv * toPoint;

	vec2d flatOffset(cam.x - pos.x, pos.y - cam.y);
	return flatOffset.radians() / pi;
}

line3dd Camera::screenToRay(double x, double y) const {
	double tan_fov = tan(fov/2.0);

	vec3d view_dir = 
		  vec3d::front(1.0)
		+ vec3d::right(tan_fov * 2.0 * (0.5-x) * aspect)
		+ vec3d::up(tan_fov * 2.0 * (0.5-y));

	view_dir = rotation * view_dir.normalized();

	vec3d start = view_dir * zNear, end = view_dir * zFar;

	vec3d camPos = getPosition();
	start += camPos; end += camPos;

	return line3dd(start, end);
}

void Camera::setLockedRotation(bool locked) {
	lockedRotation = locked;
}

void Camera::animatePercentage(double pct) {
	{ //Rotation
		auto prevRot = rotation;
		auto rotLock = [&prevRot,this]() {
			if(lockedRotation && (rotation * vec3d::up()).y < 0.001)
				rotation = prevRot;
			else
				prevRot = rotation;
		};

		if(fabs(qd_abs_pitch) > 0.00001)
			rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::right(), pct * qd_abs_pitch);
		qd_abs_pitch *= 1.0 - pct;
		
		rotLock();

		if(fabs(qd_pitch) > 0.00001)
			rotation = rotation * quaterniond::fromAxisAngle(vec3d::right(), pct * qd_pitch);
		qd_pitch *= 1.0 - pct;
		
		rotLock();

		if(fabs(qd_roll) > 0.00001)
			rotation = rotation * quaterniond::fromAxisAngle(vec3d::front(), pct * qd_roll);
		qd_roll *= 1.0 - pct;

		rotLock();

		//Quaternion rotations
		if(fabs(qd_yaw) > 0.00001)
			rotation = rotation * quaterniond::fromAxisAngle(vec3d::up(), pct * qd_yaw);
		qd_yaw *= 1.0 - pct;

		//Absolute rotations around world axes
		if(fabs(qd_abs_yaw) > 0.00001)
			rotation = rotation * quaterniond::fromAxisAngle(rotation.inverted() * vec3d::up(), pct * qd_abs_yaw);
		qd_abs_yaw *= 1.0 - pct;

		rotation.normalize();
	}
	
	center = getMovedPosition(center, pct);

	//Move the center of the camera
	qd_cam_motion *= 1.0 - pct;
	qd_world_motion *= 1.0 - pct;
	qd_abs_motion *= 1.0 - pct;

	//Zoom level
	if(fabs(qd_zoom-1) > 0.00001) {
		if(linearZoom) {
			double dest = (qd_zoom * radius);
			double zoomDist = dest - radius;
			radius += pct * zoomDist;
			qd_zoom = dest / radius;
		}
		else {
			double doZoom = pow(qd_zoom, pct);
			qd_zoom /= doZoom;
			radius *= doZoom;

			if(!qd_zoom_line.zero()) {
				//Screw you and your entire 3D vector family
			}
			else if(!qd_zoom_point.zero()) {
				center = qd_zoom_point.interpolate(center, doZoom);
			}
		}
		
		if(radius > maxDist)
			radius = maxDist;
		if(radius < qd_zoom_min_distance)
			radius = qd_zoom_min_distance;
	}
	else {
		qd_zoom = 1;
	}
}

void Camera::animate(double seconds) {
	//Interpolate the camera's current state to its destination state
	if(seconds <= 0)
		return;

	double pct = 1.0 - pow(1.0 - pctPerSecond,seconds);
	animatePercentage(pct);
}

void Camera::snap() {
	animatePercentage(1.0);
}

void Camera::snapTranslation() {
	center = getMovedPosition(center, 1.0);

	//Move the center of the camera
	qd_cam_motion *= 0.0;
	qd_world_motion *= 0.0;
	qd_abs_motion *= 0.0;
}

void Camera::toLookAt(vec3d& cameraPosition, vec3d& cameraLookAt, vec3d& cameraUp) const {
	cameraPosition = getPosition();
	cameraLookAt = cameraPosition + getFacing();
	cameraUp = getUp();
}

void Camera::setObjectCamera(bool ObjectCamera) {
	objectCamera = ObjectCamera;
}

void Camera::setLinearZoom(bool linear) {
	linearZoom = linear;
}

void Camera::resetRotation() {
	//TODO: Make this calculate the required yaw/pitch/roll to
	//reset back to defaults, so that this can be animated instead
	//of always needing to snap.
	rotation = quaterniond();
	qd_yaw = 0;
	qd_pitch = 0;
	qd_roll = 0;
	qd_zoom = 1;
}

void Camera::resetZoom() {
	qd_zoom = 1;
	radius = 300;
}

};
