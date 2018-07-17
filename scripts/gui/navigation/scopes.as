#priority init 90
import systems;

enum ScopeType {
	ST_Invalid,
	ST_System,

	ST_COUNT
};

class Scope {
	int id;

	Scope() {
		id = -1;
	}

	ScopeType get_type() {
		return ST_Invalid;
	}

	vec3d get_position() {
		return vec3d();
	}

	string get_name() {
		return "---";
	}

	double get_radius() {
		return 0.0;
	}

	int get_priority() {
		return 0;
	}
};

class SystemScope : Scope {
	SystemDesc@ sys;

	SystemScope(SystemDesc@ system) {
		@sys = system;
		id = -1;
	}

	ScopeType get_type() {
		return ST_System;
	}

	vec3d get_position() {
		return sys.position;
	}

	double get_radius() {
		return sys.radius;
	}

	int get_priority() {
		return 0;
	}

	string get_name() {
		return sys.object.name;
	}
};

class ScopeSearch {
	int minPriority;
	int maxPriority;
	double priorityFactor;
	double minDistance;
	double maxDistance;
	bool[] allowedTypes;

	vec3d position;
	Scope@[] results;
	double[] factors;

	ScopeSearch() {
		minPriority = INT_MIN;
		maxPriority = INT_MAX;
		priorityFactor = 1.0;
		minDistance = -INFINITY;
		maxDistance = INFINITY;

		allowedTypes.length = ST_COUNT;
		for(int i = 0; i < ST_COUNT; ++i)
			allowedTypes[i] = true;
	}
};

namespace scopes {
	::map scopes;
	int nextScopeId = 1;
};

void init() {
	//Add systems as scopes
	for(uint i = 0, cnt = systemCount; i < cnt; ++i)
		addScope(SystemScope(getSystem(i)));
}

int addScope(Scope@ scope) {
	if(scope.id <= 0)
		scope.id = scopes::nextScopeId++;
	scopes::scopes.set(scope.id, @scope);
	return scope.id;
}

void removeScope(Scope@ scope) {
	removeScope(scope.id);
}

void removeScope(int id) {
	if(id > 0)
		scopes::scopes.delete(id);
}

uint searchScopes(ScopeSearch@ s, uint amount) {
	uint found = 0;
	s.results.length = amount;
	s.factors.length = amount;
	double maxFactor = 0.0;

	map_iterator it = scopes::scopes.iterator();
	Scope@ scope;
	while(it.iterate(@scope)) {
		int priority = scope.priority;
		if(priority < s.minPriority || priority > s.maxPriority)
			continue;

		double factor = s.position.distanceTo(scope.position);
		factor -= scope.radius;
		if(factor < s.minDistance || factor > s.maxDistance)
			continue;
		if(priority != 0)
			factor /= double(priority) * s.priorityFactor;

		if(found < amount) {
			if(found == 0) {
				@s.results[0] = scope;
				s.factors[0] = factor;
			}
			else {
				for(int i = found; i >= 0; --i) {
					if(i == 0 || factor > s.factors[i-1]) {
						@s.results[i] = scope;
						s.factors[i] = factor;
						break;
					}
					@s.results[i] = s.results[i-1];
					s.factors[i] = s.factors[i-1];
				}
			}
			maxFactor = s.factors[found];
			++found;
		}
		else if(factor < maxFactor) {
			for(int i = amount - 1; i >= 0; --i) {
				if(i == 0 || factor > s.factors[i-1]) {
					@s.results[i] = scope;
					s.factors[i] = factor;
					break;
				}
				@s.results[i] = s.results[i-1];
				s.factors[i] = s.factors[i-1];
			}
			maxFactor = s.factors[amount-1];
		}
	}

	if(found != amount) {
		s.results.length = found;
		s.factors.length = found;
	}
	return found;
}
