#include "rendersystem.h"

#include "game.h"

RenderSystem::RenderSystem(Game& game) : game_(game), randomArray2D_(64, 64, 0) {
    for (int& v : randomArray2D_.data()) {
        v = randInt(0, INT32_MAX);
    }
}

void RenderSystem::update() {
    const int slowBy = 2;
    static int slowDown = 0;
    bool updateAnimation = slowDown++ >= slowBy;
    if (updateAnimation)
        slowDown = 0;

    tick_++;

    for (auto& sprite : game_.sprites.values()) {
        if (updateAnimation) {
            if (sprite.animated) {
                sprite.frameCounter++;
                if (sprite.frameCounter >= sprite.frameRate && !sprite.frames.empty()) {
                    sprite.frame = (sprite.frame + 1) % sprite.frames.size();
                    sprite.frameCounter = 0;
                }
            }

            if (sprite.flashTimer > 0) {
                sprite.flashTimer--;
            }
        }
    }
}

void RenderSystem::render() {
    game_.window.clear();

    const recti& b = game_.worldBounds;

    auto renderLayer = [&](RenderLayer layer) {
        for (const auto& sprite : game_.sprites.values()) {
            if (sprite.renderLayer == layer) {
                vec2i p = sprite.position;
                if (game_.onScreen(p) && b.contains(p)) {
                    vec2i sc = game_.screenCoord(p);
                    bool flash = sprite.flashTimer > 0;
                    game_.window.set(sc.x, sc.y, sprite.frames[sprite.frame],
                                     flash ? TB_WHITE : sprite.fg, sprite.bg);
                }
            }
        }
    };

    renderGround();

    // Ground sprites
    for (auto layer : {RenderLayer::Ground, RenderLayer::GroundCover}) {
        renderLayer(layer);
    }

    renderOcean();

    // Remaining sprites
    for (auto layer :
         {RenderLayer::Particles, RenderLayer::MobBelow, RenderLayer::Mob, RenderLayer::MobAbove}) {
        renderLayer(layer);
    }
}

void RenderSystem::renderGround() {
    const vec2i ws{game_.window.width(), game_.window.height()};
    const recti& b = game_.worldBounds;

    for (int y = 0; y < ws.y; y++) {
        for (int x = 0; x < ws.x; x++) {
            vec2i p = game_.worldCoord({x, y});
            if (game_.onScreen(p) && b.contains(p)) {
                game_.window.set(x, y, game_.groundTile(p), TB_WHITE, TB_BLACK);
            }
        }
    }
}

void RenderSystem::renderOcean() {
    const vec2i ws{game_.window.width(), game_.window.height()};
    const recti& b = game_.worldBounds;

    // Maps a coordinate to a random int
    auto hash = [&](vec2i p) -> size_t {
        auto mod = [](int x, int m) {
            if (x >= 0)
                return x % m;
            else
                return m - 1 - (-x % m);
        };
        int px = mod(p.x + tick_ / 32, randomArray2D_.width());
        int py = mod(p.y - tick_ / 256, randomArray2D_.height());
        return randomArray2D_(px, py);
    };

    // Main mass
    for (int y = 0; y < ws.y; y++) {
        for (int x = 0; x < ws.x; x++) {
            vec2i p = game_.worldCoord({x, y});
            if (game_.onScreen(p) && !b.contains(p)) {
                char c = hash(p) % 16 == 0 ? '~' : ' ';
                game_.window.set(x, y, c, TB_WHITE, TB_BLUE);
            }
        }
    }

    // Edges
    for (bool fg : {false, true}) {
        int tick = fg ? tick_ + 50 : tick_;

        for (int yEdge : {-1, 1}) {
            int y = (yEdge == -1) ? (b.top - b.height + 1) : b.top;
            for (int x = b.left; x < b.left + b.width; x++) {
                double mag = cos(tick * 0.03);
                int depth = 1 + (int)(2 + 2 * mag * sin(tick * 0.01 + x * 0.1));
                for (int dy = 0; dy < depth; dy++) {
                    vec2i p{x, y - dy * yEdge};
                    vec2i sc = game_.screenCoord(p);
                    if (game_.onScreen(p)) {
                        if (fg) {
                            char c = (dy == depth - 1) ? '~' : hash(p) % 4 == 0 ? '~' : ' ';
                            game_.window.set(sc.x, sc.y, c, TB_WHITE, TB_BLUE);
                        } else {
                            game_.window.set(sc.x, sc.y, '~', TB_BLUE, TB_BLACK);
                        }
                    }
                }
            }
        }

        for (int xEdge : {-1, 1}) {
            int x = (xEdge == -1) ? b.left : (b.left + b.width - 1);
            for (int y = b.top - b.height + 1; y <= b.top; y++) {
                double mag = cos(tick * 0.03);
                int depth = 1 + (int)(2 + 2 * mag * sin(tick * 0.01 + y * 0.1));
                for (int dx = 0; dx < depth; dx++) {
                    vec2i p{x - dx * xEdge, y};
                    vec2i sc = game_.screenCoord(p);
                    if (game_.onScreen(p)) {
                        if (fg) {
                            char c = (dx == depth - 1) ? '~' : hash(p) % 4 == 0 ? '~' : ' ';
                            game_.window.set(sc.x, sc.y, c, TB_WHITE, TB_BLUE);
                        } else {
                            game_.window.set(sc.x, sc.y, '~', TB_BLUE, TB_BLACK);
                        }
                    }
                }
            }
        }
    }
}
