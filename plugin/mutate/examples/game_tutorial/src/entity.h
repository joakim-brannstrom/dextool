#ifndef entity_hpp
#define entity_hpp

#include "util.h"

#include <array>

enum class ComponentType {
    Mob,
    Sprite,
    Physics,

    Count
};

class Component {
public:
    ident entity{invalid_id};
    ident id{invalid_id};

    operator bool() const { return id != invalid_id; }
};

// buffered_container<Entity>
class Entity {
public:
    ident id{invalid_id};

    operator bool() const { return id != invalid_id; }

    // hierarchy
    ident parent{invalid_id};
    std::vector<ident> children;

    void addChild(Entity& child) {
        child.parent = id;
        children.push_back(child.id);
    }

    // common
    int age = 0;
    int life = -1; // if >= 0 determines a finite life

    // components
    ident sprite{invalid_id};
    ident mob{invalid_id};
    ident physics{invalid_id};

    // private:
    //  static buffered_container<Entity>* container_ {nullptr};
};

#endif /* entity_hpp */
