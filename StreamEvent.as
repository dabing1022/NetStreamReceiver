package  
{
	import flash.events.Event;
	
	/**
	 * ...
	 * @author Childhood
	 */
	public class StreamEvent extends Event 
	{
		public static const PAUSE:String = "pause";
		public static const RESUME:String = "resume";
		public static const VOL_CHANGE:String = "vol_change";
		public function StreamEvent(type:String, bubbles:Boolean=false, cancelable:Boolean=false) 
		{ 
			super(type, bubbles, cancelable);
			
		} 
		
		public override function clone():Event 
		{ 
			return new StreamEvent(type, bubbles, cancelable);
		} 
		
		public override function toString():String 
		{ 
			return formatToString("StreamEvent", "type", "bubbles", "cancelable", "eventPhase"); 
		}
		
	}
	
}