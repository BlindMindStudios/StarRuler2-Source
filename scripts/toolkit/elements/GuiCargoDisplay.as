#section game
import elements.BaseGuiElement;
import elements.GuiSprite;
import elements.GuiText;
import elements.MarkupTooltip;
import cargo;

class GuiCargoDisplay : BaseGuiElement {
	array<GuiSprite@> icons;
	array<GuiText@> values;

	int padding = 2;

	GuiCargoDisplay(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
	}

	GuiCargoDisplay(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	void update(Object& obj) {
		uint oldCnt = icons.length;
		uint newCnt = obj.cargoTypes;
		for(uint i = newCnt; i < oldCnt; ++i) {
			icons[i].remove();
			values[i].remove();
		}
		icons.length = newCnt;
		values.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i) {
			@icons[i] = GuiSprite(this, recti());
			@values[i] = GuiText(this, recti());
		}

		const Font@ ft = skin.getFont(FT_Normal);
		int x = padding, s = size.height-padding-padding;
		for(uint i = 0; i < newCnt; ++i) {
			auto@ type = getCargoType(obj.cargoType[i]);
			if(type is null)
				continue;
			double amount = obj.getCargoStored(type.id);
			string ttip = format("[font=Medium]$1[/font]\n$2", type.name, type.description);

			icons[i].rect = recti_area(x, padding, s, s);
			icons[i].desc = type.icon;
			setMarkupTooltip(icons[i], ttip);
			x += s + padding;

			string txt = standardize(amount, true);
			int w = ft.getDimension(txt).x + 3;

			values[i].rect = recti_area(x, padding, w, s);
			values[i].text = txt;
			setMarkupTooltip(values[i], ttip);
			x += w + padding;
		}
	}
};
