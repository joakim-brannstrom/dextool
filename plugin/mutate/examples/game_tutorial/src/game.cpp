#include "game.h"

#include "event.h"

#include <iostream>

Game::Game(Window& window)
    : window(window), mobSystem_(*this), physicsSystem_(*this), renderSystem_(*this),
      groundTiles_(worldBounds.width, worldBounds.height, '.') {}

void Game::setup() {
    const auto& b = worldBounds;

    // Create player
    auto& playerMob = createMob(MobType::Player, {0, 0});
    player = playerMob.entity;
    cameraTarget = playerMob.position;
    cameraPosition = playerMob.position;

    // Setup terrain
    groundTiles_.fill('.');
    for (int x = b.left; x < b.left + b.width; x++) {
        for (int y = b.top - b.height + 1; y <= b.top; y++) {
            if (randInt(0, 6) == 0) {
                groundTile({x, y}) = choose({',', '_', ' '});
            }
        }
    }

    // Populate world with mobs
    int numMobs = (int)(0.5 * sqrt(b.width * b.height));
    for (int i = 0; i < numMobs; i++) {
        MobType type = choose({MobType::Rabbit, MobType::OrcStrong, MobType::Snake});
        vec2i pos{randInt(b.left, b.left + b.width - 1), randInt(b.top - b.height + 1, b.top)};
        createMob(type, pos);

        if (i % 32 == 0)
            sync();
    }

    // Mob-less sprites
    for (int i = 0; i < numMobs / 2; i++) {
        vec2i pos{randInt(b.left, b.left + b.width - 1), randInt(b.top - b.height + 1, b.top)};
        if (randInt(0, 2) != 0) {
            createSprite("vV", true, 6, TB_MAGENTA, TB_BLACK, pos, RenderLayer::GroundCover);
        } else if (randInt(0, 1) == 0) {
            createSprite("|/-\\", true, 2, TB_YELLOW, TB_BLACK, pos, RenderLayer::GroundCover);
        } else {
            createSprite("Xx", true, 1, TB_BLUE, TB_BLACK, pos, RenderLayer::GroundCover);
        }

        if (i % 32 == 0)
            sync();
    }

    sync();
}

