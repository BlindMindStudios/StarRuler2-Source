import influence;
import hooks;
from influence import InfluenceClauseHook;
import resources;

#section server
import influence_global;
#section all

//ShareVision(To Starter = True, To Other = True)
// Share empire vision between the empires.
/// If <To Starter> is true, the treaty starter gets vision.
/// If <To Other> is true, the treaty signatories get vision.
class ShareVision : InfluenceClauseHook {
	Document doc("Shares vision from either of the parties in a treaty to the other (or both).");
	Argument starter("To Starter", AT_Boolean, "True", doc="Whether the receiver shares vision with the starter.");
	Argument other("To Other", AT_Boolean, "True", doc="Whether the starter shares vision with the receiver.");

#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		uint mask = 0;
		if(treaty.leader !is null)
			mask = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			mask |= treaty.joinedEmpires[i].mask;

		if(starter.boolean && treaty.leader !is null)
			treaty.leader.visionMask |= mask;
		if(other.boolean) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				if(treaty.joinedEmpires[i] !is treaty.leader)
					treaty.joinedEmpires[i].visionMask |= mask;
			}
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const override {
		if(treaty.leader !is null)
			treaty.leader.visionMask = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			treaty.joinedEmpires[i].visionMask = treaty.joinedEmpires[i].mask;
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const override {
		left.visionMask = left.mask;
		onEnd(treaty, clause);
		onTick(treaty, clause, 0.0);
	}
#section all
};

//FreeTrade(To Starter = True, To Other = True)
// Share trade borders between empires.
/// If <To Starter> is true, the treaty starter gets free trade.
/// If <To Other> is true, the treaty signatories get free trade.
class FreeTrade : InfluenceClauseHook {
	Document doc("Shares trade from either of the parties in a treaty to the other (or both).");
	Argument starter("To Starter", AT_Boolean, "True", doc="Whether the receiver shares trade with the starter.");
	Argument other("To Other", AT_Boolean, "True", doc="Whether the starter shares trade with the receiver.");

#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		uint mask = 0;
		if(treaty.leader !is null)
			mask = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			mask |= treaty.joinedEmpires[i].mask;

		if(starter.boolean && treaty.leader !is null)
			treaty.leader.TradeMask |= mask;
		if(other.boolean) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				if(treaty.joinedEmpires[i] !is treaty.leader)
					treaty.joinedEmpires[i].TradeMask |= mask;
			}
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const override {
		if(treaty.leader !is null)
			treaty.leader.TradeMask.value = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			treaty.joinedEmpires[i].TradeMask.value = treaty.joinedEmpires[i].mask;
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const override {
		left.TradeMask.value = left.mask;
		onEnd(treaty, clause);
		onTick(treaty, clause, 0.0);
	}
#section all
};

//ForcePeace()
// Empires cannot declare war on each other while in this treaty.
class ForcePeace : InfluenceClauseHook {
	Document doc("Prevents and ends wars between any members of this treaty.");
	Argument break_on_war(AT_Boolean, "False", doc="Break the treaty if war does happen, for example due to mutual defense pacts.");
	
#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		uint mask = 0;
		if(treaty.leader !is null)
			mask = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			mask |= treaty.joinedEmpires[i].mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp.hostileMask & mask != 0 && break_on_war.boolean) {
				leaveTreaty(emp, treaty.id, force=true);
				--i; --cnt;
				continue;
			}

			emp.ForcedPeaceMask |= mask;
			emp.PeaceMask &= ~mask;
		}
	}

	void onJoin(Treaty@ treaty, Clause@ clause, Empire@ joined) const {
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			Empire@ other = treaty.joinedEmpires[i];
			if(other !is joined) {
				other.setHostile(joined, false);
				joined.setHostile(other, false);
			}
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const override {
		if(treaty.leader !is null)
			treaty.leader.ForcedPeaceMask.value = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i)
			treaty.joinedEmpires[i].ForcedPeaceMask.value = treaty.joinedEmpires[i].mask;
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const override {
		left.ForcedPeaceMask.value = left.mask;
		onEnd(treaty, clause);
		onTick(treaty, clause, 0.0);
	}
#section all
};

