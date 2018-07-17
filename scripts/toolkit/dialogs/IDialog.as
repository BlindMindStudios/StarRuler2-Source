import elements.IGuiElement;

interface IDialog {
	void set_position(const vec2i& pos);
	void updatePosition();
	void close();
	void focus();
	bool get_closed();
	IGuiElement@ get_bound();
};
