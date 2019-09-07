//
//  physicssystem.h
//  minirl
//
//  Created by Benjamin Porter on 2/1/18.
//  Copyright © 2018 Benjamin Porter. All rights reserved.
//

#ifndef physicssystem_hpp
#define physicssystem_hpp

#include "physics.h"
#include "system.h"
#include "util.h"

#include <cstdint>
#include <string>

class Game;
class PhysicsSystem : public System {
public:
    PhysicsSystem(Game& game) : game_(game) {}
    void update() final;
    void handleEvent(const EvAny&) final {}

protected:
    Game& game_;
};
#endif /* physicssystem_hpp */
