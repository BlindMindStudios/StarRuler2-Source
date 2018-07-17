import constructible;

void drawConstructible(Constructible@ cons, const recti& pos, bool isBox = false) {
	//Draw design model
	if(cons.dsg !is null) {
		recti shipPos;
		if(cons.dsg.hull.backgroundScale != 1.0)
			shipPos = recti_centered(pos, vec2i(double(pos.width) * cons.dsg.hull.backgroundScale,
											double(pos.height) * cons.dsg.hull.backgroundScale));
		else
			shipPos = pos;

		shader::CUTOFF_PCT = cons.progress;
		const Model@ baseModel = cons.dsg.hull.model;
		const Material@ baseMaterial = cons.dsg.hull.material;
		quaterniond rot = quaterniond_fromAxisAngle(vec3d_front(), -0.8 * pi);

		Material frontMat(baseMaterial);
		@frontMat.shader = shader::CutOff;
		frontMat.depthTest = DT_Always;

		Material backMat(baseMaterial);
		@backMat.shader = shader::WireframeCutOff;
		backMat.drawMode = DM_Line;
		backMat.depthTest = DT_Always;

		if(isBox) {
			Color lCol = cons.dsg.color;
			lCol.a = 0x20;
			Color mCol = cons.dsg.color;
			mCol.a = 0x12;
			Color dCol = cons.dsg.color;
			dCol.a = 0x05;

			drawRectangle(pos, mCol, lCol, mCol, dCol);
			drawRectangle(pos.padded(0, 0, (1.f - cons.progress) * pos.width, 0), Color(0xffffff14));
		}

		baseModel.draw(backMat, shipPos.padded(2), rot);
		baseModel.draw(frontMat, shipPos.padded(2), rot);
	}
	else if(cons.orbital !is null) {
		shader::CUTOFF_PCT = cons.progress;
		const Model@ baseModel = cons.orbital.model;
		const Material@ baseMaterial = cons.orbital.material;
		quaterniond rot = quaterniond();

		Material frontMat(baseMaterial);
		@frontMat.shader = shader::CutOff;
		frontMat.depthTest = DT_Always;

		Material backMat(baseMaterial);
		@backMat.shader = shader::WireframeCutOff;
		backMat.drawMode = DM_Line;
		backMat.depthTest = DT_Always;

		if(isBox)
			drawRectangle(pos.padded(0, 0, (1.f - cons.progress) * pos.width, 0), Color(0xffffff14));

		baseModel.draw(backMat, pos.padded(2), rot);
		baseModel.draw(frontMat, pos.padded(2), rot);
	}
	else {
		if(isBox)
			drawRectangle(pos.padded(0, 0, (1.f - cons.progress) * pos.width, 0), Color(0xffffff14));
	}
}

void drawConstructible(Constructible@ cons, const recti& pos, const Font@ ft) {
	Color nameCol(0xffffffff);
	if(!cons.started)
		nameCol = Color(0xff0000ff);

	int sz = ft.getLineHeight() * 2 + 6;
	ft.draw(pos=pos.resized(0, sz, 0.0, 1.0),
		text=cons.name, color=nameCol, horizAlign=0.5, vertAlign=0.0,
		stroke=colors::Black);

	string prog = toString(cons.progress * 100.f, 0)+"%";
	if(cons.type == CT_DryDock)
		prog += " / "+toString(cons.pct * 100.f, 0)+"%";
	ft.draw(pos=pos.resized(0, sz - ft.getLineHeight(), 0.0, 1.0),
			text=prog, color=Color(0xffffffff), horizAlign=0.5, vertAlign=0.0,
			stroke=colors::Black);

	drawConstructible(cons, pos.resized(0, pos.size.height - sz + 6));
}
