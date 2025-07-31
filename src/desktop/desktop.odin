package mobDesktop

import game ".."

main :: proc () {
    game.init()
    defer game.deinit()

    for game.shouldRun {
        game.update()
    }
}
