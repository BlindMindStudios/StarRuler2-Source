#priority render 20
const double GROW_TIMER = 1.0;
const double SHOW_TIMER = 10.0;
const double SHOW_SCALE = 0.1;

class Ping {
	Empire@ fromEmpire;
	uint type = 0;
	double timer = 0.0;

	Ping(Node& node) {
	}

	void establish(Node& node, Empire@ emp, uint t) {
		@fromEmpire = emp;
		type = t;
		node.rebuildTransform();
	}

	bool preRender(Node& node) {
		timer += frameLength;
		if(timer >= SHOW_TIMER)
			node.visible = false;
		return true;
	}

	void render(Node& node) {
		if(fromEmpire is null)
			return;
		double scale = 1.0;

		double t = timer % GROW_TIMER;
		if(timer > GROW_TIMER)
			scale *= 0.25;
		if(t < GROW_TIMER*0.5)
			scale *= t/(GROW_TIMER*0.5);
		else
			scale *= (1.0 - (t-GROW_TIMER*0.5)/(GROW_TIMER*0.5)) * (1.0 - SHOW_SCALE) + SHOW_SCALE;
		scale *= node.sortDistance * 0.2;

		renderPlane(material::Ping, node.abs_position, scale, fromEmpire.color);
		if(type == 0)
			renderBillboard(spritesheet::AttributeIcons, 5, node.abs_position, node.sortDistance * 0.02, 0, fromEmpire.color);
		else if(type == 1)
			renderBillboard(material::Minus, node.abs_position, node.sortDistance * 0.02, 0);
	}
};

Mutex mtx;
array<PingNode@> pings;
array<Empire@> pingEmpires;

void showPing(Empire@ fromEmpire, vec3d position, uint type = 0) {
	//Make new ping
	PingNode@ p = PingNode();
	p.position = position;
	p.scale = 10000.0;
	p.establish(fromEmpire, type);

	{
		Sound@ snd;
		if(type == 0)
			@snd = sound::ping.play(position, pause=true, priority=true);
		else
			@snd = sound::ping_warn.play(position, pause=true, priority=true);
		if(snd !is null) {
			snd.rolloff = 0;
			snd.resume();
		}
	}

	Lock lock(mtx);
	pings.insertLast(p);
	pingEmpires.insertLast(fromEmpire);

	//Allow at most 5 pings at the same time per empire
	uint count = 0;
	for(int i = pings.length - 1; i >= 0; --i) {
		if(pingEmpires[i] !is fromEmpire)
			continue;

		++count;
		if(count > 5) {
			pings[i].markForDeletion();
			pings.removeAt(i);
			pingEmpires.removeAt(i);
		}
	}
}

void tick(double time) {
	Lock lock(mtx);
	for(int i = pings.length - 1; i >= 0; --i) {
		if(!pings[i].visible) {
			pings.removeAt(i);
			pingEmpires.removeAt(i);
		}
	}
}

