import resources;
import orbitals;
import buildings;

void dumpImages() {
	//Dump materials
	uint cnt = getMaterialCount();
	for(uint i = 0; i < cnt; ++i) {
		auto@ mat = getMaterial(i);
		if(mat.texture0 is null || mat.texture1 !is null)
			continue;

		string fname = "images/"+getMaterialName(i)+".png";
		print("dumping "+fname);

		Image img(Sprite(mat));
		img.save(fname);
	}

	//Dump sprites
	cnt = getSpriteSheetCount();
	for(uint i = 0; i < cnt; ++i) {
		const SpriteSheet@ sheet = getSpriteSheet(i);
		if(sheet.material.texture0 is null || sheet.material.texture1 !is null)
			continue;

		Image img(Sprite(sheet.material));
		uint spriteCount = sheet.count;
		string name = getSpriteSheetName(i);

		for(uint j = 0; j < spriteCount; ++j) {
			recti source = sheet.getSource(j);

			string fname = "images/"+name+"::"+j+".png";
			print("dumping "+fname);

			Image sprite(img, source);
			sprite.save(fname);
		}
	}
}

string makeReference(const Sprite& image, const string& name, const string& tooltip, int width = -1) {
	string res;
	res += "<span onmouseover=\"children[0].style.display = 'block'; children[0].style.top = offsetTop; children[0].style.left = offsetLeft; return true;\" onmouseout=\"children[0].style.display = 'none';\" style=\"display: inline-block; background: #eeeeee;\">\n";
	res += "<span style=\"display: none; position: absolute; margin-top: 25px; width: 250px; background: #343434; color: white; border: 1px solid #666666; padding: 4px; font-style: normal;\">\n";
	res += tooltip.replaced("\n", "[br/]");
	res += "</span>\n";
	if(!image.valid)
		res += format("$1</span>", name);
	else if(width > 0)
		res += format("<img src=\"images/$1.png\" width=\"$3\"/> $2</span>",
			getSpriteDesc(image), name, toString(width));
	else
		res += format("<img src=\"images/$1.png\"/> $2</span>",
			getSpriteDesc(image), name);
	return res;
}

string makeListing(const Sprite& image, const string& name, const string& desc, int width = -1) {
	string res;
	if(image.valid) {
		if(width > 0)
			res += format("[img=$1;$2]",
				getSpriteDesc(image), toString(width));
		else
			res += format("[img=$1]",
				getSpriteDesc(image));
	}

	if(name.length > 0)
		res += format("[font=Subtitle][b]$1[/b][/font][br/]", name);
	if(desc.length > 0)
		res += desc.replaced("\n", "[br/]");
	if(image.valid)
		res += "[/img]";
	return res;
}

void dumpTemplates() {
	//Resource templates
	uint cnt = getResourceCount();
	for(uint i = 0; i < cnt; ++i) {
		const ResourceType@ type = getResource(i);

		{
			string fname = format("templates/resource_ref;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			file.writeLine(makeReference(type.smallIcon, type.name, getResourceTooltip(type)));
		}

		{
			string fname = format("templates/resource;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			string name = type.name;
			if(type.rarity > RR_Common)
				name = format("[color=$1]$2[/color]", toString(getResourceRarityColor(type.rarity)), name);
			name += format(" [img=$1;20/]", getSpriteDesc(type.smallIcon));
			file.writeLine(makeListing(type.icon, name, getResourceTooltip(type, null, null, false)));
		}
	}

	//Orbital templates
	cnt = getOrbitalModuleCount();
	for(uint i = 0; i < cnt; ++i) {
		const OrbitalModule@ type = getOrbitalModule(i);

		{
			string fname = format("templates/orbital_ref;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			file.writeLine(makeReference(Sprite(), type.name, type.getTooltip()));
		}

		{
			string fname = format("templates/orbital;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			string name = type.name;
			file.writeLine(makeListing(Sprite(), name, type.getTooltip()));
		}
	}

	//Building templates
	cnt = getBuildingTypeCount();
	for(uint i = 0; i < cnt; ++i) {
		const BuildingType@ type = getBuildingType(i);

		{
			string fname = format("templates/building_ref;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			file.writeLine(makeReference(type.sprite, type.name, type.getTooltip(), 22));
		}

		{
			string fname = format("templates/building;$1", type.ident);
			print("dumping "+fname);

			WriteFile file(fname);
			string name = type.name;
			file.writeLine(makeListing(type.sprite, name, type.getTooltip(false)));
		}
	}
}
