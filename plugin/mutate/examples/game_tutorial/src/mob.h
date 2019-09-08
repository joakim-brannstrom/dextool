//
//  mob.h
//  minirl
//
//  Created by Benjamin Porter on 1/1/18.
//  Copyright © 2018 Benjamin Porter. All rights reserved.
//

#ifndef mob_h
#define mob_h

#include "entity.h"
#include "util.h"

#include <cstdint>
#include <string>

enum class MobCategory { Unknown, Rabbit, Snake, Orc, Player };

enum class MobType { Unknown, Rabbit, RabbitWere, Snake, OrcWeak, OrcStrong, Player };

inline std::string to_string(MobType type) {
    using namespace std::string_literals;

    switch (type) {
    default:
    case MobType::Unknown:
        return "MobType::Unknown"s;
    case MobType::Rabbit:
        return "MobType::Rabbit"s;
    case MobType::RabbitWere:
        return "MobType::RabbitWere"s;
    case MobType::Snake:
        return "MobType::Snake"s;
    case MobType::OrcWeak:
        return "MobType::OrcWeak"s;
    case MobType::OrcStrong:
        return "MobType::OrcStrong"s;
    case MobType::Player:
        return "MobType::Player"s;
    }
}

struct MobInfo {
    MobCategory category{MobCategory::Unknown};
    std::string name{};
    int32_t health = 0;
    bool attacks = false;
    int32_t strength = 0;
    int32_t speed = 4; // 1 = slowest, 10 = fastest
};

class Mob : public Component {
public:
    static const int TicksPerAction = 15;

    Mob() = default;
    Mob(const MobInfo* info) : info{info} {}
    const MobInfo* info{&sMobInfo};

    vec2i position{0, 0};
    int32_t health{0};
    int32_t tick{0};

    // type-specific data
    vec2i dir{0, 1};

    // additional components (references to children)
    ident extraSprite{invalid_id};
    ident extraSprite2{invalid_id};

private:
    static MobInfo sMobInfo;
};

#endif /* mob_h */
