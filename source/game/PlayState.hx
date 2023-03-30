package game;

import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.group.FlxGroup.FlxTypedGroup;
import game.editors.*;
import game.gameplay.*;
import game.gameplay.Highscore.Rating;
import game.stage.*;
import game.subStates.*;
import game.system.charting.ChartDefs.ChartFormat;
import game.system.charting.ChartEvents;
import game.system.charting.ChartLoader;
import game.system.music.Conductor;
import game.ui.GameplayUI;
import game.ui.RatingPopup;

enum GameplayMode
{
	STORY_MODE;
	FREEPLAY;
	CHARTING;
}

typedef PlayStateStruct =
{
	var songName:String;
	var difficulty:String;
	var ?gamemode:GameplayMode;
	var ?startTime:Float;
}

/**
 * the Gameplay State, here's where most "song playing and rhythm game stuff" will actually happen
 */
class PlayState extends MusicBeatState
{
	public static var self:PlayState;

	public var constructor:PlayStateStruct;

	// Song
	public var song:ChartFormat;
	public var music:MusicPlayback;

	public var songName:String = 'test';
	public var difficulty:String = 'normal';

	// Gameplay
	public var lines:FlxTypedGroup<NoteGroup>;

	public var leftSideNotes:NoteGroup;
	public var rightSideNotes:NoteGroup;

	public var playerStrumline:Int = 1;
	public var playerStrums(get, never):NoteGroup;

	@:keep inline function get_playerStrums():NoteGroup
		return lines.members[playerStrumline];

	public var gameUI:GameplayUI;
	public var ratingUI:RatingPopup;
	public var currentStat:Highscore;

	// Cameras
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;
	public var camOver:FlxCamera;

	public var camFollow:FlxObject;

	// Objects
	public var gameStage:BaseStage = null;

	public var player:Character;
	public var opponent:Character;
	public var crowd:Character;

	public function new(constructor:PlayStateStruct):Void
	{
		super();

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		self = this;

		if (constructor != null)
		{
			this.constructor = constructor;

			if (constructor.songName != null)
			{
				if (constructor.difficulty == null)
					constructor.difficulty = 'normal';

				song = ChartLoader.loadSong(constructor.songName, constructor.difficulty);
			}

			if (constructor.gamemode == null)
				constructor.gamemode = FREEPLAY;
		}
	}

	public override function create():Void
	{
		super.create();

		music = new MusicPlayback(constructor.songName, constructor.difficulty);

		camGame = new FlxCamera();
		FlxG.cameras.reset(camGame);

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		camOver = new FlxCamera();
		camOver.bgColor.alpha = 0;
		FlxG.cameras.add(camOver, false);

		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);

		persistentUpdate = persistentDraw = true;

		// initialize gameplay modules
		currentStat = new Highscore();
		ratingUI = new RatingPopup();

		// create the stage
		gameStage = switch (song.metadata.stage)
		{
			/*
				case 'tank', 'military-zone': new military-zone();
				case 'schoolEvil', 'school-glitch': new SchoolGlitch();
				case 'school': new School();
				case 'mallEvil', 'red-mall': new RedMall();
				case 'mall': new Mall();
				case 'highway', 'limo': new Highway();
				case 'philly', 'philly-city': new PhillyCity();
			 */
			case 'spooky', 'haunted-house': new HauntedHouse();
			default: new Stage();
		}
		add(gameStage);

		camGame.zoom = gameStage.cameraZoom;
		camHUD.zoom = gameStage.hudZoom;

		// characters
		if (gameStage.displayCrowd)
			crowd = new Character(400, 130).loadChar(song.metadata.crowd);

		opponent = new Character(100, 100).loadChar(song.metadata.opponent);
		player = new Character(770, 450).loadChar(song.metadata.player, true);

		if (crowd != null)
		{
			if (song.metadata.opponent == song.metadata.crowd)
			{
				crowd.visible = false;
				opponent.setPosition(crowd.x, crowd.y);
			}
			add(crowd);
		}

		add(opponent);
		add(player);

		camFollow.setPosition(Math.floor(opponent.getMidpoint().x + FlxG.width / 4), Math.floor(opponent.getGraphicMidpoint().y - FlxG.height / 2));

		camGame.follow(camFollow, LOCKON, 0.04);
		camGame.focusOn(camFollow.getPosition());

		moveCamera();

