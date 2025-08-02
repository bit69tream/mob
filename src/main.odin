package mob

import la "core:math/linalg"
import m "core:math"
import r "vendor:raylib"
import rnd "core:math/rand"

import "core:c"
import "core:fmt"

GameStateMainMenu :: struct {}
GameStatePlaying :: struct {}

GameState :: union #no_nil {
	  GameStateMainMenu,
	  GameStatePlaying,
}

gameState: GameState = GameStateMainMenu{}
camera := r.Camera2D{}

SpriteRect :: r.Rectangle

Player :: struct {
	  pos: r.Vector2,
}

player := Player{}

SCREEN_SIZE :: [2]f32{320, 180}

Sprite :: enum {
    Null,
	  Cursor,
	  Barrier,
    Floor,
    Wall,
}

spriteMap := [Sprite]SpriteRect {
        .Null = {},
	      .Cursor = {0, 0, 7, 7},
	      .Barrier = {40, 0, 16, 16},
        .Floor = {8, 0, 16, 16},
        .Wall = {24, 0, 16, 16},
}

Tile :: Sprite

TILE_SIZE :: r.Vector2{16, 16}
MAP_SIZE :: 256

gameMap := [MAP_SIZE][MAP_SIZE]Tile{}

spriteData := #load("../assets/spritemap.png")
spriteTex: r.Texture2D

mousePos, worldMouse: r.Vector2
cursorTilt: f32 = 0

updateMouse :: proc () {
	  w := r.GetScreenWidth()
	  h := r.GetScreenHeight()
	  pSize := f32(h) / SCREEN_SIZE.y

	  d := r.GetMouseDelta()
	  xDir := 0 if d.x == 0 else d.x / abs(d.x)
	  cursorTilt = la.lerp(cursorTilt, xDir, 0.3)

	  mousePos = r.Vector2Clamp(mousePos + d, {}, {f32(w), f32(h)})

	  when ODIN_OS == .JS {
		    if r.IsMouseButtonPressed(.LEFT) || r.IsMouseButtonPressed(.RIGHT) {
			      r.DisableCursor()
		    }
	  } else {
		    if r.IsWindowFocused() {
			      r.SetMousePosition(w / 2, h / 2)
		    }
	  }

	  worldMouse = r.GetScreenToWorld2D(mousePos, camera)
}

Direction :: enum {Left, Right, Up, Down}

Walker :: struct {
    active: bool,
    pos: [2]int,
    direction: Direction,
    lifetime: int
}

MAX_WALKERS :: 32

walkDrunk :: proc (center: [2]int, maxIters: int = 32, lifetimeRange: [2]int = {16, 24}) {
    spawnWalker :: proc (pos: [2]int,
                         pool: ^[MAX_WALKERS]Walker,
                         randomDir: bool = true,
                         dir: Direction = .Left,
                         lifetimeRange: [2]int) {
        for &w in pool {
            if w.active do continue

            w = {true,
                 pos,
                 randomDir ? rnd.choice_enum(Direction) : dir,
                 int(la.lerp(f32(lifetimeRange.x),
                             f32(lifetimeRange.y),
                             rnd.float32()))}
            return
        }
    }

    walkerPool := [MAX_WALKERS]Walker{}

    gameMap[center.y][center.x] = .Floor

    spawnWalker(center, &walkerPool, false, .Left, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Right, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Up, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Down, lifetimeRange)

    DEATH_CHANCE: f32 : 0.01
    REPRODUCTION_CHANCE: f32 : 0.05

    TURN_RIGHT_CHANCE :: 20
    TURN_LEFT_CHANCE  :: 30
    TURN_DOWN_CHANCE  :: 15
    TURN_UP_CHANCE    :: 35

    #assert((TURN_RIGHT_CHANCE+TURN_LEFT_CHANCE+TURN_DOWN_CHANCE+TURN_UP_CHANCE) == 100)

    dirChangeChances := [Direction]int{
            .Right = TURN_RIGHT_CHANCE,
            .Left = TURN_LEFT_CHANCE,
            .Down = TURN_DOWN_CHANCE,
            .Up = TURN_UP_CHANCE,
    }
    dirChangeLookup := [100]Direction{}
    di := 0

    for chance, dir in dirChangeChances {
        for i in 0..<chance {
            dirChangeLookup[di] = dir
            di += 1
        }
    }

    for i in 0..<maxIters {
        hasWalkerDied := false
        hasWalkerSpawned := false

        for &w in walkerPool {
            if !w.active do continue

            switch w.direction {
            case .Down:  w.pos.y += 1
            case .Up:    w.pos.y -= 1
            case .Right: w.pos.x += 1
            case .Left:  w.pos.x -= 1
            }

            curTile := &gameMap[w.pos.y][w.pos.x]

            curTile^ = .Floor

            if w.lifetime <= 0 || rnd.float32() < DEATH_CHANCE {
                w.active = false
                continue
            } else if rnd.float32() < REPRODUCTION_CHANCE {
                spawnWalker(w.pos, &walkerPool, lifetimeRange = lifetimeRange)
            }

            w.direction = dirChangeLookup[rnd.int_max(100)]
            w.lifetime -= 1
        }
    }
}

