#include "physicssystem.h"

#include "game.h"

void PhysicsSystem::update() {
    for (auto& ph : game_.physics.values()) {
        if (ph.type == PhysicsType::Projectile) {
            ph.position += ph.velocity;
            ph.velocity *= 0.95;
            // TODO: detect collisions
        }

        // Update position of sprite
        auto& e = game_.entities[ph.entity];
        if (e.sprite) {
            auto& sprite = game_.sprites[e.sprite];
            sprite.position = (vec2i)ph.position;
        }
    }
}