		// ui
		gameUI = new GameplayUI();
		addOnHUD(gameUI);

		lines = new FlxTypedGroup<NoteGroup>();
		addOnHUD(lines);

		var yPos:Float = Settings.get("scrollType") == "DOWN" ? FlxG.height - 150 : 55;

		leftSideNotes = new NoteGroup(FlxG.width / 5 - FlxG.width / 7, yPos, opponent);
		lines.add(leftSideNotes);

		rightSideNotes = new NoteGroup(FlxG.width / 3 + FlxG.width / 4, yPos, player);
		lines.add(rightSideNotes);

		controls.onKeyPressed.add(onKeyPress);
		controls.onKeyReleased.add(onKeyRelease);

		songCutscene();

		for (i in 0...lines.members.length)
			lines.members[i].cpuControlled = i != playerStrumline;
	}

	public var inCutscene:Bool = true;

	public function songCutscene():Void
	{
		Conductor.songPosition = Conductor.beatCrochet * 16;
		startCountdown();
	}

	var showCountdown:Bool = true;
	var startedCountdown:Bool = false;

	public inline function startCountdown():Void
	{
		inCutscene = false;
		startedCountdown = true;

		if (!showCountdown)
		{
			Conductor.songPosition = -5;
			return startSong();
		}

		Conductor.songPosition = -(Conductor.beatCrochet * 5);

		gameStage.onCountdownStart();

		var countdownSprites:Array<String> = ['prepare', 'ready', 'set', 'go'];
		var countdownSounds:Array<String> = ['intro3', 'intro2', 'intro1', 'introGo'];

		for (graphic in countdownSprites)
			countdownGraphics.push(FtrAssets.getUIAsset('${graphic}'));

		for (sound in countdownSounds)
			countdownNoises.push(AssetHandler.getAsset('sounds/game/${sound}', SOUND));

		for (strum in lines)
		{
			for (i in 0...strum.babyArrows.members.length)
			{
				var startY:Float = strum.babyArrows.members[i].y;
				strum.babyArrows.members[i].alpha = 0;
				strum.babyArrows.members[i].y -= 32;

				FlxTween.tween(strum.babyArrows.members[i], {y: startY, alpha: 1}, (Conductor.beatCrochet * 4) / 1000,
					{ease: FlxEase.circOut, startDelay: (Conductor.beatCrochet / 1000) + ((Conductor.stepCrochet / 1000) * i)});
			}
		}

		countdown();
	}

	var countdownGraphics:Array<flixel.graphics.FlxGraphic> = [];
	var countdownNoises:Array<openfl.media.Sound> = [];

	var countdownPosition:Int = 0;
	var countdownTween:FlxTween;

	public function countdown():Void
	{
		var countdownSprite = new FlxSprite();
		countdownSprite.cameras = [camHUD];
		countdownSprite.alpha = 0;
		add(countdownSprite);

		new FlxTimer().start(Conductor.beatCrochet / 1000, (tmr:FlxTimer) ->
		{
			gameStage.onCountdownTick(countdownPosition);
			charactersDance(countdownPosition);

			if (countdownGraphics[countdownPosition] != null)
				countdownSprite.loadGraphic(countdownGraphics[countdownPosition]);
			countdownSprite.screenCenter();
			countdownSprite.alpha = 1;

			if (countdownTween != null)
				countdownTween.cancel();

			countdownTween = FlxTween.tween(countdownSprite, {alpha: 0}, 0.6, {
				onComplete: (twn:FlxTween) ->
				{
					if (tmr.loopsLeft == 0) // die
						countdownSprite.destroy();
				},
				ease: FlxEase.sineOut
			});

			if (countdownNoises[countdownPosition] != null)
				FlxG.sound.play(countdownNoises[countdownPosition]);

			countdownPosition++;
		}, 4);
	}

	var startingSong:Bool = true;

	public function startSong():Void
	{
		startingSong = false;
		gameStage.onSongStart();
		music.play(endSong);
	}

	var endingSong:Bool = false;

	public function endSong():Void
	{
		endingSong = true;
		gameStage.onSongEnd();
		music.cease();

		switch (constructor.gamemode)
		{
			case STORY_MODE:
			// placeholder
			case FREEPLAY:
				Highscore.saveScore(Utils.removeForbidden(constructor.songName), constructor.difficulty, currentStat.score);
				FlxG.switchState(new game.menus.FreeplayMenu());
			case CHARTING:
				FlxG.switchState(new game.editors.ChartEditor(constructor));
		}
	}

	var paused:Bool = false;

	public var canPause:Bool = true;

	public override function update(elapsed:Float):Void
	{
		if (startingSong)
		{
			if (startedCountdown && !paused)
			{
				Conductor.songPosition += FlxG.elapsed * 1000;
				if (Conductor.songPosition >= 0)
					startSong();
			}
		}
		else
			Conductor.songPosition = music.inst.time;

		super.update(elapsed);

		if (canPause && controls.justPressed("pause"))
		{
			persistentUpdate = false;
			persistentDraw = true;
			paused = true;

			FlxTween.globalManager.forEach((twn:FlxTween) ->
			{
				if (twn != null && twn.active)
					twn.active = false;
			});

			FlxTimer.globalManager.forEach((tmr:FlxTimer) ->
			{
				if (tmr != null && tmr.active)
					tmr.active = false;
			});

			var pauseSubState = new PauseSubState();
			pauseSubState.camera = camOver;
			openSubState(pauseSubState);
		}

		if (FlxG.keys.justPressed.SIX)
		{
			playerStrums.cpuControlled = !playerStrums.cpuControlled;
			gameUI.cpuText.visible = playerStrums.cpuControlled;
		}

		if (FlxG.keys.justPressed.SEVEN)
			FlxG.switchState(new ChartEditor({songName: constructor.songName, difficulty: constructor.difficulty}));

		if (song != null && !paused)
		{
			spawnNotes();
			parseEvents(ChartLoader.eventList);
			bumpCamera(elapsed);

			if (currentStat.health <= 0 && !playerStrums.cpuControlled)
			{
				music.cease();
				player.stunned = true;
				paused = true;

				persistentUpdate = persistentDraw = false;
				openSubState(new GameOverSubState(player.getGraphicMidpoint().x, player.getGraphicMidpoint().y));
			}

			for (strum in lines)
			{
				if (strum == null)
					return;

				strum.noteSprites.forEachAlive(function(note:Note):Void
				{
					note.speed = Math.abs(song.metadata.speed);

					if (strum.cpuControlled)
					{
						if (!note.wasGoodHit && note.step <= Conductor.songPosition)
							goodNoteHit(note, strum);
					}
					else if (!playerStrums.cpuControlled) // sustain note inputs
					{
						if (notesPressed[note.index] && (note.isSustain && note.canHit && note.strumline == playerStrumline))
							goodNoteHit(note, playerStrums);
					}

					var rangeReached:Bool = note.downscroll ? note.y > FlxG.height : note.y < -note.height;
					var sustainHit:Bool = note.isSustain && note.wasGoodHit && note.step <= Conductor.songPosition - note.hitboxEarly;

					if (Conductor.songPosition > note.killDelay + note.step)
					{
						if (rangeReached || sustainHit)
						{
							if (rangeReached && !note.wasGoodHit && !note.ignorable && !note.isMine)
								if (note.strumline == playerStrumline)
									noteMiss(note.index, strum);

							strum.remove(note, true);
						}
					}
				});
			}
		}
	}

	public override function openSubState(SubState:flixel.FlxSubState):Void
	{
		if (paused)
			music.pause();

		super.openSubState(SubState);
	}

	public override function closeSubState():Void
	{
		if (paused)
		{
			if (!startingSong)
				music.resyncVocals();

			FlxTween.globalManager.forEach((twn:FlxTween) ->
			{
				if (twn != null && !twn.active)
					twn.active = true;
			});

			FlxTimer.globalManager.forEach((tmr:FlxTimer) ->
			{
				if (tmr != null && !tmr.active)
					tmr.active = true;
			});

			paused = false;
		}
		super.closeSubState();
	}

	public var zoomBeat:Int = 4;

	public override function beatHit():Void
	{
		super.beatHit();

		charactersDance(curBeat);
		gameStage.onBeat(curBeat);
		gameUI.beatHit(curBeat);

		if (camZooming)
		{
			if (camGame.zoom < 1.35 && curBeat % zoomBeat == 0)
			{
				camGame.zoom += 0.015;
				camHUD.zoom += 0.05;
			}
		}

		// gameStage.onEventDispatch(event, args);
	}

	public override function stepHit():Void
	{
		super.stepHit();

		gameStage.onStep(curStep);
		music.resyncFunction();
	}

	public override function secHit():Void
	{
		super.secHit();
		gameStage.onSec(curSec);
		moveCamera();
	}

	public function charactersDance(curBeat:Int):Void
	{
		for (strum in lines)
		{
			if (strum.character != null && curBeat % strum.character.headSpeed == 0)
				if (!strum.character.isSinging() && !strum.character.isMissing() && !strum.character.stunned)
					strum.character.dance();
		}

		if (crowd != null && curBeat % crowd.headSpeed == 0)
			if (!crowd.isSinging() && !crowd.stunned)
				crowd.dance();
	}

	public var camZooming:Bool = true;

	public function bumpCamera(elapsed:Float):Void
	{
		// beat zooms
		if (camZooming)
		{
			// base game way
			var lerpValue:Float = 1 - (elapsed * 1.155);
			camGame.zoom = FlxMath.lerp(gameStage.cameraZoom, 1, lerpValue);
			camHUD.zoom = FlxMath.lerp(gameStage.hudZoom, 1, lerpValue);
		}
	}

	public function moveCamera():Void
	{
		var char:Character = opponent;

		if (song.sections[curSec] != null)
		{
			if (song.sections[curSec].camPoint == 2 && crowd != null)
				char = crowd;
			else
				char = (song.sections[curSec].camPoint == 1) ? player : opponent;

			if (camFollow.x != char.getMidpoint().x - 100)
				camFollow.setPosition(char.getMidpoint().x - 100 + char.cameraOffset[0], char.getMidpoint().y - 100 + char.cameraOffset[1]);
		}
	}

	public function spawnNotes():Void
	{
		while (ChartLoader.noteList[0] != null && ChartLoader.noteList[0].step - Conductor.songPosition < 2000)
		{
			var note = ChartLoader.noteList[0];

			var type:String = 'default';
			if (note.type != null)
				type = note.type;

			// "but if the default strumline is 0 why didn't you export the number in the first place?"
			// less characters on the json file, that's all
			if (note.strumline == null || note.strumline < 0)
				note.strumline = 0;

			var strum:NoteGroup = lines.members[note.strumline];

			if (note.sustainTime > 0)
			{
				for (noteSustain in 0...Math.floor(note.sustainTime / Conductor.stepCrochet))
				{
					var sustainStep:Float = note.step + (Conductor.stepCrochet * Math.floor(noteSustain)) + Conductor.stepCrochet;
					var newSustain:Note = new Note(sustainStep, note.index, true, type, strum.noteSprites.members[strum.noteSprites.members.length - 1]);
					newSustain.strumline = note.strumline;
					newSustain.downscroll = Settings.get("scrollType") == "DOWN";
					strum.add(newSustain);
				}
			}

			var newNote:Note = new Note(note.step, note.index, false, type);
			newNote.sustainTime = note.sustainTime;
			newNote.strumline = note.strumline;
			newNote.downscroll = Settings.get("scrollType") == "DOWN";
			strum.add(newNote);

			ChartLoader.noteList.shift();
		}
	}

	public function parseEvents(list:Array<EventLine>, stepDelay:Float = 0):Void
	{
		if (list.length > 0)
		{
			while (list[curSec] != null)
			{
				var event:EventLine = list[curSec];

				if (event != null)
					if ((event.type == Stepper && event.step >= Conductor.songPosition - stepDelay) || event.type != Stepper)
						eventTrigger(event);

				list.splice(list.indexOf(list[0]), 1);
			}
		}
	}

	public function eventTrigger(event:EventLine):Void
	{
		switch (event.name) {}
	}

	public function goodNoteHit(note:Note, strum:NoteGroup):Void
	{
		if (!note.wasGoodHit)
		{
			note.wasGoodHit = true;
			strum.playAnim('confirm', note.index, true);

			var animName:String = 'sing${NoteGroup.directions[note.index].toUpperCase()}${strum.character.suffix}';
			if (song.sections[curSec] != null && song.sections[curSec].animation != null)
			{
				// suffix check
				if (song.sections[curSec].animation.startsWith('-'))
					strum.character.suffix = song.sections[curSec].animation;
				else
					animName = song.sections[curSec].animation;
			}

			strum.character.playAnim(animName, true);
			strum.character.holdTimer = 0;

			if (!strum.cpuControlled)
			{
				var rating:String = SICK;
				if (!note.isSustain)
				{
					currentStat.notesHit++;
					if (currentStat.combo < 0)
						currentStat.combo = 0;
					currentStat.combo++;

					rating = currentStat.judgeNote(note.step);
					currentStat.gottenRatings.set(rating, currentStat.gottenRatings.get(rating) + 1);

					ratingUI.popRating(rating);
					if (rating == SICK && note.doSplash)
						strum.doSplash(note.index, note.type);

					gameUI.updateScore();
				}
				currentStat.updateHealth(Highscore.RATINGS[0].indexOf(rating), note.isSustain);
			}

			if (!note.isSustain)
				strum.remove(note, true);
		}
	}

	public var notesPressed:Array<Bool> = [];

	public function onKeyPress(key:Int, action:String):Void
	{
		if (playerStrums.cpuControlled || paused || !startedCountdown)
			return;

		if (action != null && NoteGroup.directions.contains(action))
		{
			var index:Int = NoteGroup.directions.indexOf(action);
			notesPressed[index] = true;

			var dumbNotes:Array<Note> = [];
			var possibleNotes:Array<Note> = [];

			playerStrums.noteSprites.forEachAlive(function(note:Note):Void
			{
				if (note.canHit && note.strumline == playerStrumline && !note.wasGoodHit)
				{
					if (note.index == index)
						possibleNotes.push(note);
				}
			});
			possibleNotes.sort((a:Note, b:Note) -> Std.int(a.step - b.step));

			if (possibleNotes.length > 0)
			{
				var canBeHit:Bool = true;
				for (note in possibleNotes)
				{
					for (dumbNote in dumbNotes)
					{
						// "dumb" notes are doubles
						if (Math.abs(note.step - dumbNote.step) < 10)
							playerStrums.remove(dumbNote, true);
						else
							canBeHit = false;
					}

					if (canBeHit)
					{
						goodNoteHit(note, playerStrums);
						dumbNotes.push(note);
					}
				}
			}
			else
			{
				if (!Settings.get("ghostTapping"))
					noteMiss(index, playerStrums);
			}

			if (!playerStrums.currentAnim('confirm', NoteGroup.directions.indexOf(action)))
				playerStrums.playAnim('pressed', NoteGroup.directions.indexOf(action));
		}
	}

	public function noteMiss(direction:Int = 0, ?strum:NoteGroup, ?showMiss:Bool = true):Void
	{
		if (currentStat.combo < 0)
			currentStat.combo = 0;
		else
		{
			if (currentStat.combo > 1)
				currentStat.breaks++;

			// miss combo numbers
			currentStat.combo--;
		}

		currentStat.misses++;
		FlxG.sound.play(AssetHandler.getAsset('sounds/game/miss' + FlxG.random.int(1, 3), SOUND), FlxG.random.float(0.3, 0.6));

		var animName:String = 'sing${NoteGroup.directions[direction].toUpperCase()}miss${strum.character.suffix}';
		if (song.sections[curSec] != null && song.sections[curSec].animation != null)
		{
			// suffix check
			if (song.sections[curSec].animation.startsWith('-'))
				strum.character.suffix = song.sections[curSec].animation;
			else
				animName = song.sections[curSec].animation + 'miss';
		}
		strum.character.playAnim(animName, true);

		if (showMiss)
			ratingUI.popRating('miss');

		currentStat.updateHealth(4);
		currentStat.updateRatings(4);
		gameUI.updateScore();
	}

	public function onKeyRelease(key:Int, action:String):Void
	{
		if (playerStrums.cpuControlled || paused || !startedCountdown)
			return;

		if (action != null && NoteGroup.directions.contains(action))
		{
			var index:Int = NoteGroup.directions.indexOf(action);
			notesPressed[index] = false;

			playerStrums.playAnim('static', NoteGroup.directions.indexOf(action));

			if (player != null && player.holdTimer > Conductor.stepCrochet * player.singDuration * 0.001 && !notesPressed.contains(true))
				if (player.isSinging() && !player.isMissing())
					player.dance();
		}
	}

	public function addOnHUD(object:flixel.FlxBasic):Void
	{
		object.camera = camHUD;
		add(object);
	}

	public override function destroy():Void
	{
		controls.onKeyPressed.remove(onKeyPress);
		controls.onKeyReleased.remove(onKeyRelease);

		super.destroy();
	}
}