class MakePeace : InfluenceClauseHook {
	Document doc("Ends wars when this treaty is accepted.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const override {
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			Empire@ emp = treaty.joinedEmpires[i];
			for(uint j = 0; j < cnt; ++j) {
				Empire@ other = treaty.joinedEmpires[j];
				if(other !is emp) {
					other.setHostile(emp, false);
					emp.setHostile(other, false);
				}
			}
		}
	}
#section all
};

class RemoveOnCreate : InfluenceClauseHook {
	Document doc("This clause is temporary and is removed after applying its effects.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const override {
		if(treaty.leader !is null) {
			leaveTreaty(treaty.leader, treaty.id, force=true);
		}
		else {
			array<Empire@> emps = treaty.joinedEmpires;
			for(uint i = 0, cnt = emps.length; i < cnt; ++i)
				leaveTreaty(emps[i], treaty.id, force=true);
		}
	}
#section all
};

//CannotBreak()
// This treaty is permanent and cannot be broken.
class CannotBreak : InfluenceClauseHook {
	Document doc("Prevents this treaty from being broken.");
	
	bool canLeave(const Treaty@ treaty, const Clause@ clause, Empire& empire) const {
		return false;
	}
};

//CannotInvite()
// No further empires can be invited to this treaty.
class CannotInvite : InfluenceClauseHook {
	Document doc("Prevents inviting others to enter this treaty.");
	
	bool canInvite(const Treaty@ treaty, const Clause@ clause, Empire& from, Empire& invite) const {
		return false;
	}
};

//CannotAlter()
// No additional clauses can be played into this treaty.
class CannotAlter : InfluenceClauseHook {
	Document doc("Prevents any alterations to this treaty.");
};


class DictateWar : InfluenceClauseHook {
	Document doc("The owner of the treaty dictates the war status for everyone.");

#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		if(treaty.leader is null)
			return;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ member = treaty.joinedEmpires[i];
			if(member !is treaty.leader)
				member.hostileMask = treaty.leader.hostileMask;
			for(uint j = 0, jcnt = getEmpireCount(); j < jcnt; ++j) {
				Empire@ other = getEmpire(j);
				if(other is member || other is treaty.leader)
					continue;
				bool shouldWar = other.isHostile(treaty.leader);
				bool hasWar = other.isHostile(member);
				if(shouldWar != hasWar)
					other.setHostile(member, shouldWar);
			}
		}

		uint allMask = treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			allMask |= emp.mask;
		}
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			emp.mutualDefenseMask |= allMask;
		}
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const override {
		uint allMask = 0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			allMask |= emp.mask;
		}
		left.mutualDefenseMask &= ~allMask;
	}
#section all
};


class DictateTrade : InfluenceClauseHook {
	Document doc("The owner of the treaty dictates the trade capabilities for everyone.");

#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		if(treaty.leader is null)
			return;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ member = treaty.joinedEmpires[i];
			if(member !is treaty.leader)
				member.TradeMask.value = treaty.leader.TradeMask.value;
		}
	}
#section all
};


class DictateVision : InfluenceClauseHook {
	Document doc("The owner of the treaty dictates everyone's vision.");

#section server
	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		if(treaty.leader is null)
			return;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ member = treaty.joinedEmpires[i];
			if(member !is treaty.leader)
				member.visionMask = treaty.leader.visionMask;
		}
	}
#section all
};


class NotNormallyVisible : InfluenceClauseHook {
	Document doc("This treaty is not normally visible to people not in it.");

	bool isVisibleTo(const Treaty@ treaty, const Clause@ clause, Empire& empire) const {
		if(empire.mask & treaty.inviteMask != 0)
			return true;
		if(empire.mask & treaty.presentMask != 0)
			return true;
		return false;
	}
};


class SubjugateMembers : InfluenceClauseHook {
	Document doc("Members of this treaty count as subjugated.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const {
		//Find out which empire is the leader
		Empire@ subjEmp;
		if(treaty.leader is null) {
			@treaty.leader = treaty.joinedEmpires[1];
			@subjEmp = treaty.joinedEmpires[0];
		}
		else {
			@subjEmp = treaty.joinedEmpires[1];
		}
		treaty.name = format(locale::SURRENDER_NAME, formatEmpireName(subjEmp));

		//Subjugate any secondaries
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(other is subjEmp || other is treaty.leader)
				continue;
			if(other.SubjugatedBy is subjEmp) {
				treaty.presentMask |= other.mask;
				treaty.joinedEmpires.insertLast(other);
			}
		}

