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

Biome :: enum {
	  GreenZone,
	  StoneHills,
	  BadLands,
	  Arena,
}

Sprite :: enum {
    Null,
	  Cursor,
	  Barrier,
	  FloorGreenZone,
	  FloorStoneHills,
	  FloorBadLands,
	  FloorArena,
	  WallGreenZone,
	  WallStoneHills,
	  WallBadLands,
	  WallArena,
}

spriteMap := [Sprite]SpriteRect {
        .Null            = {},

	      .Cursor          = {0, 0, 7, 7},

	      .Barrier         = {40, 0, 16, 16},

	      .FloorGreenZone  = {8, 0, 16, 16},
	      .FloorStoneHills = {8, 0, 16, 16},
	      .FloorBadLands   = {8, 0, 16, 16},
	      .FloorArena      = {8, 0, 16, 16},

	      .WallGreenZone   = {24, 0, 16, 16},
	      .WallStoneHills  = {24, 0, 16, 16},
	      .WallBadLands    = {24, 0, 16, 16},
	      .WallArena       = {24, 0, 16, 16},
}

Tile :: Sprite

TILE_SIZE :: r.Vector2{16, 16}
BIOME_WIDTH :: 64
BIOME_HEIGHT :: 64

gameMap := [BIOME_HEIGHT * len(Biome)][BIOME_WIDTH]Tile{}

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
}

MAX_WALKERS :: 64

generateBiome :: proc (floor, wall: Tile,
                       c: [2]int,
                       room2x2Chance, room3x3Chance, corridorChance: f32,
                       changeDirChance: f32,
                       spawnWalkerChance: f32,
                       corridorLength: i32,
                       maxIterations: i32 = 64) {
    walkerPool := [MAX_WALKERS]Walker{}

    spawnWalker :: proc (pos: [2]int, pool: ^[MAX_WALKERS]Walker) {
        for &w in pool {
            if w.active do continue

            w = {true, pos, rnd.choice_enum(Direction)}
            return
        }
    }

    spawnWalker(c, &walkerPool)

    mapSize :: [2]int{len(gameMap[0]), len(gameMap)}

    kk := [2]int{-1, 1}

    isFloor :: proc (t: Tile) -> bool {
        return t == .FloorArena ||
            t == .FloorBadLands ||
            t == .FloorGreenZone ||
            t == .FloorStoneHills;
    }

    setMapTileIfCan :: proc (x, y: int, t: Tile) {
        if x < 0 || x >= (mapSize.x) do return
        if y < 0 || y >= (mapSize.y) do return

        if isFloor(gameMap[y][x]) do return
        gameMap[y][x] = t
    }

    step :: proc (w: ^Walker, floor, wall: Tile) {
        setMapTileIfCan(w.pos.x, w.pos.y, floor)

        for x in (w.pos.x-1)..=(w.pos.x+1) {
            for y in (w.pos.y-1)..=(w.pos.y+1) {
                setMapTileIfCan(x, y, wall)
            }
        }

        switch w.direction {
        case .Down:  w.pos.y += 1
        case .Up:    w.pos.y -= 1
        case .Right: w.pos.x += 1
        case .Left:  w.pos.x -= 1
        }

        if w.pos.x == 0 || w.pos.x == (mapSize.x-1) || w.pos.y == 0 || w.pos.y == (mapSize.y-1) {
            w.active = false
        }

        w.pos.x = clamp(w.pos.x, 0, mapSize.x)
        w.pos.y = clamp(w.pos.y, 0, mapSize.y)
    }

    for i in 0..<maxIterations {
        for &w in walkerPool {
            if !w.active do continue

            if rnd.float32() <= room2x2Chance {
                x1 := rnd.choice(kk[:])
                y1 := rnd.choice(kk[:])

                for x in (w.pos.x)..=(w.pos.x+x1) {
                    for y in (w.pos.y)..=(w.pos.y+y1) {
                        setMapTileIfCan(x, y, floor)
                    }
                }

                for x in (w.pos.x-1)..=(w.pos.x+x1+1) {
                    for y in (w.pos.y-1)..=(w.pos.y+y1+1) {
                        setMapTileIfCan(x, y, wall)
                    }
                }
            } else if rnd.float32() <= room3x3Chance {
                for x in (w.pos.x-1)..=(w.pos.x+1) {
                    for y in (w.pos.y-1)..=(w.pos.y+1) {
                        setMapTileIfCan(x, y, floor)
                    }
                }

                for x in (w.pos.x-2)..=(w.pos.x+2) {
                    for y in (w.pos.y-2)..=(w.pos.y+2) {
                        setMapTileIfCan(x, y, wall)
                    }
                }
            } else if rnd.float32() <= corridorChance {
                for i in 0..<corridorLength {
                    if !w.active do break
                    step(&w, floor, wall)
                }
            }

            if !w.active do break
            step(&w, floor, wall)

            if rnd.float32() <= changeDirChance {
                w.direction = rnd.choice_enum(Direction)

                if rnd.float32() <= spawnWalkerChance {
                    spawnWalker(w.pos, &walkerPool)
                }
            }
        }
    }

    for y in 0..<mapSize.y {
        if isFloor(gameMap[y][0]) do gameMap[y][0] = wall
        if isFloor(gameMap[y][mapSize.x-1]) do gameMap[y][mapSize.x-1] = wall
    }

    for x in 0..<mapSize.x {
        if isFloor(gameMap[0][x]) do gameMap[0][x] = wall
        if isFloor(gameMap[mapSize.y-1][x]) do gameMap[mapSize.y-1][x] = wall
    }
}

generateMap :: proc() {
	  gameMap = {}

    generateBiome(.FloorGreenZone, .WallGreenZone,
                  {32, 224},
                  room2x2Chance = .3, room3x3Chance = .03, corridorChance = .05,
                  changeDirChance = .3,
                  spawnWalkerChance = .2,
                  corridorLength = 2)
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
	  player.pos = ({32, 224}+.5) * TILE_SIZE

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

PLAYER_SPEED :: 2.5
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
				        {player.pos.x, player.pos.y, TILE_SIZE.x, TILE_SIZE.y},
				        TILE_SIZE * .5,
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
