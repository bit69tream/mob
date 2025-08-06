package mob

import m "core:math"
import la "core:math/linalg"
import rnd "core:math/rand"
import r "vendor:raylib"

import "core:c"
import "core:fmt"
import "core:math/ease"
import "core:math/noise"
import "core:sort"

GameStateMainMenu :: struct {}
GameStatePlaying :: struct {}

GameState :: union #no_nil {
    GameStateMainMenu,
    GameStatePlaying,
}

gameState: GameState = GameStateMainMenu{}
camera := r.Camera2D{}

SpriteRect :: r.Rectangle

PLAYER_SPRITE_WIDTH :: 10
PLAYER_SPRITE_HEIGHT :: 16

PLAYER_MAX_SPEED :: 1.7
PLAYER_IDLE_TIME :: 1

PLAYER_RUNNING_ANIM_TIMER: f32 : .06
PLAYER_IDLE_ANIM_TIMER: f32 : .01

Player :: struct {
    pos:             r.Vector2,
    speed:           f32,
    posDelta:        r.Vector2,
    idleTime:        f32,
    animFrame:       int,
    runTime:         f32,
    playerAnimTimer: f32,
}

player := Player{}

SCREEN_SIZE :: [2]f32{320, 180}

Sprite :: enum {
    Null,
    Cursor,
    GeneralFloor,
    FloorSandstone0,
    FloorSandstone1,
    FloorSandstone2,
    FloorSandstone3,
    FloorSandstone4,
    FloorGrass0,
    FloorGrass1,
    FloorGrass2,
    FloorGrass3,
    FloorGrass4,
    FloorGrass5,
    FloorGrass6,
    FloorGrass7,
}

spriteYOffset := [Sprite]f32 {
    .Null            = 0,
    .Cursor          = 0,
    .GeneralFloor    = 0,
    .FloorSandstone0 = 0,
    .FloorSandstone1 = 0,
    .FloorSandstone2 = 0,
    .FloorSandstone3 = 0,
    .FloorSandstone4 = 0,
    .FloorGrass0     = 0,
    .FloorGrass1     = 0,
    .FloorGrass2     = 0,
    .FloorGrass3     = 0,
    .FloorGrass4     = 0,
    .FloorGrass5     = 0,
    .FloorGrass6     = 0,
    .FloorGrass7     = 0,
}

spriteMap := [Sprite]SpriteRect {
    .Null            = {},
    .GeneralFloor    = {},
    .Cursor          = {0, 0, 7, 7},
    .FloorSandstone0 = {16, 16 * 0, 16, 16},
    .FloorSandstone1 = {16, 16 * 1, 16, 16},
    .FloorSandstone2 = {16, 16 * 2, 16, 16},
    .FloorSandstone3 = {16, 16 * 3, 16, 16},
    .FloorSandstone4 = {16, 16 * 4, 16, 16},
    .FloorGrass0     = {32, 16 * 0, 16, 16},
    .FloorGrass1     = {32, 16 * 1, 16, 16},
    .FloorGrass2     = {32, 16 * 2, 16, 16},
    .FloorGrass3     = {32, 16 * 3, 16, 16},
    .FloorGrass4     = {32, 16 * 4, 16, 16},
    .FloorGrass5     = {32, 16 * 5, 16, 16},
    .FloorGrass6     = {32, 16 * 6, 16, 16},
    .FloorGrass7     = {32, 16 * 7, 16, 16},
}

Tile :: Sprite

TILE_SIZE :: r.Vector2{16, 16}
MAP_SIZE :: 256

mapFloor := [MAP_SIZE][MAP_SIZE]Tile{}
mapWalls := [MAP_SIZE][MAP_SIZE]bool{}

spriteData := #load("../assets/spritemap.png")
spriteTex: r.Texture2D

mousePos, worldMouse: r.Vector2
cursorTilt: f32 = 0