		//Trigger subjugation
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			if(treaty.joinedEmpires[i] !is treaty.leader)
				subjugate(treaty, treaty.joinedEmpires[i], treaty.leader);
		}
	}

	void subjugate(Treaty& treaty, Empire& emp, Empire& leader) {
		//Set subjugator
		int pts = emp.prevPoints;
		if(emp.SubjugatedBy !is null)
			emp.SubjugatedBy.points -= pts;
		@emp.SubjugatedBy = treaty.leader;
		emp.SubjugatedBy.points += pts;
		treaty.leader.setHostile(emp, false);
		emp.setHostile(treaty.leader, false);

		//Leave all existing treaties
		Lock lck(influenceLock);
		array<Treaty@> treaties = activeTreaties;
		for(uint i = 0, cnt = treaties.length; i < cnt; ++i) {
			auto@ other = treaties[i];
			if(other.id == treaty.id)
				continue;
			if(other.inviteMask & emp.mask != 0)
				declineTreaty(emp, other.id);
			if(other.presentMask & emp.mask != 0)
				leaveTreaty(emp, other.id, force=true);
		}

		//Notify everyone
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other is emp || other is leader)
				continue;
			if(emp.ContactMask & other.mask == 0)
				continue;
			other.notifyTreaty(treaty.id, TET_Subjugate, emp, leader);
		}
	}

	void onJoin(Treaty@ treaty, Clause@ clause, Empire@ joined) const {
		subjugate(treaty, joined, treaty.leader);
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const {
		if(left.SubjugatedBy !is null) {
			int pts = left.prevPoints;
			left.SubjugatedBy.points -= pts;
		}
		@left.SubjugatedBy = null;
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const {
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			if(treaty.joinedEmpires[i] !is treaty.leader)
				@treaty.joinedEmpires[i].SubjugatedBy = null;
		}
	}
#section all
};

class ShareWar : InfluenceClauseHook {
	Document doc("When one member declares war, all members declare war.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const override {
		uint warMask = 0;
		clause.data[hookIndex].store(warMask);
	}

	void onJoin(Treaty@ treaty, Clause@ clause, Empire@ emp) const override {
		uint curMask = 0;
		clause.data[hookIndex].retrieve(curMask);

		for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n) {
			Empire@ other = getEmpire(n);
			if(emp is other)
				continue;

			if(emp.isHostile(other)) {
				if(curMask & other.mask == 0) {
					emp.setHostile(other, false);
					other.setHostile(emp, false);
				}
			}
			else {
				if(curMask & other.mask != 0) {
					emp.setHostile(other, true);
					other.setHostile(emp, true);
				}
			}
		}
	}

	void onLeave(Treaty@ treaty, Clause@ clause, Empire@ left) const override {
		uint allMask = 0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			allMask |= emp.mask;
		}
		left.mutualDefenseMask &= ~allMask;
	}

	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		uint prevMask = 0, newMask = 0;
		clause.data[hookIndex].retrieve(prevMask);

		for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n) {
			auto@ check = getEmpire(n);
			bool wasWar = prevMask & check.mask != 0;

			if(wasWar) {
				bool isAllWar = true;
				for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
					if(!treaty.joinedEmpires[i].isHostile(check)) {
						isAllWar = false;
						continue;
					}
				}

				if(!isAllWar) {
					for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
						auto@ emp = treaty.joinedEmpires[i];
						if(emp.isHostile(check)) {
							emp.setHostile(check, false);
							check.setHostile(emp, false);
						}
					}
				}
				else {
					newMask |= check.mask;
				}
			}
			else {
				bool hasAnyWar = false;
				for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
					if(treaty.joinedEmpires[i].isHostile(check)) {
						hasAnyWar = true;
						continue;
					}
				}

				if(hasAnyWar) {
					for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
						auto@ emp = treaty.joinedEmpires[i];
						if(emp is check) {
							//Boot from treaties that would be at war with yourself
							leaveTreaty(emp, treaty.id, force=true);
							--i; --cnt;
							continue;
						}
						if(!emp.isHostile(check)) {
							emp.setHostile(check, true);
							check.setHostile(emp, true);
						}
					}
					newMask |= check.mask;
				}
			}
		}

		uint allMask = 0;
		if(treaty.leader !is null)
			allMask |= treaty.leader.mask;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			allMask |= emp.mask;
		}
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			emp.mutualDefenseMask |= allMask;
		}

		if(prevMask != newMask)
			clause.data[hookIndex].store(newMask);
	}

	void save(Clause@ clause, SaveFile& file) const {
		uint warMask = 0;
		clause.data[hookIndex].retrieve(warMask);
		file << warMask;
	}

	void load(Clause@ clause, SaveFile& file) const {
		uint warMask = 0;
		if(file >= SV_0070)
			file >> warMask;
		clause.data[hookIndex].store(warMask);
	}
