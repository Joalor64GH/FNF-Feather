package game.menus;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import game.options.Option;
import game.subStates.MusicBeatSubState;

class OptionsMenu extends MusicBeatSubState
{
	public var curSelection:Int = 0;

	public var pageGroup:FlxTypedGroup<FlxText>;
	public var descriptionHolder:FlxText;

	public var pageOptions:Array<Option> = [
		new Option("Scroll Type", "In which direction should notes spawn?", "scrollType"),
		new Option("Ghost Tapping", "If mashing keys should be allowed during gameplay.", "ghostTapping"),
		new Option("Info Display", "Choose what to display on the info text (usually shows time)", "infoText"),
	];

	public override function create():Void
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menus/menuBGBlue'));
		bg.screenCenter(XY);
		bg.scrollFactor.set();
		bg.alpha = 0.8;
		add(bg);

		var pageBG:FlxSprite = new FlxSprite().makeGraphic(Std.int(FlxG.width / 1.3), Std.int(FlxG.height / 1.1), FlxColor.BLACK);
		pageBG.screenCenter(XY);
		pageBG.alpha = 0;
		add(pageBG);

		pageGroup = new FlxTypedGroup<FlxText>();

		for (i in 0...pageOptions.length)
		{
			var name:FlxText = new FlxText(pageBG.x + 10, (40 * i) + pageBG.y + 10, pageBG.width, '${pageOptions[i].name}: ${pageOptions[i].getValue()}');
			name.setFormat(Paths.font('vcr'), 32, 0xFFFFFFFF, LEFT, OUTLINE, 0xFF000000);
			name.alpha = 0;
			name.ID = i;
			pageGroup.add(name);

			FlxTween.tween(name, {alpha: 0.6}, 0.4);
		}

		add(pageGroup);

		FlxTween.tween(pageBG, {alpha: 0.6}, 0.6, {
			onComplete: function(twn:FlxTween):Void
			{
				lockedMovement = false;
				updateSelection();
			}
		});
	}

	var holdTimer:Float = 0;
	var lockedMovement:Bool = true;

	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;

		if (!lockedMovement)
		{
			if (controls.anyJustPressed(["up", "down"]))
			{
				updateSelection(controls.justPressed("up") ? -1 : 1);
				holdTimer = 0;
			}

			var timerCalc:Int = Std.int((holdTimer / 1) * 5);

			if (controls.anyPressed(["up", "down"]))
			{
				holdTimer += elapsed;

				var timerCalcPost:Int = Std.int((holdTimer / 1) * 5);

				if (holdTimer > 0.5)
					updateSelection((timerCalc - timerCalcPost) * (controls.pressed("down") ? -1 : 1));
			}

			if (controls.justPressed("back"))
				FlxG.switchState(new game.menus.MainMenu());
		}
	}

	public function updateSelection(newSelection:Int = 0):Void
	{
		if (pageGroup.members != null && pageGroup.members.length > 0)
			curSelection = FlxMath.wrap(curSelection + newSelection, 0, Std.int(pageGroup.members.length - 1));

		if (newSelection != 0)
			FlxG.sound.play(Paths.sound('scrollMenu'));

		var ascendingIndex:Int = 0;
		for (option in pageGroup)
		{
			option.ID = ascendingIndex - curSelection;
			option.alpha = option.ID == 0 ? 1 : 0.6;
			++ascendingIndex;
		}
	}
}
