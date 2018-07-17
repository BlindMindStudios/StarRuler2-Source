#section disable menu
#section client
import elements.BaseGuiElement;
import elements.MarkupTooltip;
import elements.GuiIconGrid;
import planet_types;
import ship_groups;

export GuiGroupDisplay;

const Color GHOST_COLOR(0x000000ff);
const Color ORDERED_COLOR(0xaaaaaaff);

class GuiGroupDisplay : GuiIconGrid {
	GroupData[] groups;
	Object@ obj;
	Object@ leader;
	Color color;

	GuiGroupDisplay(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		iconSize = vec2i(26, 18);

		MarkupTooltip tt(250, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	void update(Object@ forObject) {
		//Figure out which objects to use
		@obj = forObject;
		if(obj.hasLeaderAI) {
			@leader = obj;
		}
		else {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null)
				@leader = ship.Leader;
		}

		if(leader is null) {
			groups.length = 0;
			hovered = -1;
			return;
		}

		//Sync the data
		groups.syncFrom(leader.getSupportGroups());

		//Update static data
		Empire@ owner = leader.owner;
		if(owner !is null)
			color = owner.color;
		else
			color = Color(0xffffffff);
		
		//Remove anything the player shouldn't be able to see
		//TODO: Handle this from the server instead
		if(owner !is playerEmpire) {
			for(int i = int(groups.length) - 1; i >= 0; --i) {
				GroupData@ group = groups[i];
				if(group.amount == 0) {
					groups.removeAt(i);
				}
				else {
					group.ghost = 0;
					group.ordered = 0;
					group.waiting = 0;
				}
			}
		}

		//Make sure our hovered isn't invalid
		hovered = clamp(hovered, -1, groups.length+1);
	}

	uint get_length() override {
		return groups.length + 1;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered > int(groups.length))
			return "";

		if(hovered == 0) {
			if(leader !is null)
				return format(locale::TT_SHIP_LEADER, leader.name);
			return "";
		}
		else {
			GroupData@ dat = groups[hovered-1];
			return format(locale::TT_SHIP_GROUP,
				dat.dsg.name, toString(dat.dsg.size, 0),
				toString(dat.amount), toString(dat.ghost), toString(dat.ordered));
		}
	}

	void drawLeader(const recti& pos) {
		if(obj is leader)
			spritesheet::ShipIconMods.draw(0, pos.padded(2, -2, 2, -2));

		Ship@ ship = cast<Ship>(leader);
		if(ship !is null) {
			const Design@ dsg = ship.blueprint.design;
			dsg.icon.draw(pos.padded(4, 0, 4, 0), dsg.color);
		}

		Planet@ pl = cast<Planet>(leader);
		if(pl !is null) {
			const PlanetType@ type = getPlanetType(pl.PlanetType);
			type.icon.draw(pos.padded(4, 0, 4, 0));
		}

		spritesheet::ShipIconMods.draw(1, pos.padded(6, -2, 0, -2));
	}

	void drawGroup(GroupData@ dat, const recti& pos) {
		const Font@ ft = skin.getFont(FT_Small);
		Color col = color;
		Color tcol(0xffffffff);
		string num;

		uint total = dat.totalSize;
		if(total > 0) {
			if(dat.ghost > dat.ordered) {
				col = col.interpolate(GHOST_COLOR, float(dat.ghost) / float(total));
				tcol = tcol.interpolate(Color(0xff0000ff), float(dat.ghost) / float(total));
			}
			else if(dat.ordered > 0) {
				col = col.interpolate(ORDERED_COLOR, float(dat.ordered) / float(total));
			}
		}

		if(dat.amount > 0)
			num = toString(dat.amount);
		else if(dat.ordered > 0)
			num = toString(dat.ordered);
		else if(dat.ghost > 0)
			num = toString(dat.ghost);

		Ship@ cur = cast<Ship>(obj);
		if(cur !is null && cur.blueprint.design is dat.dsg)
			spritesheet::ShipIconMods.draw(0, pos.padded(-2, -2, 6, -2));

		dat.dsg.icon.draw(pos.padded(0, 0, 8, 0), dat.dsg.color);
		ft.draw(pos=pos.padded(-1), text=num, ellipsis=locale::SHORT_ELLIPSIS,
				color=tcol, horizAlign=0.9, vertAlign=1.0, stroke=colors::Black);
	}

	void drawElement(uint index, const recti& pos) override {
		if(index == 0)
			drawLeader(pos);
		else
			drawGroup(groups[index-1], pos);
	}
};
