// A basic game structure example
// @eigenbom 2017

#include "game.h"
#include "window.h"

#include <memory>

void runGame() {
    std::unique_ptr<Window> window{new Window};
    std::unique_ptr<Game> game{new Game{*window}};

    game->setup();
    while (window->handleEvents()) {
        if (!game->update())
            break;
        game->render();
        window->render();
    }
}

int main(int argc, const char* argv[]) {
    runGame();
    return 0;
}
