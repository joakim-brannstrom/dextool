#include "mobsystem.h"

#include "game.h"
#include "rendersystem.h"

#include <string>
using namespace std::string_literals;

MobInfo MI(MobCategory category, std::string name, int32_t health, int32_t speed) {
    MobInfo mi;
    mi.category = category;
    mi.name = name;
    mi.health = health;
    mi.speed = speed;
    return mi;
}

MobInfo MI(MobCategory category, std::string name, int32_t health, int32_t speed,
           int32_t strength) {
    MobInfo mi;
    mi.category = category;
    mi.name = name;
    mi.health = health;
    mi.speed = speed;
    mi.attacks = true;
    mi.strength = strength;
    return mi;
}

const std::unordered_map<MobType, MobInfo> MobDatabase{
    {MobType::Unknown, MI(MobCategory::Unknown, "Unknown"s, 0, 1)},
    {MobType::Rabbit, MI(MobCategory::Rabbit, "Rabbit"s, 1, 7)},
    {MobType::RabbitWere, MI(MobCategory::Rabbit, "Were-Rabbit"s, 1, 6, 1)},
    {MobType::Snake, MI(MobCategory::Snake, "Snake"s, 1, 5)},
    {MobType::OrcWeak, MI(MobCategory::Orc, "Little Orc"s, 5, 3, 3)},
    {MobType::OrcStrong, MI(MobCategory::Orc, "Big Orc"s, 6, 2, 5)},
    {MobType::Player, MI(MobCategory::Player, "Player"s, 5, 6, 3)},
};

void MobSystem::update() {
    for (auto& mob : game_.mobs.values()) {
        if (mob.info->category == MobCategory::Player)
            continue;

        mob.tick += mob.info->speed;
        mob.tick = std::min(mob.tick, 2 * Mob::TicksPerAction - 1);
        if (mob.tick >= Mob::TicksPerAction) {
            auto& e = game_.entities[mob.entity];
            updateMob(e, mob);
            mob.tick -= Mob::TicksPerAction;
        }
    }
}

void MobSystem::handleEvent(const EvAny& any) {
    if (any.is<EvTryWalk>()) {
        const auto& ev = any.get<EvTryWalk>();
        auto& mob = game_.mobs[ev.mob];
        auto& info = *mob.info;

        // check position is clear
        bool blocked = false;
        for (auto& other : game_.mobs.values()) {
            if (other.id != mob.id && other.position == ev.to) {
                blocked = true;
                break;
            }
        }

        if (!game_.worldBounds.contains(ev.to)) {
            blocked = true;
        }

        if (!blocked) {
            mob.position = ev.to;

            // Mob overrides sprite position
            auto& sprite = game_.sprites[game_.entities[mob.entity].sprite];
            sprite.position = mob.position;

            // Additional pieces
            switch (info.category) {
            default:
                break;
            case MobCategory::Snake: {
                if (randInt(0, 3) < 3) {
                    game_.groundTile(mob.position) = '_';
                }

                game_.sprites[mob.extraSprite].position = mob.position + mob.dir;
                break;
            }
            case MobCategory::Orc: {
                if (randInt(0, 1) == 0) {
                    // smash ground
                    game_.groundTile(mob.position) = '_';
                }
                game_.sprites[mob.extraSprite].position = mob.position + vec2i{-1, 1};
                game_.sprites[mob.extraSprite2].position = mob.position + vec2i{1, 1};
                break;
            }
            }

            game_.queueEvent(EvWalked{mob.id, ev.from, mob.position});
        }
    } else if (any.is<EvWalked>()) {
        // ...
    } else if (any.is<EvAttack>()) {
        const auto& ev = any.get<EvAttack>();
        auto& mob = game_.mobs[ev.mob];
        auto& mobInfo = *mob.info;
        auto& targetMob = game_.mobs[ev.target];
        // auto& targetMobInfo = *targetMob.info;

        if (mob && targetMob) {
            targetMob.health -= mobInfo.strength;
            if (targetMob.health <= 0) {
                game_.queueEvent(EvKillMob{targetMob.id});
            } else {
                // Flash-hit
                const int flashDuration = 2;
                auto& e = game_.entities[targetMob.entity];
                game_.sprites[e.sprite].flashTimer = flashDuration;
                if (targetMob.extraSprite)
                    game_.sprites[targetMob.extraSprite].flashTimer = flashDuration;
                if (targetMob.extraSprite2)
                    game_.sprites[targetMob.extraSprite2].flashTimer = flashDuration;
            }
        }
    }
}

void MobSystem::updateMob(Entity& e, Mob& mob) {
    auto& info = *mob.info;
    auto& sprite = game_.sprites[e.sprite];
    vec2i pos = mob.position;

    const int margin = 6; // min distance from edge mobs prefer to be
    auto dirToNearestEdge = [&](vec2i pos) -> vec2i {
        const auto& b = game_.worldBounds;

        if (pos.y > b.top - margin)
            return {0, -1};
        else if (pos.y < b.top - b.height + margin)
            return {0, 1};
        else if (pos.x < b.left + margin)
            return {1, 0};
        else if (pos.x > b.left + b.width - margin)
            return {-1, 0};
        return {0, 0};
    };

    switch (info.category) {
    case MobCategory::Rabbit: {
        if (randInt(0, 500) == 0) {
            // Too many rabbits!
            // game_.queueEvent(EvSpawnMob { MobType::Rabbit, pos });
        } else {
            // Move randomly
            vec2i dir = dirToNearestEdge(pos);
            if (dir == vec2i{0, 0}) {
                dir = vec2i{randInt(-1, 1), randInt(-1, 1)};
            }
            game_.queueEvent(EvTryWalk{mob.id, pos, pos + dir});
        }
        break;
    }
    case MobCategory::Snake: {
        if (randInt(0, 6) == 0) {
            if (mob.dir.x != 0) {
                mob.dir = choose<vec2i>({{0, 1}, {0, -1}});
            } else {
                mob.dir = choose<vec2i>({{1, 0}, {-1, 0}});
            }

            vec2i dir = dirToNearestEdge(pos);
            if (dir != vec2i{0, 0})
                mob.dir = dir;
        } else {
            if (mob.dir.y == 1)
                sprite.frame = 0;
            else if (mob.dir.y == -1)
                sprite.frame = 1;
            else if (mob.dir.x == 1)
                sprite.frame = 2;
            else if (mob.dir.x == -1)
                sprite.frame = 3;

            game_.queueEvent(EvTryWalk{mob.id, pos, pos + mob.dir});
        }
        break;
    }
    case MobCategory::Orc: {
        if (randInt(0, 2) == 0) {
            game_.groundTile(pos) = choose({'_', '_'});
        }

        vec2i dir = dirToNearestEdge(pos);
        if (dir == vec2i{0, 0}) {
            if (randInt(0, 3) == 0) {
                // stay here
            } else {
                // move randomly
                int32_t move = choose({-1, 1});
                dir = choose({vec2i{move, 0}, vec2i{0, move}});
            }
        }

        if (dir != vec2i{0, 0}) {
            game_.queueEvent(EvTryWalk{mob.id, pos, pos + dir});
        }
        break;
    }
    default:
        break;
    }
}
