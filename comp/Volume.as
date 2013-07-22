package comp
{
	import flash.display.MovieClip;
	import flash.display.SimpleButton;
    import flash.display.Sprite;
    import flash.events.*;
    import flash.geom.*;
    import flash.media.*;

    public class Volume extends Sprite
    {
        public var slider_mc:MovieClip;
        public var track_mc:MovieClip;
        public var unMute_btn:SimpleButton;
        public var mute_btn:SimpleButton;
        private var secondRect:Rectangle;

        public function Volume()
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
            slider_mc.buttonMode = true;
			mute_btn.visible = false;
            this.mute_btn.addEventListener(MouseEvent.CLICK, this.muteHander);
            this.unMute_btn.addEventListener(MouseEvent.CLICK, this.unMuteHander);
            this.slider_mc.addEventListener(MouseEvent.MOUSE_DOWN, this.mouseDown);
            this.slider_mc.stage.addEventListener(MouseEvent.MOUSE_UP, this.mouseReleased);
            this.secondRect = new Rectangle(this.slider_mc.x, this.track_mc.y, 0, this.track_mc.height);
        }

        private function mouseMoved(event:Event):void
        {
            var soundValue:Number = 1 - (slider_mc.y - track_mc.y) / track_mc.height;
            this.soundValue = soundValue;
        }

        private function setSlider(value:Number):void
        {
            this.slider_mc.y = (1 - value) * this.track_mc.height + this.track_mc.y;
        }

        private function mouseDown(event:MouseEvent):void
        {
            this.slider_mc.stage.addEventListener(MouseEvent.MOUSE_MOVE, this.mouseMoved);
            this.slider_mc.startDrag(false, this.secondRect);
        }
		
        private function set soundValue(value:Number):void
        {
			SoundManager.getInstance().sndTransform.volume = value;
            if (value <= 0)
            {
                this.mute_btn.visible = true;
                this.unMute_btn.visible = false;
				//当手动滑动滑块的时候，vol为0就置为静音
				SoundManager.getInstance().isMute = true;
            }else
            {
                this.mute_btn.visible = false;
                this.unMute_btn.visible = true;
				SoundManager.getInstance().isMute = false;
            }
            this.setSlider(value);
			dispatchEvent(new StreamEvent(StreamEvent.VOL_CHANGE, true));
        }


        private function mouseReleased(event:MouseEvent):void
        {
            this.slider_mc.stage.removeEventListener(MouseEvent.MOUSE_MOVE, this.mouseMoved);
            this.slider_mc.stopDrag();
        }

        private function muteHander(event:Event):void
        {
			SoundManager.getInstance().sndTransform.volume = SoundManager.getInstance().tempVol;
            this.mute_btn.visible = false;
            this.unMute_btn.visible = true;
			this.soundValue = SoundManager.getInstance().sndTransform.volume;
        }

        private function unMuteHander(event:Event)
        {
            SoundManager.getInstance().tempVol = SoundManager.getInstance().sndTransform.volume;
			SoundManager.getInstance().sndTransform.volume = 0;
            this.mute_btn.visible = true;
            this.unMute_btn.visible = false;
			this.soundValue = SoundManager.getInstance().sndTransform.volume;
        }
    }
}
