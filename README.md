# MacMischief

A playful macOS menu bar app that brings your desktop to life. Pick a "mischief" from the 🐾 menu and it plays on top of everything you're working on — purely visual, never in your way.

| Mischief | What it does |
|---|---|
| 🐈 **Munchkin Cat** | A 3D short-legged ginger tabby. Wanders, naps, grooms, does zoomies, hops between window tops, stalks and pounces on your cursor, purrs when you rest the cursor on it. |
| 🐺 **Pomsky** | A 3D husky-pom puppy. Sniffs, digs, play-bows, chases your cursor, wags its curled tail, rolls over for belly rubs. |
| 🦾 **Skybolt** | An original armoured jet-suit hero in 3D. Flies, loops, barrel-rolls, makes sonic-boom fly-bys, and lands on your windows. |
| ❄️ **Snowfall** | Snow that piles up on window tops and the Dock. Move a window to shake it off; hover over a pile to roll a snowball and throw it. |
| 🍁 **Autumn Leaves** | Realistic 3D leaves (maple, oak, elm, birch) that flutter and tumble down, heap up on your windows, and scatter when you swish the cursor through them. |

Only one mischief runs at a time.

## The menu bar app

MacMischief lives entirely in your menu bar — there's no Dock icon and no main window. Everything is controlled from the 🐾 icon at the top of the screen.

**The menu.** Clicking the icon opens a colourful popover:

- **Header** with a bouncing emoji and a random cheeky tagline.
- **One card per mischief**: tap a card to start it (it shows an **ON** badge), tap it again to stop it. Starting a new one automatically retires the current one with a short goodbye animation.
- **All quiet 😴** stops whatever is running.
- **Hide during full-screen 🍿** (on by default) fades the overlay out whenever an app goes full screen — handy for movies and presentations.
- **Quit 👋** closes the app.

**The icon changes with the mischief**: a paw when nothing is running, and a cat, dog, bolt, snowflake or leaf while that mischief is active.

**Behaviour**

- MacMischief remembers the last mischief you chose and resumes it the next time you open the app.
- It does not start at login on its own. To open it again after quitting, launch it from Spotlight (⌘ Space → "MacMischief") or the Applications folder.
- Multiple displays are supported: weather effects cover every screen; pets and Skybolt live on the main display.
- To uninstall, quit it from the menu and drag `MacMischief.app` from Applications to the Bin.

## Safe by design

- **Click-through:** the overlay ignores all mouse events — every click goes to your apps.
- **Read-only:** it only reads window *positions* (never titles or contents) to know where snow, leaves and pets can land.
- **Sandboxed:** runs in the macOS App Sandbox and asks for no special permissions.
- **Battery-aware:** adaptive frame rate (30 fps when calm, halved in Low Power Mode), adaptive window polling, and an option to hide during full-screen apps.

## Requirements

- macOS 14 or later
- Xcode command line tools / Swift 6 toolchain (the project builds with Swift Package Manager)

## Build & run

```bash
./build.sh            # build build/MacMischief.app
./build.sh --run      # build and launch from ./build
./build.sh --install  # build, copy to /Applications, and launch
```

Then click the 🐾 icon in the menu bar.

## How it works

- **Overlay:** one transparent, click-through window per screen hosts a SpriteKit scene (snow, speech bubbles, particles). 3D characters render with SceneKit into a second transparent window attached directly beneath it, driven in lock-step with the SpriteKit frame.
- **3D pets:** bodies are sculpted from smoothly blended signed-distance-field primitives, meshed with Surface Nets, painted per vertex, and skinned to a procedural skeleton (2-bone leg IK, tail chains, look-at heads).
- **Leaves:** each leaf texture is painted procedurally (shape, veins, mottling, blemishes) into an atlas; leaves are curled two-sided meshes with a falling-leaf flutter model. Resting leaves are baked into a single mesh.
- **Art:** everything is generated in code — there are no image or model assets besides the app icon.

```
Sources/MacMischief/
├── App/          menu bar app, popover menu, settings
├── Core/         overlay windows, scene, window tracking, geometry
├── Core3D/       3D stage + SDF mesher
├── Mischiefs/    Cat, Dog, Hero, Pets (shared brain), Pets3D, Snow, Leaves
└── Debug/        offline preview renderers
```

## Adding a mischief

Implement the `Mischief` protocol (id, title, emoji, tagline, colours) and return a `MischiefLayer` from `makeLayer(for:)`, then add it to `MischiefRegistry.all`. Layers get `update(dt:)` every frame, `geometryDidChange()` when windows move, and can request the 3D stage via `scene.acquireStage3D`.

## Developer previews

Render preview images without touching the desktop:

```bash
swift build -c release
.build/release/MacMischief --snapshot <dir>     # 2D art, snow, menu
.build/release/MacMischief --snapshot3d <dir>   # 3D pets, hero, leaves
.build/release/MacMischief --iconset <dir>      # app icon iconset
```
