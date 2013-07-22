package 
{
	import com.bit101.components.TextArea;
	
	import flash.display.DisplayObjectContainer;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.KeyboardEvent;
	import flash.ui.Keyboard;
	import flash.utils.getTimer;
	
	public class DebugConsole extends Sprite
	{
		private static var debug:TextArea;
		private static var lineNo:uint;
		private static var isDebug:Boolean = true;
		private static var _stage:Stage;
		public function DebugConsole(stage:Stage = null):void
		{
			super();
		}
		
		public static function addDebugLog(stage:Stage, info:String):void{
			if(!isDebug)	return;
			_stage = stage;
			if(debug){
				debug.text += "\n" + lineNo + "-->" + info;
				lineNo ++;
				
				if(lineNo == 350){
					debug.text = "";
					lineNo = 0;
				}
			}else{
				debug = new TextArea(null, 10, 10);
				debug.editable = false;
				debug.width = _stage.stageWidth-60;
				debug.height = _stage.stageHeight-20;
				lineNo = 0;
				debug.text = "==========<51高清>=============";
				_stage.addEventListener(flash.events.KeyboardEvent.KEY_UP, onShowDebug);
			}
		}
		
		private static function onShowDebug(e:flash.events.KeyboardEvent):void{
			if(e.keyCode == Keyboard.HOME){
				if(_stage.contains(debug))
					_stage.removeChild(debug);
				else
					_stage.addChildAt(debug, _stage.numChildren);
			}
		}
	}
}