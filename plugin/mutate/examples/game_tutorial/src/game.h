#ifndef game_hpp
#define game_hpp

#include "entity.h"
#include "event.h"
#include "mob.h"
#include "mobsystem.h"
#include "physics.h"
#include "physicssystem.h"
#include "rendersystem.h"
#include "system.h"
#include "util.h"
#include "window.h"

#include <deque>
#include <memory>
#include <string>
#include <utility>

class Game {
public:
    Game(Window& window);
    void setup();
    void queueEvent(const EvAny& ev);
    bool update();
    void render();

    vec2i worldCoord(vec2i screenCoord) const; // Map screen point to world point
    vec2i screenCoord(vec2i worldCoord) const; // Map world point to screen point
    bool onScreen(vec2i worldCoord) const;

    char& groundTile(vec2i p) {
        vec2i q{p.x - worldBounds.left, worldBounds.top - p.y};
        return groundTiles_(q);
    }

public:
    Window& window;
    recti worldBounds{-64, 24, 128, 48};
    ident player{invalid_id};
    vec2i cameraPosition{0, 0};
    vec2i cameraTarget{0, 0};

    bool cameraShake = false;
    int cameraShakeTimer = 0;
    int cameraShakeStrength = 2;
    vec2i cameraShakeOffset{0, 0};
    int freezeTimer = 0;

    buffered_container<Entity> entities;
    buffered_container<Mob> mobs;
    buffered_container<Sprite> sprites;
    buffered_container<Physics> physics;

protected:
    int tick_ = 0;
    int subTick_ = 0;

    std::array<std::vector<EvAny>, 2> events_{};
    int eventsIndex_ = 0;

    std::deque<std::pair<std::string, int>> log_;

    Array2D<char> groundTiles_;

    std::deque<WindowEvent> windowEvents_;

    MobSystem mobSystem_;
    PhysicsSystem physicsSystem_;
    RenderSystem renderSystem_;
    std::vector<System*> systems_{
        &mobSystem_,
        &physicsSystem_,
        &renderSystem_,
    };

    void sync();
    void handleInput();
    void updatePlayer();
    void updateCamera();

    void log(const std::string message);

    // Factories
    Sprite& createSprite(std::string frames, bool animated, int frameRate, uint16_t fg, uint16_t bg,
                         vec2i position, RenderLayer layer);
    Mob& createMob(MobType type, vec2i position);
    void createBloodSplatter(vec2i position);
    void createBones(char c, vec2i position);
};

#endif