updateMouse :: proc() {
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

Direction :: enum {
    Left,
    Right,
    Up,
    Down,
}

Walker :: struct {
    active:    bool,
    pos:       [2]int,
    direction: Direction,
    lifetime:  int,
}

MAX_WALKERS :: 32

walkDrunk :: proc(center: [2]int, maxIters: int = 32, lifetimeRange: [2]int = {16, 24}) {
    spawnWalker :: proc(
        pos: [2]int,
        pool: ^[MAX_WALKERS]Walker,
        randomDir: bool = true,
        dir: Direction = .Left,
        lifetimeRange: [2]int,
    ) {
        for &w in pool {
            if w.active do continue

            w = {
                true,
                pos,
                randomDir ? rnd.choice_enum(Direction) : dir,
                int(la.lerp(f32(lifetimeRange.x), f32(lifetimeRange.y), rnd.float32())),
            }
            return
        }
    }

    walkerPool := [MAX_WALKERS]Walker{}

    mapFloor[center.y][center.x] = .GeneralFloor

    spawnWalker(center, &walkerPool, false, .Left, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Right, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Up, lifetimeRange)
    spawnWalker(center, &walkerPool, false, .Down, lifetimeRange)

    DEATH_CHANCE: f32 : 0.01
    REPRODUCTION_CHANCE: f32 : 0.05

    TURN_RIGHT_CHANCE :: 20
    TURN_LEFT_CHANCE :: 30
    TURN_DOWN_CHANCE :: 15
    TURN_UP_CHANCE :: 35

    #assert((TURN_RIGHT_CHANCE + TURN_LEFT_CHANCE + TURN_DOWN_CHANCE + TURN_UP_CHANCE) == 100)

    dirChangeChances := [Direction]int {
        .Right = TURN_RIGHT_CHANCE,
        .Left  = TURN_LEFT_CHANCE,
        .Down  = TURN_DOWN_CHANCE,
        .Up    = TURN_UP_CHANCE,
    }
    dirChangeLookup := [100]Direction{}
    di := 0

    for chance, dir in dirChangeChances {
        for i in 0 ..< chance {
            dirChangeLookup[di] = dir
            di += 1
        }
    }

    for i in 0 ..< maxIters {
        hasWalkerDied := false
        hasWalkerSpawned := false

        for &w in walkerPool {
            if !w.active do continue

            switch w.direction {
            case .Down:
                w.pos.y += 1
            case .Up:
                w.pos.y -= 1
            case .Right:
                w.pos.x += 1
            case .Left:
                w.pos.x -= 1
            }

            curTile := &mapFloor[w.pos.y][w.pos.x]

            curTile^ = .GeneralFloor

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
    mapFloor = {}
    mapWalls = {}

    FRAGMENTS: f64 : 32
    RADIUS: f64 : 32
    center := [2]int{MAP_SIZE / 2, MAP_SIZE / 2}

    for a := 0.0; a <= m.PI * 2; a += (m.PI * 2) / FRAGMENTS {
        offset := [2]int{int(m.round(m.cos(a) * RADIUS)), int(m.round(m.sin(a) * RADIUS))}
        walkDrunk(offset + center)
    }

    INNER_RADIUS: f64 : 12
    for a := 0.0; a < m.PI / 2; a += m.PI / 360.0 {
        offset := [2]int {
            int(m.round(m.cos(a) * INNER_RADIUS + .5)),
            int(m.round(m.sin(a) * INNER_RADIUS + .5)),
        }
        for x in 0 ..= offset.x {
            for y in 0 ..= offset.y {
                mapFloor[center.y + y][center.x + x] = .GeneralFloor
                mapFloor[center.y - y][center.x - x] = .GeneralFloor
                mapFloor[center.y - y][center.x + x] = .GeneralFloor
                mapFloor[center.y + y][center.x - x] = .GeneralFloor
            }
        }
    }

    for a := 0.0; a <= m.PI * 2; a += (m.PI * 2) / FRAGMENTS {
        offset := [2]int {
            int(m.round(m.cos(a) * INNER_RADIUS)),
            int(m.round(m.sin(a) * INNER_RADIUS)),
        }
        walkDrunk(offset + center, 16, {8, 12})
    }

    seedTerrain: i64 = rnd.int63()
    seedVariants: i64 = rnd.int63()

    grassVariants :: []Tile {
        .FloorGrass1,
        .FloorGrass2,
        .FloorGrass3,
        .FloorGrass4,
        .FloorGrass5,
        .FloorGrass6,
        .FloorGrass7,
    }

    sandstoneVarians :: []Tile {
        .FloorSandstone1,
        .FloorSandstone2,
        .FloorSandstone3,
        .FloorSandstone4,
    }


    generateFloorTile :: proc(x, y: int, seedTerrain, seedVariants: i64) -> Tile {
        res := Tile.Null
        p := [2]f64{f64(x), f64(y)}

        v1 := noise.noise_2d(seedTerrain, p * .025)
        v2 := noise.noise_2d(seedVariants, p)

        if v1 < 0 {
            res = .FloorGrass0
            if v2 < -.65 do res = rnd.choice(grassVariants)
        } else {
            res = .FloorSandstone0
            if v2 < -.65 do res = rnd.choice(sandstoneVarians)
        }

        return res
    }

    for y in 0 ..< len(mapFloor) {
        for x in 0 ..< len(mapFloor[y]) {
            if mapFloor[y][x] != .GeneralFloor do continue
            mapFloor[y][x] = generateFloorTile(x, y, seedTerrain, seedVariants)
        }
    }

    isFloor :: proc(s: Sprite) -> bool {
        return int(s) >= int(Sprite.FloorSandstone0) && int(s) <= int(Sprite.FloorGrass7)
    }

    for y in 1 ..< (len(mapFloor) - 1) {
        for x in 1 ..< (len(mapFloor[y]) - 1) {
            if !isFloor(mapFloor[y][x]) do continue

            for xi in -1 ..= 1 {
                for yi in -1 ..= 1 {
                    xx, yy := x + xi, y + yi
                    if isFloor(mapFloor[yy][xx]) do continue
                    mapWalls[yy][xx] = true
                }
            }
        }
    }

    for y in 0 ..< len(mapWalls) {
        for x in 0 ..< len(mapWalls[y]) {
            if mapWalls[y][x] {
                mapFloor[y][x] = generateFloorTile(x, y, seedTerrain, seedVariants)
            }
        }
    }

    player.pos = ({f32(center.x), f32(center.y) - f32(RADIUS)} + .5) * TILE_SIZE
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
    spriteTex = r.LoadTextureFromImage(img)

    defer r.UnloadImage(img)

    camera.zoom = 1.0
    camera.offset.x = f32(r.GetScreenWidth()) * .5
    camera.offset.y = f32(r.GetScreenHeight()) * .5
    camera.target = player.pos
}

init :: proc() {
    generateMap()

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

updatePlayer :: proc() {
    dir := r.Vector2{}

    if r.IsKeyDown(.E) do dir.y -= 1
    if r.IsKeyDown(.D) do dir.y += 1
    if r.IsKeyDown(.S) do dir.x -= 1
    if r.IsKeyDown(.F) do dir.x += 1

    dir = la.normalize0(dir)
    if la.length(dir) > 0 {
        player.idleTime = 0

        if player.speed == 0 {
            player.animFrame = 0
            player.playerAnimTimer = PLAYER_RUNNING_ANIM_TIMER
        }

        player.speed = clamp(0, PLAYER_MAX_SPEED, player.speed + r.GetFrameTime() * 25)
    } else {
        player.speed = 0
        player.runTime = 0

        if player.idleTime == 0 {
            player.playerAnimTimer = PLAYER_IDLE_ANIM_TIMER
            player.animFrame = 0
        }

        player.idleTime += r.GetFrameTime()
    }

    player.posDelta = dir * player.speed
    player.pos += player.posDelta
}

getScreenSize :: proc() -> r.Vector2 {
    return {f32(r.GetScreenWidth()), f32(r.GetScreenHeight())}
}

updateCamera :: proc() {
    camera.target = la.lerp(camera.target, player.pos, .1)
    camera.offset = getScreenSize() * .5
}

OriginPoint :: enum {
    TopLeft,
    Center,
}

drawWallStacked :: proc(pos: r.Vector2) {
    t := camera.target
    dir := la.normalize0(pos - t)

    for i in 0 ..< 16 {
        pd := pos + (dir * f32(i) * 1.015)

        r.DrawTexturePro(
            spriteTex,
            {80, f32(i) * 16, 16, 16},
            {pd.x, pd.y, 16, 16},
            {},
            0,
            r.WHITE,
        )
    }
}

drawSprite :: proc(
    sprite: Sprite,
    pos: r.Vector2,
    rotation: f32 = 0,
    tint: r.Color = r.WHITE,
    originPoint: OriginPoint = .Center,
) {
    rect := spriteMap[sprite]
    origin := r.Vector2{}
    switch originPoint {
    case .TopLeft:
        break
    case .Center:
        origin = {rect.width, rect.height} * .5
    }

    r.DrawTexturePro(
        spriteTex,
        rect,
        {pos.x, pos.y + spriteYOffset[sprite], rect.width, rect.height},
        origin,
        rotation,
        tint,
    )
}

MapDrawingOption :: enum {
    BeforePlayer,
    AfterPlayer,
}

drawMap :: proc() {
    for yi in 0 ..< len(mapFloor) {
        for xi in 0 ..< len(mapFloor[yi]) {
            drawSprite(mapFloor[yi][xi], {f32(xi), f32(yi)} * TILE_SIZE, originPoint = .TopLeft)
        }
    }
}

drawWallMap :: proc() {
    walls := make_dynamic_array([dynamic]r.Vector2, context.temp_allocator)
    for yi in 0 ..< len(mapWalls) {
        for xi in 0 ..< len(mapWalls[yi]) {
            if mapWalls[yi][xi] {
                append(&walls, r.Vector2{f32(xi), f32(yi)} * TILE_SIZE)
            }
        }
    }

    wallCompare :: proc(a, b: r.Vector2) -> int {
        adist, bdist := la.length(a - player.pos), la.length(b - player.pos)

        switch {
        case adist < bdist:
            return 1
        case bdist < adist:
            return -1
        }

        return 0
    }

    sort.quick_sort_proc(walls[:], wallCompare)

    for w in walls {
        drawWallStacked(w)
    }
}

PLAYER_MAX_ANIM_SPRITES :: 6

playerIdleSprites := [PLAYER_MAX_ANIM_SPRITES]r.Rectangle {
    {0, 240, 10, 16},
    {10, 240, 10, 16},
    {20, 240, 10, 16},
    {30, 240, 10, 16},
    {40, 240, 10, 16},
    {50, 240, 10, 16},
}

playerRunningSprites := [PLAYER_MAX_ANIM_SPRITES]r.Rectangle {
    {0, 223, 10, 17},
    {10, 223, 10, 17},
    {20, 223, 10, 17},
    {30, 223, 10, 17},
    {40, 223, 10, 17},
    {50, 223, 10, 17},
}

wrapNumb :: proc(n, limit: int) -> int {
    if n < 0 {
        return (limit) - abs(n)
    } else {
        return n % limit
    }
}

drawPlayer :: proc() {
    playerIdleOrigin :: [2]f32{5, 8}
    playerRunningOrigin :: [2]f32{5, 9}

    pSprite := playerIdleSprites[0]
    o := playerIdleOrigin
    timer := PLAYER_IDLE_ANIM_TIMER

    if player.idleTime >= PLAYER_IDLE_TIME {
        pSprite = playerIdleSprites[player.animFrame]
        o = playerIdleOrigin
        timer = PLAYER_IDLE_ANIM_TIMER
    } else if player.speed > 0 {
        pSprite = playerRunningSprites[player.animFrame]
        o = playerRunningOrigin
        timer = PLAYER_RUNNING_ANIM_TIMER
    }

    m := f32(1.0)
    if worldMouse.x < player.pos.x do m = -1.0

    pSprite.width *= m
    r.DrawTexturePro(
        spriteTex,
        pSprite,
        {player.pos.x, player.pos.y, pSprite.width, pSprite.height},
        o,
        0,
        r.WHITE,
    )

    frameD := int(1)
    p := (player.posDelta.x / abs(player.posDelta.x))
    if p != m {
        frameD = -1
    }

    if player.playerAnimTimer <= 0 {
        player.animFrame = wrapNumb(player.animFrame + frameD, PLAYER_MAX_ANIM_SPRITES)
        player.playerAnimTimer = timer
    } else {
        player.playerAnimTimer -= r.GetFrameTime()
    }
}

update :: proc() {
    s := getScreenSize()

    if s.y < s.x do camera.zoom = s.y / SCREEN_SIZE.y
    else do camera.zoom = s.x / SCREEN_SIZE.x

    updateMouse()
    updateCamera()
    updatePlayer()

    r.BeginDrawing();if r.IsWindowFocused() {
        r.ClearBackground(r.BLACK)

        r.BeginMode2D(camera);{
            drawMap()
            drawWallMap()
            drawPlayer()

            drawSprite(.Cursor, worldMouse + 1, cursorTilt * 10, r.BLACK)
            drawSprite(.Cursor, worldMouse, cursorTilt * 10)
        };r.EndMode2D()

        r.DrawFPS(0, 0)
    };r.EndDrawing()

    when ODIN_OS != .JS {
        if r.WindowShouldClose() {
            shouldRun = false
        }
    }

    free_all(context.temp_allocator)
}
