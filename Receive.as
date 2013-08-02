package  
{
	import comp.Controller;
	import fl.motion.easing.Back;
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.NetDataEvent;
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
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	import flash.display.Loader;
	import com.bit101.components.TextArea;
	/**
	 * 51高清直播Flash控件
	 * @author Childhood
	 */
	public class Receive extends Sprite 
	{
		/**版本号*/
		private const VERSION:String = "Version:v1.6";
		/**缓冲区时间*/
		private const MIN_BUFFER_TIME:Number = 3;
		private const MAX_BUFFER_TIME:Number = 10;
		/**视频*/
		private var video:Video;
		private var controller:Controller;
		/**加载动画*/
		private var loadingMc:LoadingMc;
		/**无流logo*/
		private var noStreamMc:NoStreamMc;
		
		private var pConnection:NetConnection;
		private var pStream:NetStream;
		private var controllerStatus:String = "";
		private var playURL:String;
		private var fileName:String = "null";
		/**流状态*/
		private var streamStatus:String;
		/**流播放状态*/
		private var playStatus:String;
		
		/**播放类型：1.直播2.非直播*/
		private var playType:uint = 0;
		
		private const MAX_BUFFER_EMPTY_RECONNECT_TIME = 20;
		private var bufferEmptyReconnectTime;
		private var bufferEmptyTimer:Timer;
		private var totalTimer:Timer;
		private var customClient:Object;
		private var emptyCount:int;
		private var delayConnecting:Boolean = false;
		
		private var countTimer:Timer;
		private var fullDate:Date;
		private var emptyDate:Date;
		private var emptySec:Number = 0;
		private var currTimeSec:Number;
		private var currEmptyTime:Number;
		private var emptyTimeSum:Number;
		private var isCountEmpty:Boolean = false;
		/**UnpublishNotify次数*/
		private var UPNFlag = 0;
		private var reconnectTimeOut:uint;
		private var screenshotBmp:Bitmap;
		private var screenshotBmpd:BitmapData;
		private var isNetworkChange:Boolean = false;
		/**bufferLength持续为0的统计次数*/
		private var bufferLengthZeroCount:int = 0;
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
			}
			
			removeEventListener(Event.ADDED_TO_STAGE, onSetUp);
			stage.addEventListener(Event.RESIZE, onResizeHandler);
			stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveHandler);
			stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeaveHandler);
				
			streamStatus = Status.STREAM_NULL;
			playStatus = Status.PLAY_CLOSE;
			initTotalTimer();
			initBufferEmptyTimer(); 
			initSocket();			
		}
		
		private function initCustomClient():void
		{
			customClient = new Object();
			customClient.onMetaData = onMetaDataHandler;
			customClient.onCuePoint = onCuePointHandler;
			customClient.onImageData = onImageDataHandler;           
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
		
		private function initSocket()
		{
			pStream = null;
			pConnection = null;
		}
		
		private function onBufferEmptyTimerHandler(e:TimerEvent):void 
		{
			bufferEmptyReconnectTime ++;
			DebugConsole.addDebugLog(stage, "bufferEmptyReconnectTime: " + bufferEmptyReconnectTime);
			if (bufferEmptyReconnectTime >= MAX_BUFFER_EMPTY_RECONNECT_TIME)
			{
				resetBufferEmptyTimer();
				if (streamStatus == Status.STREAM_EMPTY)
				{
					//20秒内还没有缓冲好数据,就可以重新连接
					delayNetConnect();
				}
			}
		}
		
		private function resetBufferEmptyTimer():void
		{
			bufferEmptyTimer.reset();
			bufferEmptyReconnectTime = 0;
			DebugConsole.addDebugLog(stage, "重置停止BufferEmpty计时器");
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
		private function getVersion(version:String):void
		{
			ExternalInterface.call("trace", VERSION);
		}
		
		private function addLoadingMc():void
		{
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
		private function playLive(fileName:String, playURL:String, playType:uint):void 
		{
			this.playURL = playURL;
			this.fileName = fileName;
			this.playType = playType;
			DebugConsole.addDebugLog(stage, "流地址:" + this.playURL + "/" + this.fileName);
			
			startNetConnection();
			playStatus = Status.PLAY_START;
		}
		
		private function netConnectionStatusHandler(event:NetStatusEvent):void 
		{
			DebugConsole.addDebugLog(stage, event.info.code);
            switch (event.info.code)
			{
                case "NetConnection.Connect.Success":
                    connectStream();
					emptyCount = 0;
                    break;
				case "NetConnection.Connect.Failed":
					delayNetConnect();
					break;
				case "NetConnection.Connect.Closed":
					drawScrennShot();
					delayNetConnect();	
					break;
				case "NetConnection.Connect.NetworkChange":
					isNetworkChange = true;
					break;				
            }
        }
	
		private function netStreamStatusHandler(event:NetStatusEvent):void 
		{
			DebugConsole.addDebugLog(stage, event.info.code);
            switch (event.info.code)
			{
                case "NetStream.Play.Start":
					resetBufferEmptyTimer();
					streamStatus = Status.STREAM_START;
					DebugConsole.addDebugLog(stage, "流开始播放...");
					startCount();
					noStreamMc.visible = false;
					loadingMc.visible = false;
					if (controller == null)
					{
						addController();
					}
					break;
				case "NetStream.Play.UnpublishNotify":
					streamStatus = Status.STREAM_UNPUBLISHNOTIFY;
					UPNFlag += 1;
					DebugConsole.addDebugLog(stage, "UPNFlag:" + UPNFlag);
					startNetConnection();
					break;
                case "NetStream.Play.StreamNotFound":
					closeConnectStream();
					loadingMc.visible = false;
					noStreamMc.visible = true;
					delayNetConnect();
                    break;
				case "NetStream.Buffer.Full":
					resetBufferEmptyTimer();
					streamStatus = Status.STREAM_FULL;
					if (streamStatus == Status.STREAM_EMPTY)
					{
						countFull();
					}
					break;
				case "NetStream.Buffer.Empty":
					streamStatus = Status.STREAM_EMPTY;
					countEmpty();
					emptyCount++;
					if (pStream)
					{
						pStream.bufferTime = MIN_BUFFER_TIME + emptyCount * 0.2;
						if (pStream.bufferTime >= MAX_BUFFER_TIME)
						{
							pStream.bufferTime = MAX_BUFFER_TIME;
						}
						DebugConsole.addDebugLog(stage, "BufferTime==>" + pStream.bufferTime);
						resetBufferEmptyTimer();
						DebugConsole.addDebugLog(stage, "开启BufferEmpty计时器");
						bufferEmptyTimer.start();
					}
					break;
            }
        }
		
		private function drawScrennShot():void
		{
			if (screenshotBmpd)	return;
			screenshotBmpd = new BitmapData(video.width, video.height);
			screenshotBmpd.draw(video);
			screenshotBmp = new Bitmap(screenshotBmpd);
			addChild(screenshotBmp);
			screenshotBmp.width = 480;
			screenshotBmp.height = 360;
			screenshotBmp.x = (stage.stageWidth - screenshotBmp.width)/2;
			screenshotBmp.y = (stage.stageHeight - screenshotBmp.height)/2;
			screenshotBmp.z = 100;
		}
		
		private function clearScreenShot():void
		{
			if (screenshotBmp)
			{
				if (this.contains(screenshotBmp))
				{
					removeChild(screenshotBmp);
					screenshotBmpd.dispose();
					screenshotBmpd = null;
					screenshotBmp = null;
				}
			}
		}
		
		private function startCount():void
		{
			if (!countTimer)
			{
				countTimer = new Timer(1000);
				countTimer.addEventListener(TimerEvent.TIMER, countTimerHandler);
			}
			countTimer.reset();
			countTimer.start();
			countTimer.repeatCount = 30 + int(Math.random() * 10);
			
			currEmptyTime = 0;
			emptyTimeSum = 0;
			currTimeSec = 0;
			emptySec = 0;
			if (streamStatus == Status.STREAM_EMPTY)
			{
				emptyDate = new Date();
				currEmptyTime = emptyDate.getTime();
			}
		}
		
		private function countTimerHandler(e:TimerEvent):void
		{
			currTimeSec = countTimer.currentCount;
			if (currTimeSec >= countTimer.currentCount)
			{
				debugLogCountSum();
			}
		}
		
		private function debugLogCountSum():void
		{
			emptyTimeSum = 0;
			if (streamStatus == Status.STREAM_EMPTY && emptyDate)
			{
				fullDate = new Date();
				var fullTime:Number = fullDate.getTime();
				var dt:Number = fullTime - currEmptyTime;
				var timeString:String = emptySec + "|" + dt;
				DebugConsole.addDebugLog(stage, timeString);
			}
			emptySec = 0;
			currTimeSec = 0;
			isCountEmpty = false;
			emptyDate = null;
			startCount();
		}
		
		private function countFull():void
		{
			if (emptyDate)
			{
				fullDate = new Date();
				var fullTimeSec:Number = fullDate.getTime();
				var dt:Number = fullTimeSec - currEmptyTime;
				DebugConsole.addDebugLog(stage, "dt=" + dt);
				fullDate = null;
			}
		}
		
		private function countEmpty():void
		{
			isCountEmpty = true;
			emptySec = currTimeSec;
			DebugConsole.addDebugLog(stage, "countEmpty=" + emptySec);
			emptyDate = new Date();
			currEmptyTime = emptyDate.getTime();
		}
		
		private function onTotalTimerHandler(e:TimerEvent):void
		{
			if (!pStream || !pConnection.connected)	return;
			//如果流帧频大于0，则清除画面静止截图
			if (pStream.currentFPS > 0)
				clearScreenShot();
			//如果流bufferLength为0，则统计次数+1
			if (pStream.bufferLength == 0)
				bufferLengthZeroCount ++;
			//一旦不为0，则统计次数归0
			else
				bufferLengthZeroCount = 0;
			//bufferLength持续为0统计次数大于MAX_BUFFER_EMPTY_RECONNECT_TIME次数,并且主播没下麦，则重新连接
			if (bufferLengthZeroCount > MAX_BUFFER_EMPTY_RECONNECT_TIME && playStatus != Status.PLAY_CLOSE) 
			{
				bufferLengthZeroCount = 0;
				startNetConnection();
			}
			DebugConsole.addDebugLog(stage, "bufferLength/bufferTime===>" + pStream.bufferLength + "/" + pStream.bufferTime + ", 流帧频:" + int(pStream.currentFPS));
		}
		
		private function delayNetConnect():void {
			var reconnectHandler:Function = function()
			{
				delayConnecting = false;
				clearTimeout(reconnectTimeOut);
				if (playStatus != Status.PLAY_CLOSE)
				{
					startNetConnection();
				}
			}
			if (delayConnecting == false && playStatus != Status.PLAY_CLOSE) 
			{
				delayConnecting = true;
				reconnectTimeOut = setTimeout(reconnectHandler, 1000);
				DebugConsole.addDebugLog(stage, "重连中...");
			}
		}
		
		/**开始连接流地址*/
		private function startNetConnection():void
		{
			closeConnect();
			pConnection = new NetConnection();
			if (!pConnection.hasEventListener(NetStatusEvent.NET_STATUS))
			{
				pConnection.addEventListener(NetStatusEvent.NET_STATUS, netConnectionStatusHandler);
			}
			if (!pConnection.hasEventListener(SecurityErrorEvent.SECURITY_ERROR))
			{
				pConnection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
			}
			pConnection.client = this;	
			pConnection.connect(playURL);
			DebugConsole.addDebugLog(stage, "初始化连接...");
		}
		
		/**下麦通知停止直播*/
		private function stopLive():void 
		{
			closeConnectStream();
			clearScreenShot();
			video.clear();
            video.visible = false;
			loadingMc.visible = false;
			noStreamMc.visible = true;
			playStatus = Status.PLAY_CLOSE;
			DebugConsole.addDebugLog(stage, "直播结束关闭流...");
		}
		
		private function closeConnectStream():void
		{
			closeConnect();
			closeStream();
		}
		
		private function closeConnect():void
		{
			if (pConnection)
			{
				pConnection.removeEventListener(NetStatusEvent.NET_STATUS, netConnectionStatusHandler);
				pConnection.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
				pConnection.close();
				pConnection = null;
				DebugConsole.addDebugLog(stage, "关闭连接...");
			}	
		}
				
		private function closeStream():void
		{
			if (pStream)
			{
				pStream.removeEventListener(NetStatusEvent.NET_STATUS, netStreamStatusHandler);
				pStream.close();
				pStream = null;
				DebugConsole.addDebugLog(stage, "关闭流...");
			}
			resetBufferEmptyTimer();
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
		
		private function securityErrorHandler(event:SecurityErrorEvent):void
		{
			DebugConsole.addDebugLog(stage, "安全错误: " + event);
        }
		
		private function connectStream():void
		{
			loadingMc.visible = true;
			
			closeStream();
			pStream = new NetStream(pConnection);
			DebugConsole.addDebugLog(stage, "初始化流...");
			if (pStream != null)
			{
				pStream.client = customClient;
				pStream.bufferTime = MIN_BUFFER_TIME;		
				pStream.addEventListener(NetStatusEvent.NET_STATUS, netStreamStatusHandler);

				if (SoundManager.getInstance().sndTransform == null)
				{
					SoundManager.getInstance().sndTransform = pStream.soundTransform;
					SoundManager.getInstance().sndTransform.volume = 0.8;
				}
				else
				{
					SoundManager.getInstance().sndTransform.volume = SoundManager.getInstance().isMute? 0 : SoundManager.getInstance().sndTransform.volume;
					pStream.soundTransform = SoundManager.getInstance().sndTransform;
				}
			}
			if (fileName != "null" && fileName != "")
			{
				pStream.play(fileName);
				pStream.receiveVideo(true);
				video.clear();
				video.attachNetStream(pStream);
				video.smoothing = true;
				video.visible = true;
			}
			else
			{
				DebugConsole.addDebugLog(stage, "流名不能为空！");
			}
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
			pStream.soundTransform = SoundManager.getInstance().sndTransform;
		}
		
		private function onMouseMoveHandler(e:MouseEvent):void 
		{
			if (controllerStatus == "" || controllerStatus == "hide" || controllerStatus == "hided")
			{
				showController();
			}
		}
		
		private var timer:Timer;
		private var lifeTime:Number = 0;
		private function showController():void
		{
			trace("showController");
			controllerStatus = "show";
			TweenMax.to(controller, 1, { ease:Back.easeOut, alpha:1, onComplete:onFinishTween1 } );
		}
		
		private function onFinishTween1():void
		{
			controllerStatus = "showed";
			if (timer == null)
			{
				timer = new Timer(1000);
				timer.addEventListener(TimerEvent.TIMER, timeout);
			}
			timer.reset();
			timer.start();
		}
		
		private function onFinishTween2():void 
		{
			controllerStatus = "hided";
		}
		
		private function timeout(e:TimerEvent):void 
		{
			lifeTime += 1;
			if (controllerStatus == "showed") 
			{
				if (!controller.hitTestPoint(mouseX, mouseY, false) && lifeTime > 3) 
				{
					lifeTime = 0;
					hideController();
				}
			}
		}

		/** 
		 * 重置尺寸事件
		 * @param	event
		 */
		private function onResizeHandler(event:Event):void
		{
			DebugConsole.addDebugLog(stage, "舞台大小重置适应");
			if (controller)
			{
				controller.x = stage.stageWidth - 35;
				controller.y = stage.stageHeight / 2 - this.controller.height / 2;
			}
			if (loadingMc)
			{
				loadingMc.x = (stage.stageWidth - loadingMc.width) / 2;
				loadingMc.y = (stage.stageHeight - loadingMc.height) / 2;
			}
			
			if (noStreamMc)
			{
				noStreamMc.x = stage.stageWidth >> 1
				noStreamMc.y = stage.stageHeight >> 1;
			}
			
			if (video)
			{
				video.width = stage.stageWidth;
				video.height = stage.stageHeight;
				video.x = stage.stageWidth - video.width >> 1;
				video.y = stage.stageHeight - video.height >> 1;
			}
		}
		
		private function hideController():void 
		{
			controllerStatus = "hide";
			TweenMax.to(controller, 0.5, { alpha:0, onComplete:onFinishTween2 } );
		}
		
		private function onPauseStream(e:StreamEvent):void 
		{
			if (!pStream)	return;
			pStream.pause();
			DebugConsole.addDebugLog(stage, "pause stream...");
		}
		
		private function onResumeStream(e:StreamEvent):void 
		{
			if (!pStream)	return;
			pStream.togglePause();
			DebugConsole.addDebugLog(stage, "resume stream...");
		}
		
		private function showRightClickMenu():void
		{
			var expandmenu = new ContextMenu();
			expandmenu.hideBuiltInItems();
			var customMenu:ContextMenuItem = new ContextMenuItem("51高清娱乐", true);
			var versionMenu:ContextMenuItem = new ContextMenuItem(VERSION, true, false);
			expandmenu.customItems.push(versionMenu);
			expandmenu.customItems.push(customMenu);
			this.contextMenu = expandmenu;
		}
		
		public function onMetaDataHandler(info:Object):void
		{
		}	
		public function onCuePointHandler(info:Object):void
		{
		}
		public function onImageDataHandler(imageData:Object):void
		{
		}
	}
}
