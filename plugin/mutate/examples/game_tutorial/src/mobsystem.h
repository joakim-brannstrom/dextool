#ifndef mobsystem_hpp
#define mobsystem_hpp

#include "entity.h"
#include "mob.h"
#include "system.h"
#include "util.h"

extern const std::unordered_map<MobType, MobInfo> MobDatabase;

class Game;
class MobSystem : public System {
public:
    MobSystem(Game& game) : game_(game) {}
    void update() final;
    void handleEvent(const EvAny&) final;

protected:
    void updateMob(Entity& e, Mob& mob);

protected:
    Game& game_;
};

#endif /* mobsystem_hpp */