generateMap :: proc() {
    gameMap = {}

    FRAGMENTS: f64 : 32
    RADIUS: f64 : 32
    center := [2]int{MAP_SIZE/2, MAP_SIZE/2}

    for a := 0.0; a <= m.PI*2; a += (m.PI*2)/FRAGMENTS {
        offset := [2]int{int(m.round(m.cos(a)*RADIUS)),
                         int(m.round(m.sin(a)*RADIUS))}
        walkDrunk(offset+center)
    }

    INNER_RADIUS: f64 : 12
    for a := 0.0; a < m.PI/2; a += m.PI/360.0 {
        offset := [2]int{int(m.round(m.cos(a)*INNER_RADIUS+.5)),
                         int(m.round(m.sin(a)*INNER_RADIUS+.5))}
        for x in 0..=offset.x {
            for y in 0..=offset.y {
                gameMap[center.y+y][center.x+x] = .Floor
                gameMap[center.y-y][center.x-x] = .Floor
                gameMap[center.y-y][center.x+x] = .Floor
                gameMap[center.y+y][center.x-x] = .Floor
            }
        }
    }

    for a := 0.0; a <= m.PI*2; a += (m.PI*2)/FRAGMENTS {
        offset := [2]int{int(m.round(m.cos(a)*INNER_RADIUS)),
                         int(m.round(m.sin(a)*INNER_RADIUS))}
        walkDrunk(offset+center, 16, {8, 12})
    }

    gameMap[center.y][center.x] = .Floor
}

initGraphics :: proc() {
	  r.SetConfigFlags({.VSYNC_HINT})

	  r.InitWindow(800, 600, "MOB")
	  r.SetWindowState({.WINDOW_RESIZABLE})
	  r.SetExitKey(.KEY_NULL)
	  /* r.SetTargetFPS(60) */

	  r.InitAudioDevice()

	  when ODIN_OS == .JS {
		    r.DisableCursor()
	  } else {
		    r.HideCursor()
	  }

	  img := r.LoadImageFromMemory(".png", &spriteData[0], i32(len(spriteData)))
	  defer r.UnloadImage(img)

	  spriteTex = r.LoadTextureFromImage(img)

	  camera.zoom = 1.0
	  camera.offset.x = f32(r.GetScreenWidth())*.5
	  camera.offset.y = f32(r.GetScreenHeight())*.5
	  camera.target = player.pos
}

init :: proc() {
	  generateMap()
	  player.pos = ({MAP_SIZE, MAP_SIZE}*.5+.5)*TILE_SIZE

	  initGraphics()
}

deinit :: proc() {
	  r.CloseAudioDevice()
	  r.CloseWindow()
}

shouldRun := true

setWindowSize :: proc(w, h: c.int) {
	  r.SetWindowSize(w, h)
}

PLAYER_SPEED :: 1.5
updatePlayer :: proc() {
	  dir := r.Vector2{}

	  if r.IsKeyDown(.E) do dir.y -= 1
	  if r.IsKeyDown(.D) do dir.y += 1
	  if r.IsKeyDown(.S) do dir.x -= 1
	  if r.IsKeyDown(.F) do dir.x += 1

	  player.pos += la.normalize0(dir) * PLAYER_SPEED
}

getScreenSize :: proc () -> r.Vector2 {
    return {f32(r.GetScreenWidth()), f32(r.GetScreenHeight())}
}

updateCamera :: proc() {
	  camera.target = la.lerp(camera.target, player.pos, .1)
    camera.offset = getScreenSize()*.5
}

OriginPoint :: enum {TopLeft, Center}

drawSprite :: proc(sprite: Sprite,
                   pos: r.Vector2,
                   rotation: f32 = 0,
                   tint: r.Color = r.WHITE,
                   originPoint: OriginPoint = .Center) {
    if sprite == .Null do return

    rect := spriteMap[sprite]
    origin := r.Vector2{}
    switch originPoint {
    case .TopLeft: break
    case .Center: origin = {rect.width, rect.height} * .5
    }

	  r.DrawTexturePro(
		    spriteTex,
		    rect,
		    {pos.x, pos.y, rect.width, rect.height},
		    origin,
		    rotation,
		    tint,
	  )
}

drawMap :: proc() {
	  for yi in 0 ..< len(gameMap) {
		    for xi in 0 ..< len(gameMap[yi]) {
            drawSprite(gameMap[yi][xi], {f32(xi), f32(yi)} * TILE_SIZE, originPoint = .TopLeft)
		    }
	  }
}

update :: proc() {
    s := getScreenSize()

	  /* if s.y < s.x do camera.zoom = s.y / SCREEN_SIZE.y */
	  /* else         do camera.zoom = s.x / SCREEN_SIZE.x */

	  updateMouse()
	  updateCamera()
	  updatePlayer()

	  r.BeginDrawing(); if r.IsWindowFocused() {
		    r.ClearBackground(r.BLACK)

		    r.BeginMode2D(camera); {
			      drawMap()

			      r.DrawRectanglePro(
				        {player.pos.x, player.pos.y, 16, 16},
				        {8, 8},
				        0,
				        r.RED,
			      )

		        drawSprite(.Cursor, worldMouse+1, cursorTilt*10, r.BLACK)
		        drawSprite(.Cursor, worldMouse, cursorTilt*10)
		    }; r.EndMode2D()

		    r.DrawFPS(0, 0)
	  }; r.EndDrawing()

	  when ODIN_OS != .JS {
		    if r.WindowShouldClose() {
			      shouldRun = false
		    }
	  }
}
