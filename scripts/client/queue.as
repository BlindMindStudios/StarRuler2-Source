import elements.BaseGuiElement;
import elements.GuiOverlay;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSkinElement;

QueueResponse@ response;

class QueueResponse : GuiOverlay {
	GuiSkinElement@ bg;
	GuiText@ state;
	GuiButton@ accept, reject;
	double speed = 1;

	QueueResponse() {
		speed = gameSpeed;
		gameSpeed = 0;
	
		super(null);
		@bg = GuiSkinElement(this, Alignment(Left+0.5f-250,Top+0.5f-100,Width=500,Height=200), SS_Dialog);
		
		@state = GuiText(bg, Alignment(Left+10,Top+20,Right-10,Height=28), locale::MP_QUEUE_READY);
		state.font = FT_Medium;
		state.horizAlign = 0.5;
		
		@accept = GuiButton(bg, Alignment(
				Left+0.5f-205, Top+65, Width=200, Height=46),
				locale::MP_QUEUE_ACCEPT);
			accept.font = FT_Medium;
			accept.color = Color(0x88ff88ff);
		
		@reject = GuiButton(bg, Alignment(
				Left+0.5f+5, Top+65, Width=200, Height=46),
				locale::MP_QUEUE_REJECT);
			reject.font = FT_Medium;
			reject.color = Color(0xff8888ff);
		
		updateAbsolutePosition();
		update();
		bringToFront();
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Clicked:
				if(event.caller is accept) {
					if(game_running)
						saveGame(path_join(baseProfile["saves"], "queue_accepted.sr2"));
					cloud::acceptQueue();
					return true;
				}
				else if(event.caller is reject) {
					cloud::rejectQueue();
					remove();
					gameSpeed = speed;
					@response = null;
					return true;
				}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void close() {
		//Absorb the various close events that can occur
	}
	
	void update() {
		uint ready = 0, players = 0;
	
		if(cloud::queueRequest)
			state.text = locale::MP_QUEUE_READY;
		else if(cloud::getQueuePlayerWait(ready, players)) {
			state.text = format(locale::MP_QUEUE_WAITING, ready, players);
			accept.visible = false;
			reject.visible = false;
		}
		else {
			gameSpeed = speed;
			remove();
			@response = null;
			return;
		}
	}
};

void tick(double time) {
	if(response is null && cloud::queueRequest)
		@response = QueueResponse();
	else if(response !is null)
		response.update();
}