package mob

import la "core:math/linalg"
import r "vendor:raylib"

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
	      .Cursor          = {0, 0, 7, 7},
	      .Barrier         = {},
	      .FloorGreenZone  = {},
	      .FloorStoneHills = {},
	      .FloorBadLands   = {},
	      .FloorArena      = {},
	      .WallGreenZone   = {},
	      .WallStoneHills  = {},
	      .WallBadLands    = {},
	      .WallArena       = {},
}

Tile :: struct {
	  type: Sprite,
}

TILE_SIZE :: r.Vector2{8, 8}
BIOME_WIDTH :: 64
BIOME_HEIGHT :: 64

gameMap := [BIOME_HEIGHT * len(Biome)][BIOME_WIDTH]Tile{}

spriteData := #load("../assets/spritemap.png")
spriteTex: r.Texture2D

mousePos, worldMouse: r.Vector2
cursorTilt: f32 = 0

updateMouse :: proc(rx, ry, rw, rh: f32) {
	  w := r.GetScreenWidth()
	  h := r.GetScreenHeight()
	  pSize := f32(h) / SCREEN_SIZE.y

	  d := r.GetMouseDelta()
	  xDir := 0 if d.x == 0 else d.x / abs(d.x)
	  cursorTilt = la.lerp(cursorTilt, xDir, 0.3)

	  mousePos = r.Vector2Clamp(mousePos + d, {rx, ry}, {rx + rw, ry + rh})

	  when ODIN_OS == .JS {
		    if r.IsMouseButtonPressed(.LEFT) || r.IsMouseButtonPressed(.RIGHT) {
			      r.DisableCursor()
		    }
	  } else {
		    if r.IsWindowFocused() {
			      r.SetMousePosition(w / 2, h / 2)
		    }
	  }

	  p := mousePos
	  p.x -= rx
	  p.y -= ry
	  worldMouse = r.Vector2Clamp(p / pSize, {}, SCREEN_SIZE)
}

generateMap :: proc() {
	  gameMap = {}
	  for b, bi in Biome {
		    startY := len(gameMap) - ((bi + 1) * BIOME_HEIGHT)
		    endY := startY + BIOME_HEIGHT

		    fmt.println(b, bi, startY, endY)

		    for yi in startY ..< endY {
			      for xi in 0 ..< len(gameMap[yi]) {
				        switch b {
				        case .GreenZone:
					          gameMap[yi][xi].type = .WallGreenZone
				        case .StoneHills:
					          gameMap[yi][xi].type = .WallStoneHills
				        case .BadLands:
					          gameMap[yi][xi].type = .WallBadLands
				        case .Arena:
					          gameMap[yi][xi].type = .WallArena
				        }
			      }
		    }
	  }
}

scr: r.RenderTexture2D

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

	  scr = r.LoadRenderTexture(i32(SCREEN_SIZE.x), i32(SCREEN_SIZE.y))

	  img := r.LoadImageFromMemory(".png", &spriteData[0], i32(len(spriteData)))
	  defer r.UnloadImage(img)

	  spriteTex = r.LoadTextureFromImage(img)

	  camera.zoom = 1.0
	  camera.offset = SCREEN_SIZE * .5
	  camera.target = player.pos
}

init :: proc() {
	  generateMap()
	  player.pos = {32, 224} * TILE_SIZE

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

PLAYER_SPEED :: 3
updatePlayer :: proc() {
	  dir := r.Vector2{}

	  if r.IsKeyDown(.E) do dir.y -= 1
	  if r.IsKeyDown(.D) do dir.y += 1
	  if r.IsKeyDown(.S) do dir.x -= 1
	  if r.IsKeyDown(.F) do dir.x += 1

	  player.pos += la.normalize0(dir) * PLAYER_SPEED
}

updateCamera :: proc() {
	  camera.target = la.lerp(camera.target, player.pos, .1)
}

drawSprite :: proc(sprite: Sprite, pos: r.Vector2, rotation: f32 = 0, tint: r.Color = r.WHITE) {
    rect := spriteMap[sprite]

	  r.DrawTexturePro(
		    spriteTex,
		    rect,
		    {pos.x, pos.y, rect.width, rect.height},
		    {rect.width, rect.height} * .5,
		    rotation,
		    tint,
	  )
}

drawMap :: proc() {
	  for yi in 0 ..< len(gameMap) {
		    /* for xi in 0 ..< len(gameMap[yi]) { */
			  /*     t := gameMap[yi][xi] */
			  /*     r.DrawRectangleV({f32(xi), f32(yi)}*TILE_SIZE, */
			  /*                      TILE_SIZE, */
			  /*                      tileColors[t.biome][t.type]) */
		    /* } */
	  }
}

update :: proc() {
	  sw := f32(r.GetScreenWidth())
	  sh := f32(r.GetScreenHeight())

	  rw, rh: f32 = 0, 0

	  if sh < sw {
		    rh = sh
		    rw = (SCREEN_SIZE.x / SCREEN_SIZE.y) * sh
	  } else {
		    rw = sw
		    rh = (SCREEN_SIZE.y / SCREEN_SIZE.x) * sw
	  }
	  rx := (sw / 2) - (rw / 2)
	  ry := (sh / 2) - (rh / 2)

	  updateMouse(rx, ry, rw, rh)
	  updateCamera()
	  updatePlayer()

	  r.BeginTextureMode(scr);{
		    r.ClearBackground(r.BLACK)

		    /* switch s in gameState { */
		    /* case GameStateMainMenu: */
		    /* case GameStatePlaying: */
		    /* } */

		    r.BeginMode2D(camera);{
			      drawMap()

			      r.DrawRectanglePro(
				        {player.pos.x, player.pos.y, TILE_SIZE.x, TILE_SIZE.y},
				        TILE_SIZE * .5,
				        0,
				        r.RED,
			      )
		    };r.EndMode2D()

		    drawSprite(.Cursor, worldMouse+1, cursorTilt*10, r.BLACK)
		    drawSprite(.Cursor, worldMouse, cursorTilt*10)
	  };r.EndTextureMode()

	  r.BeginDrawing();if r.IsWindowFocused() {
		    r.ClearBackground(r.BLACK)

		    r.DrawTexturePro(
			      scr.texture,
			      {0, 0, SCREEN_SIZE.x, -SCREEN_SIZE.y},
			      {rx, ry, rw, rh},
			      {},
			      0,
			      r.WHITE,
		    )

		    r.DrawFPS(0, 0)
		    r.DrawText(r.TextFormat("%f %f", player.pos.x, player.pos.y), 0, 40, 20, r.WHITE)
	  };r.EndDrawing()

	  when ODIN_OS != .JS {
		    if r.WindowShouldClose() {
			      shouldRun = false
		    }
	  }
}
