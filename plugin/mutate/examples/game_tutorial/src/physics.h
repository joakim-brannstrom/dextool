//
//  physics.h
//  minirl
//
//  Created by Benjamin Porter on 2/1/18.
//  Copyright © 2018 Benjamin Porter. All rights reserved.
//

#ifndef physics_hpp
#define physics_hpp

#include "entity.h"
#include "util.h"

enum PhysicsType { Projectile, Static };

class Physics : public Component {
public:
    PhysicsType type{Static};
    vec2d position{0, 0};
    vec2d velocity{0, 0};
};

#endif /* physics_hpp */
