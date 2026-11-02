package
{
   import flash.display.MovieClip;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.net.SharedObject;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.utils.describeType;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;

   /**
    * FPS Unlock for Bleach vs. Naruto Sports (5DPLAY, AIR 50.2).
    *
    * WHY THIS WORKS
    * The engine is already frame-rate independent. GameConfig derives
    *   SPEED_PLUS_DEFAULT = 30 / FPS_GAME
    * and every hold/delay constant in the simulation is multiplied by
    * GameConfig.FPS_GAME (e.g. holdFrame = hold * FPS_GAME). One logic tick is
    * consumed per stage frame, so raising FPS_GAME together with stage.frameRate
    * keeps simulation time constant while rendering more frames per second.
    *
    * WHY THE STOCK BUILD IS CAPPED
    * Only two values are ever assigned, from three places:
    *   ConfigVO.applyConfig()          -> setGameFps(30 or 60) by quality tier
    *   GameInterfaceManager.applyConfig() -> MainGame.I.setFPS(30/45/60)
    *   MainGame.setFPS()               -> stage.frameRate, clamped to 30 when
    *                                      GameConfig.IS_LOW_QUALITY is true
    * Because applyConfig() and every goStage() transition re-assert the cap, the
    * unlock has to be re-applied continuously rather than set once.
    *
    * THE IS_LOW_QUALITY TRAP
    * GameRender.render() invokes each registered logic callback TWICE per frame
    * when (IS_LOW_QUALITY && config.isExactMoving) - that is how the stock build
    * fakes 60fps simulation on a 30fps stage. At an unlocked rate that double
    * invoke would run the simulation at 2x speed, so IS_LOW_QUALITY is forced
    * false on every frame while unlocked.
    *
    * NETPLAY SAFETY (important)
    * LockFrameLogic.initServer()/initClient() force setGameFps(30) and gate
    * GameRender.isRender on network lockstep agreement. Overriding FPS_GAME
    * during a networked match changes SPEED_PLUS (30/FPS_GAME) and therefore the
    * local simulation rate, which desynchronises both peers. This plugin detects
    * an active LAN/online match and stands down completely - there is no override.
    *
    * CONTROLS (in game)
    *   F1  toggle HUD          F2 / F3  target +15 / -15 (Shift: +/-1)
    *   F4  toggle unlock / restore stock 60
    *   F5  cycle presets 30/60/90/120/144/165/240
    *   F6  dump the live decrypted roster (dev/diagnostic, see docs/)
    * Target range 20-480; target, unlock state and HUD visibility persist in
    * SharedObject("fps_unlock").
    *
    * Install: copy dist/fps_unlock.swf to <game>/assets/plugin/fps_unlock.swf
    * PluginModel.initByPath("plugin/") auto-registers it; CONFIG.isRunBack=true
    * makes MenuUtils.startBackRun() activate it silently at menu init.
    */
   public dynamic class PluginMain extends MovieClip
   {
      // Consumed by PluginModel.initBySwfIdArray().
      public const CONFIG:Object = {
         "id":"fps_unlock",
         "name":"FPS Unlock",
         "author":"RE",
         "isRunBack":true,
         "isNeedDebug":false
      };

      public static const PLUGIN_VERSION:String = "2.0";
      public static const PRESETS:Array = [30, 60, 90, 120, 144, 165, 240];
      public static const FPS_MIN:int = 20;
      public static const FPS_MAX:int = 480;
      public static const DEFAULT_FPS:int = 120;
      public static const STOCK_FPS:int = 60;

      public static const KEY_HUD:int = 112;      // F1
      public static const KEY_UP:int = 113;       // F2
      public static const KEY_DOWN:int = 114;     // F3
      public static const KEY_TOGGLE:int = 115;   // F4
      public static const KEY_PRESET:int = 116;   // F5
      public static const KEY_DUMP:int = 117;     // F6

      // High priority so enforce() runs BEFORE GameRender.render(), otherwise the
      // first frame after applyConfig() sets IS_LOW_QUALITY=true would still take
      // the double-invoke path and advance the simulation two ticks.
      public static const RENDER_PRIORITY:int = 1000;
      public static const HUD_INTERVAL:int = 200;
      public static const TELEMETRY_INTERVAL:int = 500;
      public static const SAMPLE_INTERVAL:int = 500;

      // Injected by MenuUtils.startBackRun() / MenuUtils.createPluginWindow().
      public var gameRender:*;
      public var mainStage:Stage;
      public var location:MovieClip;

      private var GameConfig:Class;
      private var MainGame:Class;
      private var LANServerCtrl:Class;
      private var LANClientCtrl:Class;
      private var NativeApplication:Class;
      private var FighterModel:Class;
      private var AssisterModel:Class;
      private var MapModel:Class;
      private var FileClass:Class;
      private var FileStreamClass:Class;
      private var FileModeClass:Class;
      private var logFile:*;

      private var targetFps:int = DEFAULT_FPS;
      private var unlocked:Boolean = true;
      private var hudVisible:Boolean = true;
      private var netplaySuspended:Boolean = false;
      private var ready:Boolean = false;

      private var so:SharedObject;
      private var hud:TextField;

      private var frames:int = 0;
      private var sampleStart:int = 0;
      private var measuredFps:Number = 0;
      private var lastHud:int = 0;
      private var lastTelemetry:int = 0;
      private var note:String = "";

      public function PluginMain()
      {
         super();
         // MenuUtils.createPluginWindow() sizes its window from a child named
         // "location"; keep one so the windowed path also works.
         location = new MovieClip();
         location.name = "location";
         location.graphics.beginFill(0x000000, 0);
         location.graphics.drawRect(0, 0, 200, 120);
         location.graphics.endFill();
         addChild(location);
         stop();
      }

      public function initPlugin(param1:Object = null) : void
      {
         if (param1 != null)
         {
            mainStage = param1.mainStage as Stage;
            gameRender = param1.gameRender;
         }

         GameConfig = resolveClass("net.play5d.game.bvn::GameConfig");
         MainGame = resolveClass("net.play5d.game.bvn::MainGame");
         LANServerCtrl = resolveClass("net.play5d.game.bvn.win.ctrls::LANServerCtrl");
         LANClientCtrl = resolveClass("net.play5d.game.bvn.win.ctrls::LANClientCtrl");
         NativeApplication = resolveClass("flash.desktop::NativeApplication");
         FighterModel = resolveClass("net.play5d.game.bvn.data::FighterModel");
         AssisterModel = resolveClass("net.play5d.game.bvn.data::AssisterModel");
         MapModel = resolveClass("net.play5d.game.bvn.data::MapModel");
         // AIR-only APIs, resolved at runtime so this compiles against
         // playerglobal.swc. applicationStorageDirectory is where the game
         // itself writes bvnsave*.json, so it is guaranteed writable.
         FileClass = resolveClass("flash.filesystem::File");
         FileStreamClass = resolveClass("flash.filesystem::FileStream");
         FileModeClass = resolveClass("flash.filesystem::FileMode");

         loadSettings();

         if (GameConfig == null)
         {
            note = "GameConfig unavailable";
            return;
         }

         initLogFile();

         var st:Stage = resolveStage();
         if (st != null)
         {
            st.addEventListener(Event.ENTER_FRAME, onEnterFrame, false, RENDER_PRIORITY);
            st.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true, RENDER_PRIORITY);
         }
         buildHud(st);

         ready = true;
         enforce();
         dumpRoster();
         trace("[fps_unlock] v" + PLUGIN_VERSION + " target=" + targetFps + " unlocked=" + unlocked);
      }

      public function destroy() : void
      {
         ready = false;
         var st:Stage = mainStage;
         if (st != null)
         {
            st.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
            st.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true);
            if (hud != null && hud.parent != null)
            {
               hud.parent.removeChild(hud);
            }
         }
         saveSettings();
      }

      private function onEnterFrame(e:Event) : void
      {
         // This listener is registered at high priority, so an escaping
         // exception would abort the remaining ENTER_FRAME listeners in the same
         // dispatch - including GameRender.render(), which drives the whole
         // simulation. Never let that happen: the unlock must fail silently.
         try
         {
            enforce();
         }
         catch (err:Error)
         {
            note = "enforce error: " + err.errorID;
         }
      }

      private function enforce() : void
      {
         sampleFps();

         if (!ready)
         {
            return;
         }

         // mainStage can be missing if initPlugin() ran before MenuUtils held a
         // stage reference; keep trying to acquire one instead of sitting idle.
         if (mainStage == null)
         {
            var late:Stage = resolveStage();
            if (late != null)
            {
               mainStage = late;
               late.addEventListener(Event.ENTER_FRAME, onEnterFrame, false, RENDER_PRIORITY);
               late.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true, RENDER_PRIORITY);
               buildHud(late);
            }
         }

         // HARD SAFETY: never touch the frame rate during a networked match.
         // LockFrameLogic owns FPS_GAME (30) and gates GameRender.isRender on
         // peer agreement; overriding either desyncs the simulation.
         if (isNetplayActive())
         {
            if (!netplaySuspended)
            {
               netplaySuspended = true;
               note = "NETPLAY LOCK - suspended";
            }
            publishTelemetry();
            updateHud();
            return;
         }

         if (netplaySuspended)
         {
            netplaySuspended = false;
            note = "";
         }

         if (!unlocked)
         {
            publishTelemetry();
            updateHud();
            return;
         }

         applyTarget();
         publishTelemetry();
         updateHud();
      }

      private function applyTarget() : void
      {
         // Must be cleared first: GameRender.render() reads IS_LOW_QUALITY to
         // decide whether to run each logic callback twice per frame.
         if (GameConfig.IS_LOW_QUALITY !== false)
         {
            GameConfig.IS_LOW_QUALITY = false;
         }

         // setGameFps() also refreshes SPEED_PLUS = 30 / FPS_GAME, which every
         // movement, bullet and camera speed in the engine is scaled by.
         if (int(GameConfig.FPS_GAME) != targetFps)
         {
            GameConfig.setGameFps(targetFps);
         }

         if (mainStage != null && !close(Number(mainStage.frameRate), Number(targetFps)))
         {
            mainStage.frameRate = targetFps;
         }

         // MainGame caches _fps and re-applies it on every goStage() transition
         // (goGame/goMosouGame use FPS_GAME, menus use a literal 30), and
         // GameInterfaceManager.applyConfig() pushes 30/45/60 by quality tier.
         // setFPS() is what actually writes stage.frameRate, so drive it too.
         if (MainGame != null)
         {
            try
            {
               var mg:* = MainGame["I"];
               if (mg != null && int(mg["getFPS"]()) != targetFps)
               {
                  mg["setFPS"](targetFps);
               }
            }
            catch (err:Error)
            {
            }
         }
      }

      private function isNetplayActive() : Boolean
      {
         return readActiveFlag(LANServerCtrl) || readActiveFlag(LANClientCtrl);
      }

      // LANServerCtrl.active / LANClientCtrl.active are set true in gameStart()
      // and cleared in gameEnd()/gameQuit(), which brackets exactly the window in
      // which LockFrameLogic owns the frame rate. Reading .I lazily constructs the
      // singleton, but its constructor has no side effects.
      private function readActiveFlag(cls:Class) : Boolean
      {
         if (cls == null)
         {
            return false;
         }
         try
         {
            var inst:* = cls["I"];
            if (inst == null)
            {
               return false;
            }
            return (inst["active"] === true);
         }
         catch (err:Error)
         {
         }
         return false;
      }

      private function resolveStage() : Stage
      {
         if (mainStage != null)
         {
            return mainStage;
         }
         try
         {
            if (NativeApplication != null)
            {
               var na:* = NativeApplication["nativeApplication"];
               if (na != null)
               {
                  var win:* = na["activeWindow"];
                  if (win != null && win["stage"] != null)
                  {
                     return win["stage"] as Stage;
                  }
               }
            }
         }
         catch (err:Error)
         {
         }
         return null;
      }

      private function resolveClass(name:String) : Class
      {
         try
         {
            return getDefinitionByName(name) as Class;
         }
         catch (err:Error)
         {
         }
         return null;
      }

      private function close(a:Number, b:Number) : Boolean
      {
         return Math.abs(a - b) < 0.001;
      }

      private function sampleFps() : void
      {
         var now:int = getTimer();
         frames++;
         if (sampleStart == 0)
         {
            sampleStart = now;
            return;
         }
         var elapsed:int = now - sampleStart;
         if (elapsed >= SAMPLE_INTERVAL)
         {
            measuredFps = Math.round(frames * 10000 / elapsed) / 10;
            frames = 0;
            sampleStart = now;
         }
      }

      private function onKeyDown(e:KeyboardEvent) : void
      {
         var handled:Boolean = true;
         switch (e.keyCode)
         {
            case KEY_HUD:
               hudVisible = !hudVisible;
               if (hud != null)
               {
                  hud.visible = hudVisible;
               }
               saveSettings();
               break;
            case KEY_UP:
               setTargetFps(targetFps + (e.shiftKey ? 1 : 15));
               break;
            case KEY_DOWN:
               setTargetFps(targetFps - (e.shiftKey ? 1 : 15));
               break;
            case KEY_PRESET:
               cyclePreset();
               break;
            case KEY_TOGGLE:
               unlocked = !unlocked;
               if (!unlocked)
               {
                  restoreStock();
               }
               note = unlocked ? "" : "locked to stock " + STOCK_FPS;
               saveSettings();
               break;
            case KEY_DUMP:
               dumpRoster();
               note = "roster dumped";
               break;
            default:
               handled = false;
         }
         if (handled)
         {
            e.stopPropagation();
         }
      }

      private function cyclePreset() : void
      {
         var i:int = PRESETS.indexOf(targetFps);
         i = (i < 0) ? 1 : (i + 1) % PRESETS.length;
         setTargetFps(int(PRESETS[i]));
      }

      private function setTargetFps(value:int) : void
      {
         if (value < FPS_MIN)
         {
            value = FPS_MIN;
         }
         if (value > FPS_MAX)
         {
            value = FPS_MAX;
         }
         if (value == targetFps)
         {
            return;
         }
         targetFps = value;
         unlocked = true;
         note = "";
         saveSettings();
      }

      // Hands the rate back to what ConfigVO.applyConfig() would have produced.
      private function restoreStock() : void
      {
         if (GameConfig == null)
         {
            return;
         }
         try
         {
            GameConfig.setGameFps(STOCK_FPS);
            if (MainGame != null && MainGame["I"] != null)
            {
               MainGame["I"]["setFPS"](STOCK_FPS);
            }
            if (mainStage != null)
            {
               mainStage.frameRate = STOCK_FPS;
            }
         }
         catch (err:Error)
         {
         }
      }

      private function buildHud(st:Stage) : void
      {
         if (st == null)
         {
            return;
         }
         hud = new TextField();
         hud.name = "fps_unlock_hud";
         hud.autoSize = TextFieldAutoSize.LEFT;
         hud.selectable = false;
         hud.mouseEnabled = false;
         hud.multiline = true;
         hud.defaultTextFormat = new TextFormat("_sans", 12, 0x00ff88, true);
         hud.background = true;
         hud.backgroundColor = 0x000000;
         hud.x = 4;
         hud.y = 4;
         hud.visible = hudVisible;
         try
         {
            st.addChild(hud);
         }
         catch (err:Error)
         {
            hud = null;
         }
      }

      private function updateHud() : void
      {
         if (hud == null || !hudVisible || GameConfig == null)
         {
            return;
         }
         var now:int = getTimer();
         if (now - lastHud < HUD_INTERVAL)
         {
            return;
         }
         lastHud = now;

         var engine:* = GameConfig.FPS_GAME;
         var stageRate:String = (mainStage != null) ? String(mainStage.frameRate) : "?";
         var speedPlus:* = GameConfig.SPEED_PLUS;
         var lowq:* = GameConfig.IS_LOW_QUALITY;

         var state:String = netplaySuspended ? "NETPLAY LOCK" : (unlocked ? "ON" : "OFF");
         var txt:String = "FPS UNLOCK v" + PLUGIN_VERSION + "  " + state + "\n"
                        + "target " + targetFps + "   engine " + engine + "   stage " + stageRate + "\n"
                        + "real " + measuredFps.toFixed(1) + "   speed+ " + speedPlus
                        + "   lowQ " + lowq + "\n"
                        + "F1 hud  F2/F3 +-15  F5 preset  F4 toggle";
         if (note != "")
         {
            txt += "\n" + note;
         }
         hud.text = txt;

         try
         {
            if (mainStage != null && hud.parent == mainStage)
            {
               mainStage.setChildIndex(hud, mainStage.numChildren - 1);
            }
         }
         catch (err:Error)
         {
         }
      }

      // Written to the AIR Local Store (#SharedObjects/launch.swf/fps_unlock.sol)
      // so the live state can be verified from outside the process without
      // attaching a debugger. Same mechanism the game uses for its own cache.sol.
      private function publishTelemetry() : void
      {
         if (GameConfig == null)
         {
            return;
         }
         var now:int = getTimer();
         if (now - lastTelemetry < TELEMETRY_INTERVAL)
         {
            return;
         }
         lastTelemetry = now;
         try
         {
            var lowq:Boolean = (GameConfig.IS_LOW_QUALITY === true);
            var stageRate:Number = (mainStage != null) ? Number(mainStage.frameRate) : -1;
            var engine:int = int(GameConfig.FPS_GAME);
            var speedPlus:Number = Number(GameConfig.SPEED_PLUS);

            if (so != null)
            {
               so.data["v"] = PLUGIN_VERSION;
               so.data["t"] = now;
               so.data["target"] = targetFps;
               so.data["engine"] = engine;
               so.data["stage"] = stageRate;
               so.data["measured"] = measuredFps;
               so.data["speedplus"] = speedPlus;
               so.data["lowq"] = lowq;
               so.data["unlocked"] = unlocked;
               so.data["netplay"] = netplaySuspended;
               so.flush();
            }
         }
         catch (err:Error)
         {
         }

         writeStatusFile(engine, stageRate, speedPlus, lowq, now);
      }

      private function initLogFile() : void
      {
         if (FileClass == null)
         {
            return;
         }
         try
         {
            var dir:* = FileClass["applicationStorageDirectory"];
            if (dir == null)
            {
               return;
            }
            logFile = dir["resolvePath"]("fps_unlock_status.txt");
         }
         catch (err:Error)
         {
            logFile = null;
         }
      }

      // Plain-text mirror of the SharedObject telemetry. .sol files are AMF3
      // and awkward to read externally; this one is a plain read.
      private function writeStatusFile(engine:int, stageRate:Number, speedPlus:Number, lowq:Boolean, now:int) : void
      {
         if (logFile == null || FileStreamClass == null || FileModeClass == null)
         {
            return;
         }
         var txt:String =
               "version=" + PLUGIN_VERSION + "\n"
             + "uptime_ms=" + now + "\n"
             + "target=" + targetFps + "\n"
             + "engine_fps_game=" + engine + "\n"
             + "stage_framerate=" + stageRate + "\n"
             + "measured_fps=" + measuredFps.toFixed(1) + "\n"
             + "speed_plus=" + speedPlus + "\n"
             + "speed_plus_default=" + Number(GameConfig.SPEED_PLUS_DEFAULT) + "\n"
             + "is_low_quality=" + lowq + "\n"
             + "unlocked=" + unlocked + "\n"
             + "netplay_suspended=" + netplaySuspended + "\n"
             + "hud_visible=" + hudVisible + "\n";
         try
         {
            var mode:* = FileModeClass["WRITE"];
            var fs:* = new FileStreamClass();
            fs["open"](logFile, mode);
            fs["writeUTFBytes"](txt);
            fs["close"]();
         }
         catch (err:Error)
         {
         }
      }

      private function loadSettings() : void
      {
         try
         {
            so = SharedObject.getLocal("fps_unlock");
            if (so.data["fps"] !== undefined)
            {
               var v:int = int(so.data["fps"]);
               if (v >= FPS_MIN && v <= FPS_MAX)
               {
                  targetFps = v;
               }
            }
            if (so.data["unlocked"] !== undefined)
            {
               unlocked = (so.data["unlocked"] !== false);
            }
            if (so.data["hud"] !== undefined)
            {
               hudVisible = (so.data["hud"] !== false);
            }
         }
         catch (err:Error)
         {
            so = null;
         }
      }

      private function saveSettings() : void
      {
         if (so == null)
         {
            return;
         }
         try
         {
            so.data["fps"] = targetFps;
            so.data["unlocked"] = unlocked;
            so.data["hud"] = hudVisible;
            so.flush();
         }
         catch (err:Error)
         {
            note = "cfg write failed";
         }
      }

      // Writes the live, decrypted roster (FighterModel / AssisterModel / MapModel,
      // parsed from config/*.x by the embedded loader) to a plain-text file so the
      // exact data schema and fileUrl strings can be studied from outside.
      private function dumpRoster() : void
      {
         if (FileClass == null)
         {
            return;
         }
         try
         {
            var dir:* = FileClass["applicationStorageDirectory"];
            if (dir == null)
            {
               return;
            }
            var f:* = dir["resolvePath"]("fps_unlock_roster.txt");
            var txt:String = "";
            txt += "# fighters\r\n";
            txt += dumpModel(FighterModel, "getAllFighters");
            txt += "\r\n# assisters\r\n";
            txt += dumpModel(AssisterModel, "getAllAssisters");
            txt += "\r\n# maps\r\n";
            txt += dumpModel(MapModel, "getAllMaps");
            var mode:* = FileModeClass["WRITE"];
            var fs:* = new FileStreamClass();
            fs["open"](f, mode);
            fs["writeUTFBytes"](txt);
            fs["close"]();
         }
         catch (err:Error)
         {
         }
      }

      private function dumpModel(model:Class, getter:String) : String
      {
         var out:String = "";
         if (model == null)
         {
            return "(model class not found)\r\n";
         }
         try
         {
            var inst:* = model["I"];
            if (inst == null)
            {
               return "(singleton null)\r\n";
            }
            var fn:* = inst[getter];
            if (fn == null)
            {
               return "(no " + getter + ")\r\n";
            }
            var obj:Object = fn() as Object;
            if (obj == null)
            {
               return "(null collection)\r\n";
            }
            var n:int = 0;
            for (var k:String in obj)
            {
               n++;
               out += "[" + k + "]\r\n";
               out += dumpVO(obj[k], 1);
            }
            out += "# count=" + n + "\r\n";
         }
         catch (err:Error)
         {
            out += "(error " + err.errorID + ")\r\n";
         }
         return out;
      }

      private function dumpVO(vo:*, depth:int) : String
      {
         var out:String = "";
         var pad:String = "";
         for (var i:int = 0; i < depth; i++)
         {
            pad += "  ";
         }
         try
         {
            // FighterVO & friends are sealed classes, so for..in yields nothing.
            // describeType().factory exposes every public var and getter.
            var desc:XML = describeType(vo);
            // NOTE: XMLList + XMLList string-concatenates in AS3, it does NOT
            // merge lists; iterate the factory children and filter instead.
            // describeType(instance) puts instance traits directly under <type>;
            // <factory> only appears when a Class object is described.
            var nodes:XMLList = desc.* + desc.factory.*;
            for each (var node:XML in desc.*)
            {
               var nodeName:String = node.localName();
               if (nodeName != "variable" && nodeName != "accessor")
               {
                  continue;
               }
               var key:String = String(node.@name);
               var v:* = vo[key];
               if (v is Array)
               {
                  out += pad + key + "[] = len " + (v as Array).length + "\r\n";
               }
               else if (v == null)
               {
                  out += pad + key + " = null\r\n";
               }
               else if (v is String || v is Number || v is Boolean || v is int || v is uint)
               {
                  out += pad + key + " = " + String(v) + "\r\n";
               }
               else
               {
                  out += pad + key + " = <" + getQualifiedClassName(v) + ">\r\n";
               }
            }
         }
         catch (err:Error)
         {
            out += pad + "(dump error " + err.errorID + ")\r\n";
         }
         return out;
      }

   }
}