#section all
};

class GainPercentageMoney : InfluenceClauseHook {
	Document doc("Gain a percentage of all members' incomes.");
	Argument factor(AT_Decimal, doc="What percentage to give.");
	Argument count_leader(AT_Boolean, "False", doc="Whether to count the leader's income.");
	Argument count_members(AT_Boolean, "True", doc="Whether to count other members' income.");
	Argument give_leader(AT_Boolean, "True", doc="Whether to give the income to the leader.");
	Argument give_members(AT_Boolean, "False", doc="Whether to give the income to other members.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		double prevAmount = 0.0;
		clause.data[hookIndex].retrieve(prevAmount);

		double newAmount = 0.0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!count_leader.boolean)
					continue;
			}
			else {
				if(!count_members.boolean)
					continue;
			}

			newAmount += factor.decimal * double(emp.TotalBudget);
		}

		if(int(prevAmount) != int(newAmount)) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				auto@ emp = treaty.joinedEmpires[i];
				if(emp is treaty.leader) {
					if(!give_leader.boolean)
						continue;
				}
				else {
					if(!give_members.boolean)
						continue;
				}

				emp.modTotalBudget(int(newAmount) - int(prevAmount), MoT_Vassals);
			}
			clause.data[hookIndex].store(newAmount);
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].retrieve(amount);

		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!give_leader.boolean)
					continue;
			}
			else {
				if(!give_members.boolean)
					continue;
			}

			emp.modTotalBudget(-int(amount), MoT_Vassals);
		}

		amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void save(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		clause.data[hookIndex].retrieve(amount);
		file << amount;
	}

	void load(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		if(file >= SV_0070)
			file >> amount;
		clause.data[hookIndex].store(amount);
	}
#section all
};

class GainPercentageInfluence : InfluenceClauseHook {
	Document doc("Gain a percentage of all members' influence incomes.");
	Argument factor(AT_Decimal, doc="What percentage to give.");
	Argument count_leader(AT_Boolean, "False", doc="Whether to count the leader's influence income.");
	Argument count_members(AT_Boolean, "True", doc="Whether to count other members' influence income.");
	Argument give_leader(AT_Boolean, "True", doc="Whether to give the influence income to the leader.");
	Argument give_members(AT_Boolean, "False", doc="Whether to give the influence income to other members.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		double prevAmount = 0.0;
		clause.data[hookIndex].retrieve(prevAmount);

		double newAmount = 0.0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!count_leader.boolean)
					continue;
			}
			else {
				if(!count_members.boolean)
					continue;
			}

			newAmount += factor.decimal * double(emp.getInfluenceStock());
		}

		if(int(prevAmount) != int(newAmount)) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				auto@ emp = treaty.joinedEmpires[i];
				if(emp is treaty.leader) {
					if(!give_leader.boolean)
						continue;
				}
				else {
					if(!give_members.boolean)
						continue;
				}

				emp.modInfluenceIncome(int(newAmount) - int(prevAmount));
			}
			clause.data[hookIndex].store(newAmount);
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].retrieve(amount);

		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!give_leader.boolean)
					continue;
			}
			else {
				if(!give_members.boolean)
					continue;
			}

			emp.modInfluenceIncome(-int(amount));
		}

		amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void save(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		clause.data[hookIndex].retrieve(amount);
		file << amount;
	}

	void load(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		if(file >= SV_0070)
			file >> amount;
		clause.data[hookIndex].store(amount);
	}