bool Game::update() {
    handleInput();
    updateCamera(); // NB: Outside of world update

    // Use this to slow down the world update
    const int subTicksPerTick = 2;
    if (--subTick_ <= 0) {
        subTick_ = subTicksPerTick;

        if (freezeTimer > 0)
            freezeTimer--;
        bool updateWorld = (freezeTimer == 0);

        if (updateWorld) {
            updatePlayer();

            for (auto* sys : systems_) {
                sys->update();
            }

            for (auto& e : entities.values()) {
                e.age++;
                if (e.life > 0 && e.age >= e.life) {
                    queueEvent(EvRemove{e.id});
                }
            }

            // Dirt system
            for (auto& c : groundTiles_.data()) {
                // Roughen flat ground
                if (c == '_' && randInt(0, 60) == 0)
                    c = '.';
            }
        }

        // Events
        auto& events = events_[eventsIndex_];
        eventsIndex_ = 1 - eventsIndex_; // toggle buffer
        std::vector<ident> remove;

        for (const EvAny& any : events) {
            const bool logEvents = false;
            if (logEvents) {
                log(to_string(any));
            }

            if (any.is<EvRemove>()) {
                const auto& ev = any.get<EvRemove>();
                remove.push_back({ev.entity});
            } else if (any.is<EvKillMob>()) {
                const auto& ev = any.get<EvKillMob>();
                Mob& mob = mobs[ev.who];
                auto& e = entities[mob.entity];
                auto& sprite = sprites[e.sprite];
                queueEvent(EvRemove{mob.entity});

                if (onScreen(mob.position)) {
                    cameraShake = true;
                    cameraShakeTimer = 0;
                    cameraShakeStrength = 2;
                    freezeTimer = 1;
                }

                createBloodSplatter(mob.position);
                createBones(sprite.frames[sprite.frame], mob.position);
            } else if (any.is<EvSpawnMob>()) {
                const auto& ev = any.get<EvSpawnMob>();
                createMob(ev.type, ev.position);
            } else if (any.is<EvTryWalk>()) {
                // const auto& ev = any.get<EvTryWalk>();
                // ...
            } else if (any.is<EvWalked>()) {
                const auto& ev = any.get<EvWalked>();
                if (ev.mob == entities[player].mob) {
                    // Camera tracks player
                    const vec2i margin{8, 4};
                    vec2i newScreenPos = screenCoord(ev.to);
                    if ((window.width() - newScreenPos.x) < margin.x) {
                        cameraTarget.x += margin.x;
                    } else if (newScreenPos.x < margin.x) {
                        cameraTarget.x -= margin.x;
                    } else if ((window.height() - newScreenPos.y) < margin.y) {
                        cameraTarget.y -= margin.y;
                    } else if (newScreenPos.y < margin.y) {
                        cameraTarget.y += margin.y;
                    }
                }
            } else if (any.is<EvAttack>()) {
                const auto& ev = any.get<EvAttack>();
                if (onScreen(mobs[ev.target].position)) {
                    cameraShake = true;
                    cameraShakeTimer = 0;
                    cameraShakeStrength = 1;
                }
            }

            for (auto* sys : systems_) {
                sys->handleEvent(any);
            }
        }
        events.clear();

        auto it = remove.begin();
        while (it != remove.end()) {
            const ident& id = *it;
            Entity& e = entities[id];
            if (!e) {
                ++it;
                continue; // Already removed
            }

            using cid = std::pair<ComponentType, ident>;
            auto comps = {cid{ComponentType::Mob, e.mob}, cid{ComponentType::Sprite, e.sprite},
                          cid{ComponentType::Physics, e.physics}};

            for (auto pair : comps) {
                ident component = pair.second;
                if (component) {
                    ComponentType type = pair.first;

                    switch (type) {
                    default:
                        break;
                    case ComponentType::Mob: {
                        mobs.remove(component);
                        break;
                    }
                    case ComponentType::Sprite: {
                        sprites.remove(component);
                        break;
                    }
                    case ComponentType::Physics: {
                        physics.remove(component);
                        break;
                    }
                    }
                }
            }

            for (const auto& ch : e.children) {
                queueEvent(EvRemove{ch});
            }
            e.children.clear();

            entities.remove(id);
            it++;
        }

        sync();
        tick_++;

        while (!log_.empty()) {
            const auto& pair = log_.front();
            if (tick_ > pair.second + 20) {
                log_.pop_front();
            } else
                break;
        }
    }

    return true;
}

void Game::render() {
    window.clear();
    renderSystem_.render();

    const bool showLog = true;
    if (showLog) {
        const int maxMessages = 10;
        int y = 0;
        for (const auto& message : log_) {
            auto tick = std::to_string(message.second);
            for (int x = 0; x < (int)tick.size(); x++) {
                window.set(x, y, tick[x], TB_WHITE, TB_BLUE);
            }
            for (int x = (int)tick.size(); x < 6; x++) {
                window.set(x, y, ' ', TB_WHITE, TB_BLUE);
            }
            for (int x = 0; x < (int)message.first.size(); x++) {
                window.set(6 + x, y, message.first[x], TB_WHITE, TB_BLUE);
            }
            y++;
            if (y > maxMessages)
                break;
        }
    }

    std::string header = "Some Roguelike Thing";
    for (int x = 0; x < (int)header.size(); x++) {
        window.set(x, 0, header[x], TB_WHITE, TB_BLUE);
    }
    for (int x = (int)header.size(); x < window.width(); x++) {
        window.set(x, 0, ' ', TB_WHITE, TB_BLUE);
    }

#ifdef __EMSCRIPTEN__
    std::string footer = "Arrows: Move. Code: https://github.com/eigenbom/game-example.";
#else
    std::string footer = "ESC: Exit. Arrows: Move.";
#endif

    for (int x = 0; x < (int)footer.size(); x++) {
        window.set(x, window.height() - 1, footer[x], TB_WHITE, TB_BLUE);
    }
    for (int x = (int)footer.size(); x < window.width(); x++) {
        window.set(x, 0, ' ', TB_WHITE, TB_BLUE);
    }
}

vec2i Game::worldCoord(vec2i screenCoord) const {
    const vec2i ws{window.width(), window.height()};
    vec2i q = screenCoord - ws / 2;
    vec2i camFinal = cameraPosition + (cameraShake ? cameraShakeOffset : vec2i{0, 0});
    return {q.x + camFinal.x, -(q.y - camFinal.y)};
}

