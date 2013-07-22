package  
{
	import comp.Controller;
	import fl.motion.easing.Back;
	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.NetStatusEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.SyncEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.media.SoundTransform;
	import flash.media.Video;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.SharedObject;
	import flash.system.Security;
	import flash.text.TextField;
	import flash.ui.ContextMenu;
	import flash.ui.ContextMenuItem;
	import flash.utils.getTimer;
	import flash.utils.Timer;
	import gs.TweenMax;
	import com.bit101.components.TextArea;
	/**
	 * 51高清直播Flash控件
	 * @author Childhood
	 */
	public class Receive extends Sprite 
	{
		/**版本号*/
		private const VERSION:String = "Version:v1.9";
		/**缓冲区时间*/
		private const MIN_BUFFER_TIME:Number = 0.5;
		private const MAX_BUFFER_TIME:Number = 3;
		/**视频*/
		private var video:Video;
		private var debug_mc:MovieClip;
		private var controller:Controller;
		/**加载动画*/
		private var loadingMc:LoadingMc;
		
		private var pConnection:NetConnection;
		private var stream:NetStream;
		private var controllerStatus:String = "";
		private var playURL:String;
		private var fileName:String;
		private var isPlaying:Boolean = true;
		
		private var playType:uint = 0;
		private var noStreamMc:NoStreamMc;
		
		private var debugToJS:Boolean = true;//是否要跟js交互，让控制台输出信息
		/**非直播视频播放是否循环播放*/
		private var isLoop:Boolean = true;
		private var debugConsole:TextArea;
		private var isDebug:Boolean = true;
		private var streamOpt:int = 0;//0:音视频，1：仅音频，2：仅视频
		
		private var state:uint = 0;
		private var isConnecting = false;
		private var hasStopLive = false;//js是否已经告知flash主播下麦停止直播
		
		private const MAX_BUFFER_EMPTY_RECONNECT_TIME = 20;
		private var bufferEmptyReconnectTime;
		private var bufferEmptyTimer:Timer;
		private var totalTimer:Timer;
		private var reconnectTimer:Timer;
		private var customClient:Object;
		private var emptyCount:int;
		public function Receive():void
		{
			addEventListener(Event.ADDED_TO_STAGE, onSetUp);
		}
		
		private function onSetUp(e:Event):void {
			stage.align = StageAlign.TOP_LEFT;
			Security.allowDomain("*");
			
			DebugConsole.addDebugLog(stage, "");
			DebugConsole.addDebugLog(stage, "版本：" + VERSION);
			showRightClickMenu();
			initCustomClient();
			
			addVideo();
			addLoadingMc();
			addNoStreamMc();
			if (ExternalInterface.available) {
				ExternalInterface.call("getVersion", VERSION);
				ExternalInterface.addCallback("getVersion", getVersion); 
				ExternalInterface.addCallback("palyLive", playLive); 
				ExternalInterface.addCallback("stopLive", stopLive);				
				ExternalInterface.addCallback("getState", getState);
				
				ExternalInterface.addCallback("connectSoundStream", connectSoundStream);
				ExternalInterface.addCallback("connectSoundandVideoStream", connectSoundandVideoStream);
				ExternalInterface.addCallback("setStreamOpt", setStreamOpt);
				ExternalInterface.addCallback("getStreamOpt", getStreamOpt);
			}
			
			removeEventListener(Event.ADDED_TO_STAGE, onSetUp);
			stage.addEventListener(Event.RESIZE, onResizeHandler);
			stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveHandler);
			stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeaveHandler);
				
			initTotalTimer();
			initBufferEmptyTimer();
			initReconnectTimer();
		}
		
		private function initCustomClient():void
		{
			customClient = new Object();
			customClient.onMetaData = function oMD():void { };
			customClient.onCuePoint = function oCP():void { };         
		}
		
		private function metaDataHandler(infoObject:Object):void {}
		
		private function initTotalTimer():void 
		{
			totalTimer = new Timer(1000);
			totalTimer.addEventListener(TimerEvent.TIMER, onTotalTimerHandler);
			totalTimer.start();
		}
		
		private function initBufferEmptyTimer():void
		{
			bufferEmptyReconnectTime = 0;
			bufferEmptyTimer = new Timer(1000);
			bufferEmptyTimer.addEventListener(TimerEvent.TIMER, onBufferEmptyTimerHandler);
		}
		
		private function initReconnectTimer():void
		{
			reconnectTimer = new Timer(3000);
			reconnectTimer.addEventListener(TimerEvent.TIMER, onDelayConnect);			
		}
		
		private function onBufferEmptyTimerHandler(e:TimerEvent):void 
		{
			bufferEmptyReconnectTime ++;
			if (bufferEmptyReconnectTime >= MAX_BUFFER_EMPTY_RECONNECT_TIME) {
				resetBufferEmptyTimer();
				delayNetConnect();
			}
		}
		
		private function resetBufferEmptyTimer():void
		{
			bufferEmptyTimer.reset();
			bufferEmptyReconnectTime = 0;
			DebugConsole.addDebugLog(stage, "重置BufferEmpty计时器");
		}
		
		private function getState():uint 
		{
			DebugConsole.addDebugLog(stage, "return state: " + state);
			return state;
		}
		
		/**
		 * 当swf没有被加载完毕，外部js调用GetVersion会返回异常，被捕捉到后，执行catch语句
		 * @example/ try {
						ocxObj.getVersion(version); 
					}catch(e) {
						version = 0;
					}
		 * 如果捕捉到了0，就说明没有被加载完毕
		 */
		private function getVersion(version:String):void {
			ExternalInterface.call("trace", VERSION);
		}
		
		private function addLoadingMc():void {
			loadingMc = new LoadingMc();
			addChild(loadingMc);
			loadingMc.x = (stage.stageWidth - loadingMc.width) / 2;
			loadingMc.y = (stage.stageHeight - loadingMc.height) / 2;
			loadingMc.visible = false;
		}
		
		/**
		 * 当没有流的时候显示一个无流信息的影片剪辑
		 */
		private function addNoStreamMc():void {
			noStreamMc = new NoStreamMc();
			noStreamMc.x = stage.stageWidth >> 1
			noStreamMc.y = stage.stageHeight >> 1;
			addChild(noStreamMc);
			noStreamMc.visible = true;
		}
		
		private function onMouseLeaveHandler(e:Event):void 
		{
			lifeTime = 0;
			hideController();
		}
		
		/**
		 * 播放视频
		 * @param fileName 流媒体名字
		 * @param playURL  流媒体地址
		 * @param playType 流媒体类型(1.直播2.非直播)
		 */
		private function playLive(fileName:String, playURL:String, playType:uint):void {
			this.playURL = playURL;
			this.fileName = fileName;
			this.playType = playType;
			DebugConsole.addDebugLog(stage, "流地址:" + this.playURL + "/" + this.fileName);
			
			if (!pConnection) {
				pConnection = new NetConnection();
				pConnection.client = this;
				pConnection.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
				pConnection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
				pConnection.connect(playURL);
				isConnecting = true;
			}else {
				connectStream();
			}
		}
	
		private function netStatusHandler(event:NetStatusEvent):void {
			DebugConsole.addDebugLog(stage, event.info.code);
            switch (event.info.code) {
                case "NetConnection.Connect.Success":
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "连接服务器成功");
                    connectStream();
					state = 0;
					emptyCount = 0;
					reconnectTimer.reset();
					isConnecting = false;
					//pConnection.call("checkBandwidth", null);
                    break;
				case "NetStream.Play.Start":
					if (ExternalInterface.available) {
						ExternalInterface.call("trace", "开始播放");
					}
					state = 1;
					noStreamMc.visible = false;
					onStreamStart();
					resetBufferEmptyTimer();
					break;
                case "NetStream.Play.StreamNotFound":
					state = 0;
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "没有发现流")
					try {
						if (stream != null) {
							stream.removeEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
							stream.close();
							stream = null;
						}
					}catch (e:Error) {
						DebugConsole.addDebugLog(stage, "stream close failure...");
					}
					loadingMc.visible = false;
					noStreamMc.visible = true;
					delayNetConnect();
                    break;
				case "NetStream.Play.Failed":
					state = 0;
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "NetStream.Play.Failed");
					loadingMc.visible = false;
					noStreamMc.visible = true;
					delayNetConnect();
					break;
				case "NetConnection.Connect.Closed":
					state = 0;
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "NetConnection.Connect.Closed");
					loadingMc.visible = false;
					noStreamMc.visible = true;
					if(!hasStopLive)//如果js没有通知flash主播下麦
						delayNetConnect();	
                    break;
				case "NetStream.Play.Stop":
					state = 0;
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "视频播放完毕");	
					loadingMc.visible = false;
					noStreamMc.visible = true;
					break;
				case "NetStream.Buffer.Full":
					resetBufferEmptyTimer();
					break;
				case "NetStream.Buffer.Empty":
					state = 0;	
					emptyCount++;
					if(ExternalInterface.available)
						ExternalInterface.call("trace", "NetStream.Buffer.Empty");
					if (stream) {
						stream.bufferTime = MIN_BUFFER_TIME + emptyCount * 0.1;
						if (stream.bufferTime >= MAX_BUFFER_TIME)
							stream.bufferTime = MAX_BUFFER_TIME;
						DebugConsole.addDebugLog(stage, "BufferTime==>" + stream.bufferTime);
						resetBufferEmptyTimer();
						DebugConsole.addDebugLog(stage, "开启BufferEmpty计时器");
						bufferEmptyTimer.start();
					}
					break;
            }
        }
		
		private function onTotalTimerHandler(e:TimerEvent):void
		{
			if (!stream || !pConnection.connected)	return;
			DebugConsole.addDebugLog(stage, "bufferLength/bufferTime===>" + stream.bufferLength + "/" + stream.bufferTime);
			DebugConsole.addDebugLog(stage, "流帧频:" + int(stream.currentFPS));
		}
		
		private function delayNetConnect():void {
			DebugConsole.addDebugLog(stage, "是否正在重连？==>" + isConnecting);
			if (isConnecting)	return;
			reconnectTimer.reset();
			reconnectTimer.start();
		}
		
		private function onDelayConnect(e:TimerEvent):void 
		{
			DebugConsole.addDebugLog(stage, "开始重连...");
			pConnection.connect(playURL);
			isConnecting = true;
		}

		private function onStreamStart():void 
		{
			hasStopLive = false;
			DebugConsole.addDebugLog(stage, "流开始播放...");
			loadingMc.visible = false;
			loadingMc.stop();
			
			if(controller == null)
				addController();
		}
		
		private function stopLive():void {
			try {
				if (stream != null) {
					stream.removeEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
					stream.close();
					stream = null;
				}
				video.clear();
                video.visible = false;
			}catch (e:Error) {
				DebugConsole.addDebugLog(stage, "stream close failure...");
			}
			loadingMc.visible = false;
			noStreamMc.visible = true;
			isPlaying = false;
			hasStopLive = true;
			DebugConsole.addDebugLog(stage, "流已经关闭...");
		}
		
		private function addVideo():void 
		{
			video = new Video();
			video.width = stage.stageWidth;
			video.height = stage.stageHeight;
			addChild(video);
			video.x = stage.stageWidth - video.width >> 1;
			video.y = stage.stageHeight - video.height >> 1;
		}
	
		public function onBWCheck(...arg):Number 
		{
			return 0;
		}
		public function onBWDone(...arg):void
		{ 
		}
		
		private function securityErrorHandler(event:SecurityErrorEvent):void {
			DebugConsole.addDebugLog(stage, "SecurityErrorHandler: " + event);
        }
		
		private function connectStream():void {
			if (!pConnection.connected) {
				delayNetConnect();
			}
			DebugConsole.addDebugLog(stage, "流缓冲中...");
			loadingMc.visible = true;
			loadingMc.play();
			
			stream = new NetStream(pConnection);
			stream.client = customClient;
			stream.bufferTime = MAX_BUFFER_TIME;				
			DebugConsole.addDebugLog(stage, "流帧频:" + int(stream.currentFPS));

			//0:音视频，1：仅音频，2：仅视频
			if (streamOpt == 0 || streamOpt == 2) {
				stream.receiveVideo(true);
				video.attachNetStream(stream);
				video.smoothing = true;
				video.deblocking = 2;
				video.visible = true;
			}else if (streamOpt == 1) {
				connectSoundStream();
			}
			
			
			if (SoundManager.getInstance().sndTransform == null) {
				SoundManager.getInstance().sndTransform = stream.soundTransform;
				SoundManager.getInstance().sndTransform.volume = 0.8;
			}else {
				SoundManager.getInstance().sndTransform.volume = SoundManager.getInstance().isMute? 0 : SoundManager.getInstance().sndTransform.volume;
				stream.soundTransform = SoundManager.getInstance().sndTransform;
			}
			if (streamOpt == 2) {
				SoundManager.getInstance().sndTransform.volume = 0;
			}
			
			if(!stream.hasEventListener(NetStatusEvent.NET_STATUS))
				stream.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);			
            stream.play(fileName);
		}
		
		/**
		 * 加入控制器
		 * 包括音量的高低、静音、播放暂停等控制
		 */
		private function addController():void 
		{
			controller = new Controller();
			addChild(controller);
			controller.x = stage.stageWidth - 35;
            controller.y = stage.stageHeight / 2 - this.controller.height / 2;
			controller.addEventListener(StreamEvent.PAUSE, onPauseStream);
			controller.addEventListener(StreamEvent.RESUME, onResumeStream);
			controller.addEventListener(StreamEvent.VOL_CHANGE, onVolChange);
		}
		
		private function onVolChange(e:StreamEvent):void 
		{
			DebugConsole.addDebugLog(stage, "音量：" + SoundManager.getInstance().sndTransform.volume.toFixed(2));
			stream.soundTransform = SoundManager.getInstance().sndTransform;
		}
		
		private function onMouseMoveHandler(e:MouseEvent):void 
		{
			if(controllerStatus == "" || controllerStatus == "hide" || controllerStatus == "hided")
				showController();
		}
		
		private var timer:Timer;
		private var lifeTime:Number = 0;
		private function showController():void {
			trace("showController");
			controllerStatus = "show";
			TweenMax.to(controller, 1, { ease:Back.easeOut, alpha:1, onComplete:onFinishTween1 } );
		}
		
		private function onFinishTween1():void {
			controllerStatus = "showed";
			if (timer == null) {
				timer = new Timer(1000);
				timer.addEventListener(TimerEvent.TIMER, timeout);
			}
			timer.reset();
			timer.start();
		}
		
		private function onFinishTween2():void {
			controllerStatus = "hided";
		}
		
		private function timeout(e:TimerEvent):void {
			lifeTime += 1;
			if (controllerStatus == "showed") {
				if (!controller.hitTestPoint(mouseX, mouseY, false) && lifeTime > 3) {
					lifeTime = 0;
					hideController();
				}
			}
		}

		/**
		 * 重置尺寸事件
		 * @param	event
		 */
		private function onResizeHandler(event:Event):void {
			if (controller) {
				controller.x = stage.stageWidth - 35;
				controller.y = stage.stageHeight / 2 - this.controller.height / 2;
			}
			if (loadingMc) {
				loadingMc.x = (stage.stageWidth - loadingMc.width) / 2;
				loadingMc.y = (stage.stageHeight - loadingMc.height) / 2;
			}
			
			if (noStreamMc) {
				noStreamMc.x = stage.stageWidth >> 1
				noStreamMc.y = stage.stageHeight >> 1;
			}
			
			if (video) {
				video.x = stage.stageWidth - video.width >> 1;
				video.y = stage.stageHeight - video.height >> 1;
			}
		}
		
		private function hideController():void {
			controllerStatus = "hide";
			TweenMax.to(controller, 0.5, { alpha:0, onComplete:onFinishTween2 } );
		}
		
		private function onPauseStream(e:StreamEvent):void 
		{
			if (!stream)	return;
			stream.pause();
			isPlaying = false;
			DebugConsole.addDebugLog(stage, "pause stream...");
		}
		
		private function onResumeStream(e:StreamEvent):void 
		{
			if (!stream)	return;
			stream.togglePause();
			isPlaying = true;
			DebugConsole.addDebugLog(stage, "resume stream...");
		}
		
		private function showRightClickMenu():void {
			var expandmenu = new ContextMenu();
			expandmenu.hideBuiltInItems();
			var customMenu:ContextMenuItem = new ContextMenuItem("51高清娱乐", true);
			var versionMenu:ContextMenuItem = new ContextMenuItem(VERSION, true, false);
			expandmenu.customItems.push(versionMenu);
			expandmenu.customItems.push(customMenu);
			this.contextMenu = expandmenu;
		}
		
		public function onMetaData(info:Object):void {
			trace("metadata: duration=" + info.duration + " width=" + info.width + " height=" + info.height + " framerate=" + info.framerate);
		}
		public function onCuePoint(info:Object):void {
			trace("cuepoint: time=" + info.time + " name=" + info.name + " type=" + info.type);
		}
		
		private function connectSoundStream():void {
			stream.receiveVideo(false);
			noStreamMc.visible = true;
			video.visible = false;
			video.clear();
			//setStreamOpt(1);
		}
		
		private function connectSoundandVideoStream():void {			
			if (!pConnection) {
				pConnection = new NetConnection();
				pConnection.client = this;
				pConnection.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
				pConnection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
				pConnection.connect(this.playURL);
				isConnecting = true;
			}else {
				connectStream();
			}
			setStreamOpt(0);
		}
		
		private function setStreamOpt(val:int): void {
			this.streamOpt = val;
			DebugConsole.addDebugLog(stage, "streamOpt:" + streamOpt);
		}
		
		private function getStreamOpt(val:int): int {
			DebugConsole.addDebugLog(stage, "streamOpt:" + val);
			return this.streamOpt;			
		}
	}

}
