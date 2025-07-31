package mob

import la "core:math/linalg"
import r "vendor:raylib"

import "core:c"

GameStateMainMenu :: struct {}
GameStatePlaying :: struct {}

GameState :: union #no_nil {
	  GameStateMainMenu,
	  GameStatePlaying,
}

gState: GameState = GameStateMainMenu{}

SCREEN_SIZE :: [2]f32{320, 180}

mousePos, worldMouse: r.Vector2

cursorData := #load("../assets/cursor.png")

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

scr: r.RenderTexture2D
cursor: r.Texture2D

init :: proc() {
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

	  cI := r.LoadImageFromMemory(".png", &cursorData[0], i32(len(cursorData)))
	  cursor = r.LoadTextureFromImage(cI)
	  r.UnloadImage(cI)

}

deinit :: proc() {
	  r.CloseAudioDevice()
	  r.CloseWindow()
}

shouldRun := true

setWindowSize :: proc(w, h: c.int) {
	  r.SetWindowSize(w, h)
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

	  r.BeginTextureMode(scr);{
		    r.ClearBackground(r.BLACK)

		    switch s in gState {
		    case GameStateMainMenu:
		    case GameStatePlaying:
		    }

		    r.DrawTexturePro(
			      cursor,
			      {0, 0, f32(cursor.width), f32(cursor.height)},
			      {worldMouse.x + 1, worldMouse.y + 1, f32(cursor.width), f32(cursor.height)},
			      {f32(cursor.width) / 2, f32(cursor.height) / 2},
			      cursorTilt * 10,
			      r.BLACK,
		    )

		    r.DrawTexturePro(
			      cursor,
			      {0, 0, f32(cursor.width), f32(cursor.height)},
			      {worldMouse.x, worldMouse.y, f32(cursor.width), f32(cursor.height)},
			      {f32(cursor.width) / 2, f32(cursor.height) / 2},
			      cursorTilt * 10,
			      r.WHITE,
		    )
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
	  };r.EndDrawing()

	  when ODIN_OS != .JS {
		    if r.WindowShouldClose() {
			      shouldRun = false
		    }
	  }
}