#section all
};

class GainPercentageEnergy : InfluenceClauseHook {
	Document doc("Gain a percentage of all members' energy generation.");
	Argument factor(AT_Decimal, doc="What percentage to give.");
	Argument count_leader(AT_Boolean, "False", doc="Whether to count the leader's energy generation.");
	Argument count_members(AT_Boolean, "True", doc="Whether to count other members' energy generation.");
	Argument give_leader(AT_Boolean, "True", doc="Whether to give the energy generation to the leader.");
	Argument give_members(AT_Boolean, "False", doc="Whether to give the energy generation to other members.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		double prevAmount = 0.0;
		clause.data[hookIndex].retrieve(prevAmount);

		double newAmount = 0.0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!count_leader.boolean)
					continue;
			}
			else {
				if(!count_members.boolean)
					continue;
			}

			newAmount += factor.decimal * (emp.EnergyIncome - emp.EnergyUse);
		}

		if(int(prevAmount) != int(newAmount)) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				auto@ emp = treaty.joinedEmpires[i];
				if(emp is treaty.leader) {
					if(!give_leader.boolean)
						continue;
				}
				else {
					if(!give_members.boolean)
						continue;
				}

				emp.modEnergyIncome(newAmount - prevAmount);
			}
			clause.data[hookIndex].store(newAmount);
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].retrieve(amount);

		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!give_leader.boolean)
					continue;
			}
			else {
				if(!give_members.boolean)
					continue;
			}

			emp.modEnergyIncome(-amount);
		}

		amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void save(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		clause.data[hookIndex].retrieve(amount);
		file << amount;
	}

	void load(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		if(file >= SV_0070)
			file >> amount;
		clause.data[hookIndex].store(amount);
	}
#section all
};

class GainPercentageResearch : InfluenceClauseHook {
	Document doc("Gain a percentage of all members' research generation.");
	Argument factor(AT_Decimal, doc="What percentage to give.");
	Argument count_leader(AT_Boolean, "False", doc="Whether to count the leader's research generation.");
	Argument count_members(AT_Boolean, "True", doc="Whether to count other members' research generation.");
	Argument give_leader(AT_Boolean, "True", doc="Whether to give the research generation to the leader.");
	Argument give_members(AT_Boolean, "False", doc="Whether to give the research generation to other members.");

#section server
	void onStart(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void onTick(Treaty@ treaty, Clause@ clause, double time) const override {
		double prevAmount = 0.0;
		clause.data[hookIndex].retrieve(prevAmount);

		double newAmount = 0.0;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!count_leader.boolean)
					continue;
			}
			else {
				if(!count_members.boolean)
					continue;
			}

			newAmount += factor.decimal * emp.ResearchRate;
		}

		if(int(prevAmount) != int(newAmount)) {
			for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
				auto@ emp = treaty.joinedEmpires[i];
				if(emp is treaty.leader) {
					if(!give_leader.boolean)
						continue;
				}
				else {
					if(!give_members.boolean)
						continue;
				}

				emp.modResearchRate(newAmount - prevAmount);
			}
			clause.data[hookIndex].store(newAmount);
		}
	}

	void onEnd(Treaty@ treaty, Clause@ clause) const {
		double amount = 0.0;
		clause.data[hookIndex].retrieve(amount);

		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			auto@ emp = treaty.joinedEmpires[i];
			if(emp is treaty.leader) {
				if(!give_leader.boolean)
					continue;
			}
			else {
				if(!give_members.boolean)
					continue;
			}

			emp.modResearchRate(-amount);
		}

		amount = 0.0;
		clause.data[hookIndex].store(amount);
	}

	void save(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		clause.data[hookIndex].retrieve(amount);
		file << amount;
	}

	void load(Clause@ clause, SaveFile& file) const {
		double amount = 0;
		if(file >= SV_0070)
			file >> amount;
		clause.data[hookIndex].store(amount);
	}
#section all
};
