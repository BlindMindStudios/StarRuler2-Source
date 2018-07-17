namespace icons {
	const Sprite Loyalty(spritesheet::AttributeIcons, 1);
	const Sprite Population(spritesheet::ResourceIcon, 8);
	const Sprite Pressure(spritesheet::AttributeIcons, 0);
	const Sprite Effectiveness(spritesheet::StatusIcons, 0);

	const Sprite Planet(spritesheet::PlanetType, 2);
	const Sprite Artifact(spritesheet::ArtifactIcon, 0);
	const Sprite Anomaly(spritesheet::AnomalyIcons, 0);
	const Sprite Asteroid(material::AsteroidIcon);
	const Sprite Building(material::Warehouse);
	const Sprite Orbital(spritesheet::GuiOrbitalIcons, 0, Color(0x9e33ddff));
	const Sprite Ship(spritesheet::ActionBarIcons, 2);
	const Sprite Project(spritesheet::ResourceIcon, 6);

	const Sprite Money(spritesheet::ResourceIcon, 0);
	const Sprite Influence(spritesheet::ResourceIcon, 1);
	const Sprite Energy(spritesheet::ResourceIcon, 2);
	const Sprite Labor(spritesheet::ResourceIcon, 6);
	const Sprite Defense(spritesheet::ResourceIcon, 5);
	const Sprite Research(spritesheet::ResourceIcon, 4);
	const Sprite FTL(spritesheet::ResourceIcon, 3);
	const Sprite Empty;

	const Sprite Health(spritesheet::AttributeIcons, 6);
	const Sprite Strength(spritesheet::AttributeIcons, 3);
	const Sprite Supply(spritesheet::AttributeIcons, 4);
	const Sprite Shield(spritesheet::ResourceIcon, 5, Color(0x429cffff));

	const Sprite FoodRequirement(spritesheet::ResourceClassIcons, 3);
	const Sprite WaterRequirement(spritesheet::ResourceClassIcons, 4);
	const Sprite FoodWaterRequirement(spritesheet::ResourceClassIcons, 7);

	const Sprite InfluenceWeight(material::SupportIcon);
	const Sprite InfluencePlayCost = Influence;
	const Sprite InfluencePurchaseCost(spritesheet::ConvertIcon, 0);
	const Sprite InfluenceUpkeep(material::SupplyIcon);
	const Sprite Duration(spritesheet::ContextIcons, 1);

	const Sprite Manage(spritesheet::ActionBarIcons, 0);
	const Sprite ManageSupports(spritesheet::ActionBarIcons, 2);
	const Sprite Colonize(spritesheet::ActionBarIcons, 1);
	const Sprite ProjectDefense(spritesheet::ActionBarIcons, 3);
	const Sprite ColonizeThis(spritesheet::ActionBarIcons, 4);
	const Sprite UnderSiege(spritesheet::QuickbarIcons, 7);
	
	const Sprite Hyperdrive(spritesheet::ActionBarIcons, 5);
	const Sprite Slipstream(spritesheet::ActionBarIcons, 6);
	const Sprite Gate(spritesheet::ActionBarIcons, 7);
	const Sprite Fling(spritesheet::ActionBarIcons, 8);
	
	const Sprite Explore(spritesheet::ActionBarIcons, 9);
	const Sprite HyperExplore(spritesheet::ActionBarIcons, 10);

	const Sprite Ability(spritesheet::ActionBarIcons, 7);

	const Sprite Customize(spritesheet::StatusIcons, 0);

	const Sprite NotReady(spritesheet::CardCategoryIcons, 0);
	const Sprite Ready(spritesheet::CardCategoryIcons, 4);

	const Sprite Obsolete(spritesheet::CardCategoryIcons, 0);
	const Sprite Unobsolete(spritesheet::CardCategoryIcons, 3);

	const Sprite Back(spritesheet::MenuIcons, 11);
	const Sprite Close(spritesheet::MenuIcons, 8);
	const Sprite Remove(spritesheet::MenuIcons, 8);
	const Sprite Delete(spritesheet::MenuIcons, 8);
	const Sprite Create(spritesheet::AttributeIcons, 2);
	const Sprite Add(spritesheet::AttributeIcons, 2);
	const Sprite Plus(spritesheet::AttributeIcons, 2);
	const Sprite Minus(material::Minus);
	const Sprite Exclaim(spritesheet::MenuIcons, 5);
	const Sprite Info(spritesheet::MenuIcons, 3);
	const Sprite Details(spritesheet::MenuIcons, 10);
	const Sprite Chat(spritesheet::MenuIcons, 6);
	const Sprite Go(spritesheet::MenuIcons, 9);
	const Sprite Refresh(spritesheet::MenuIcons, 12);
	const Sprite Repeat(spritesheet::MenuIcons, 12);
	const Sprite Reset(spritesheet::MenuIcons, 12, colors::Red);
	const Sprite Import(spritesheet::MenuIcons, 13);
	const Sprite Export(spritesheet::MenuIcons, 13);
	const Sprite Forward(spritesheet::MenuIcons, 10);
	const Sprite Load(spritesheet::MenuIcons, 1);
	const Sprite Save(spritesheet::MenuIcons, 2);
	const Sprite Edit(material::TabDesigns);
	const Sprite Action(spritesheet::CardCategoryIcons, 0);

	const Sprite Undo(spritesheet::EditIcons, 0);
	const Sprite Redo(spritesheet::EditIcons, 2);
	const Sprite UndoDisabled(spritesheet::EditIcons, 1);
	const Sprite RedoDisabled(spritesheet::EditIcons, 3);
	const Sprite Clear(spritesheet::EditIcons, 8);

	const Sprite Paint(spritesheet::EditIcons, 4);
	const Sprite Move(spritesheet::EditIcons, 5);
	const Sprite Eyedrop(spritesheet::EditIcons, 6);
	const Sprite Zoom(spritesheet::EditIcons, 6);
	const Sprite Search(spritesheet::EditIcons, 6);

	const Sprite Donate(spritesheet::ActionBarIcons, 4, colors::Green);
	const Sprite Upvote(material::ThumbsUp);
	const Sprite Next(spritesheet::MenuIcons, 9);
	const Sprite Previous(spritesheet::MenuIcons, 11);
};

namespace colors {
	const Color Money(0xd1cb6aff);
	const Color Influence(0x0087c7ff);
	const Color Energy(0x42b4bdff);
	const Color Defense(0xaf7926ff);
	const Color Labor(0xb1b4b6ff);
	const Color Research(0x8c4ec9ff);
	const Color FTL(0x00c0ffff);
	const Color FTLResource(0x9bd29cff);

	const Color Planet(0x8cc94eff);
	const Color Artifact(0xfe82ffff);
};
