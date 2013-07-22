package comp
{
	import flash.display.SimpleButton;
    import flash.display.Sprite;
    import flash.events.Event;
	import flash.events.MouseEvent;

    public class Controller extends Sprite
    {
        public var pause_btn:SimpleButton;
        public var vulme:Volume;
        public var play_btn:SimpleButton;

        public function Controller()
        {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
		
		private function onAddedToStage(e:Event):void 
		{
			removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			init();
		}
	
        private function init():void
        {
			this.alpha = 0;
            this.playValue = "pause";
            this.play_btn.addEventListener(MouseEvent.MOUSE_UP, this.playUpHandler);
            this.pause_btn.addEventListener(MouseEvent.MOUSE_UP, this.pauseUpHandler);
        }

        public function set playValue(value:String):void
        {
            switch(value)
            {
                case "play":
                {
                    this.play_btn.visible = true;
                    this.pause_btn.visible = false;
                    break;
                }
                case "pause":
                {
                    this.play_btn.visible = false;
                    this.pause_btn.visible = true;
                    break;
                }
            }
        }

        private function playUpHandler(event:Event):void
        {
           play_btn.visible = false;
		   pause_btn.visible = true;
		   dispatchEvent(new StreamEvent(StreamEvent.RESUME));
        }
		
        private function pauseUpHandler(event:Event):void
        {
            play_btn.visible = true;
            pause_btn.visible = false;
			dispatchEvent(new StreamEvent(StreamEvent.PAUSE));
        }

    }
}
