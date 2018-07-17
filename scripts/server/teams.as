#priority init 10
import influence;
import settings.game_settings;
from influence_global import createTreaty, joinTreaty;

void init() {
	if(isLoadedSave)
		return;
	uint empCnt = gameSettings.empires.length;
	uint handledTeams = 0;
	for(uint i = 0; i < empCnt; ++i) {
		Empire@ emp = getEmpire(i);
		EmpireSettings@ settings = gameSettings.empires[i];
		emp.team = settings.team;

		if(settings.team <= 0)
			continue;
		int team = settings.team;
		uint mask = 1<<(team-1);
		bool needTreaty = handledTeams & mask == 0;

		Treaty@ treaty;
		for(uint j = 0; j < empCnt; ++j) {
			if(j == i)
				continue;
			EmpireSettings@ otherSettings = gameSettings.empires[j];
			if(otherSettings.team != team)
				continue;
			Empire@ other = getEmpire(j);
			other.ContactMask |= emp.mask;
			emp.ContactMask |= other.mask;

			if(needTreaty) {
				if(treaty is null) {
					@treaty = Treaty();
					treaty.name = format(locale::TEAM_TEXT, toString(team));
					for(uint n = 0, ncnt = getInfluenceClauseTypeCount(); n < ncnt; ++n) {
						auto@ type = getInfluenceClauseType(n);
						if(type.teamClause)
							treaty.addClause(type);
					}

					@treaty = createTreaty(emp, treaty);
				}
				joinTreaty(other, treaty.id, force=true);
			}
		}

		handledTeams |= mask;
	}
}
