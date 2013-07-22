package  
{
	import flash.events.EventDispatcher;
	import flash.media.SoundTransform;
	
	/**
	 * ...
	 * @author Childhood
	 */
	public class SoundManager extends EventDispatcher 
	{
		private static var _instance:SoundManager;
		public var sndTransform:SoundTransform;
		public var tempVol:Number;
		public var isMute:Boolean;
		public function SoundManager() 
		{
			sndTransform = new SoundTransform();
		}
		
		public static function getInstance():SoundManager {
			if (_instance == null)
				_instance = new SoundManager();
			return _instance;
		}
		
	}

}