vec2i Game::screenCoord(vec2i worldCoord) const {
    const vec2i ws{window.width(), window.height()};
    vec2i wc = worldCoord;
    vec2i camFinal = cameraPosition + (cameraShake ? cameraShakeOffset : vec2i{0, 0});
    return vec2i{wc.x - camFinal.x, camFinal.y - wc.y} + ws / 2;
}

bool Game::onScreen(vec2i worldCoord) const {
    vec2i sc = screenCoord(worldCoord);
    recti windowBounds{0, window.height() - 1, window.width(), window.height()};
    return windowBounds.contains(sc);
}

void Game::queueEvent(const EvAny& ev) { events_[eventsIndex_].push_back(ev); }

void Game::sync() {
    entities.sync();
    mobs.sync();
    sprites.sync();
    physics.sync();
}

void Game::log(const std::string message) { log_.push_back({message, tick_}); }

Sprite& Game::createSprite(std::string frames, bool animated, int frameRate, uint16_t fg,
                           uint16_t bg, vec2i position, RenderLayer renderLayer) {
    auto& e = entities.add();

    auto& spr = sprites.add(Sprite{frames, animated, frameRate, fg, bg, position, renderLayer});
    spr.entity = e.id;
    e.sprite = spr.id;
    return spr;
}

Mob& Game::createMob(MobType type, vec2i position) {
    auto& e = entities.add();

    auto& info = MobDatabase.at(type);
    Mob& mob = mobs.add(Mob{&info});
    e.mob = mob.id;
    mob.entity = e.id;

    mob.health = info.health;
    mob.position = position;

    const char* frames = "?!";
    int frameRate = 1;
    auto fg = TB_WHITE;
    auto bg = TB_BLACK;
    switch (mob.info->category) {
    case MobCategory::Rabbit:
        frames = "r";
        frameRate = 1;
        fg = TB_YELLOW;
        break;
    case MobCategory::Snake:
        frames = "i!~~";
        frameRate = 0;
        fg = TB_GREEN;
        break;
    case MobCategory::Orc:
        frames = "oO";
        frameRate = 3;
        fg = TB_GREEN;
        bg = TB_BLACK;
        break;
    case MobCategory::Player:
        frames = "@";
        break;
    default:
        frames = "?!";
        break;
    }
    auto& spr =
        sprites.add(Sprite(frames, frameRate > 0, frameRate, fg, bg, position, RenderLayer::Mob));
    e.sprite = spr.id;
    spr.entity = e.id;

    switch (mob.info->category) {
    case MobCategory::Snake: {
        auto spr = createSprite("oo", false, 0, TB_GREEN, TB_BLACK, mob.position + mob.dir,
                                RenderLayer::Mob);
        auto& child = entities[spr.entity];
        e.addChild(child);

        mob.extraSprite = spr.id;
        break;
    }
    case MobCategory::Orc: {
        auto& spr1 = createSprite("\\|", true, 6, TB_GREEN, TB_BLACK, mob.position + vec2i{-1, 1},
                                  RenderLayer::MobBelow);
        auto& child1 = entities[spr1.entity];
        e.addChild(child1);
        mob.extraSprite = spr1.id;

        auto& spr2 = createSprite("/|", true, 6, TB_GREEN, TB_BLACK, mob.position + vec2i{1, 1},
                                  RenderLayer::MobBelow);
        auto& child2 = entities[spr2.entity];
        e.addChild(child2);
        mob.extraSprite2 = spr2.id;
        break;
    }
    default:
        break;
    }

    return mob;
}

