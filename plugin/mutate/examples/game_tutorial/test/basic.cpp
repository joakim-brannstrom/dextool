/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2019
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "gtest/gtest.h"

#include "game.h"

#include <memory>

class Basic : public ::testing::Test {
protected:
    Basic() : window{new Window}, game{new Game{*window}} {}

    void SetUp() override { game->setup(); }

    std::unique_ptr<Window> window;
    std::unique_ptr<Game> game;
};

TEST_F(Basic, OneGameStep) {
    game->update();
    game->render();
    window->render();

    EXPECT_EQ(window->layoutEvents.size(), 35160);
}

TEST_F(Basic, StepLeft) {
    // act
    window->inject(WindowEvent::ArrowLeft);
    game->update();
    game->render();
    window->render();

    // assert
    // This is fragil because internal changes to the game which do not
    // actually affect the funtionality may lead to this test failing. This is
    // why it would never be accepted by a competent peer reviewer.
    EXPECT_EQ(window->layoutEvents.size(), 35150);
}
