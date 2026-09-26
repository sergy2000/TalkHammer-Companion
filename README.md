# TalkHammer Companion

A small helper for the **TalkHammer** mod for Total War: WARHAMMER III. It lets the rulers in your campaign talk back.

TalkHammer runs inside the game, but the game's scripts can't connect to anything outside of it. This companion passes messages between the mod and the **Player2** app on your computer. Without it, the rulers stay silent.

## What you need

- Windows 10 or 11
- Total War: WARHAMMER III (Steam)
- The **TalkHammer** mod: [https://steamcommunity.com/sharedfiles/filedetails/?id=3808547073]
- The **Player2** app, installed and signed in: [https://player2.game/]

## Installation

1. Download the latest zip from the [Releases] page.
2. Unzip it anywhere, for example your desktop or Documents.
3. Double-click **`TalkHammerCompanion.bat`**.

That's all. Nothing is installed, and it doesn't need admin rights.

The first time you run it, Windows may show **"Windows protected your PC"**, because the file was downloaded from the internet. Click **More info**, then **Run anyway**.

## Every time you play

1. Open the Player2 app.
2. Double-click `TalkHammerCompanion.bat`.
3. Start the game and load a campaign.
4. Open Diplomacy, select a ruler and press **SPEAK**.

Keep the companion window open while you play. Close it whenever you want to stop.

## What the window shows

```
  [ OK ] Found the game: D:\Steam\steamapps\common\Total War WARHAMMER III
  [ OK ] Player2 is running.
  [ .. ] Waiting for the game - start Total War: WARHAMMER III and load a campaign.

  [ OK ] The game is connected. Rulers can speak.

  18:02  A ruler is thinking...
  18:02  A ruler replied (2.1 s)
```

If something is wrong, it tells you what to do in the same window.

## Troubleshooting

**"Could not find Total War: WARHAMMER III"**
The companion looks for the game through Steam. If your game is somewhere unusual, start it with the game folder (the one containing `Warhammer3.exe`):

```
TalkHammerCompanion.bat -GameRoot "D:\Games\Total War WARHAMMER III"
```

You can put that in a shortcut so you only set it up once.

**"Player2 is not running"**
Open the Player2 app and sign in. The companion reconnects on its own.

**In game: "the TalkHammer Companion is not running"**
Start `TalkHammerCompanion.bat` and keep its window open, then try again.

**The window closes straight away**
Right-click `TalkHammerCompanion.bat`, choose **Properties**, tick **Unblock** at the bottom if it's there, and try again.

## How it works

- The mod writes each request as a small file into a folder called `talkhammer_data` in your game folder.
- The companion picks it up, sends it to Player2 on your computer (`127.0.0.1`), and writes the answer back for the mod to read.
- It creates `talkhammer_data` the first time it runs, and clears out old message files by itself.
- It doesn't change any game files, doesn't run in the background once you close it, and doesn't connect to anything except the Player2 app.

It's a single PowerShell script (`TalkHammerCompanion.ps1`), started by the `.bat` file. You can read all of it.

## Privacy

The companion only talks to the Player2 app on your own computer. Your conversations with the rulers are then handled by Player2, under Player2's terms.

## Uninstalling

Delete the companion folder. If you like, also delete the `talkhammer_data` folder inside your game folder.

## License

[MIT](LICENSE)