void Game::createBloodSplatter(vec2i position) {
    if (sprites.size() >= sprites.max_size() / 2)
        return;

    const int radius = 3;
    const int sqradius = radius * radius;
    for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
            if ((dx * dx + dy * dy) <= sqradius) {
                if (randInt(0, 4) != 0) {
                    auto& spr = createSprite(".", false, 0, TB_RED, TB_BLACK,
                                             position + vec2i{dx, dy}, RenderLayer::Ground);
                    auto& e = entities[spr.entity];
                    e.life = randInt(200, 300);
                }
            }
        }
    }

    int numBloodParticles = randInt(10, 40);
    for (int i = 0; i < numBloodParticles; i++) {
        auto& spr = createSprite("o", false, 0, TB_RED, TB_BLACK, position, RenderLayer::Particles);
        auto& e = entities[spr.entity];
        e.life = randInt(6, 12);

        double vel = random(0.4, 0.6);

        Physics& ph = physics.add();
        ph.type = PhysicsType::Projectile;
        ph.position = (vec2d)position;
        double th = random(-M_PI, M_PI);
        ph.velocity.x = vel * cos(th);
        ph.velocity.y = vel * sin(th);

        e.physics = ph.id;
        ph.entity = e.id;
    }
}

void Game::createBones(char c, vec2i position) {
    auto& spr =
        createSprite(std::string(1, c), false, 0, TB_RED, TB_BLACK, position, RenderLayer::Ground);
    auto& e = entities[spr.entity];
    e.life = randInt(100, 110);
}

void Game::handleInput() {
    for (auto ev : window.events()) {
        bool isPlayerMove = [ev]() {
            switch (ev) {
            case WindowEvent::ArrowUp:
            case WindowEvent::ArrowDown:
            case WindowEvent::ArrowLeft:
            case WindowEvent::ArrowRight:
                return true;
            default:
                return false;
            }
        }();

        if (!isPlayerMove || windowEvents_.size() < 1) {
            // log(to_string(ev));
            windowEvents_.push_back(ev);
        }
    }
}

void Game::updatePlayer() {
    auto& entity = entities[player];
    auto& mob = mobs[entity.mob];

    mob.tick += mob.info->speed;
    mob.tick = std::min(mob.tick, 2 * Mob::TicksPerAction - 1);

    // Map input to player commands
    vec2i movePlayer{0, 0};

    while (!windowEvents_.empty()) {
        const auto& ev = windowEvents_.front();
        switch (ev) {
        default:
            break;
        case WindowEvent::ArrowUp:
            movePlayer = vec2i{0, 1};
            break;
        case WindowEvent::ArrowDown:
            movePlayer = vec2i{0, -1};
            break;
        case WindowEvent::ArrowLeft:
            movePlayer = vec2i{-1, 0};
            break;
        case WindowEvent::ArrowRight:
            movePlayer = vec2i{1, 0};
            break;
        }

        // A move requires a full action
        if (movePlayer != vec2i{0, 0}) {
            if (mob.tick >= Mob::TicksPerAction) {
                windowEvents_.pop_front();
                mob.tick -= Mob::TicksPerAction;
                break;
            } else {
                // Can't move yet
                return;
            }
        }
    }

    if (movePlayer != vec2i{0, 0}) {
        vec2i oldPos = mob.position;
        vec2i newPos = oldPos + movePlayer;

        ident target = invalid_id;
        for (auto& other : mobs.values()) {
            if (other.id != mob.id && other.position == newPos) {
                target = other.id;
                break;
            }
        }

        if (target) {
            queueEvent(EvAttack{mob.id, target});
        } else {
            queueEvent(EvTryWalk{mob.id, oldPos, newPos});
        }
    }
}

void Game::updateCamera() {
    if (cameraShake) {
        cameraShakeTimer++;
        if (cameraShakeStrength == 1)
            cameraShakeTimer++;

        if (cameraShakeTimer > 7) {
            cameraShake = false;
            cameraShakeOffset = vec2i{0, 0};
            cameraShakeTimer = 0;
        } else if (cameraShakeTimer % 2 == 0) {
            if (cameraShakeStrength == 1) {
                if (randInt(0, 1) == 0) {
                    cameraShakeOffset = vec2i{randInt(-1, 1), 0};
                } else {
                    cameraShakeOffset = vec2i{0, randInt(-1, 1)};
                }
            } else {
                cameraShakeOffset = vec2i{randInt(-1, 1), randInt(-1, 1)};
            }
        }
    }

    if (cameraPosition != cameraTarget) {
        static int cameraTick_ = 0;
        if (cameraTick_++ >= 1) {
            cameraTick_ = 0;
            vec2i dc = cameraTarget - cameraPosition;
            int dx = sign(dc.x);
            int dy = sign(dc.y);
            cameraPosition += vec2i{dx, dy};
        }
    }
}
