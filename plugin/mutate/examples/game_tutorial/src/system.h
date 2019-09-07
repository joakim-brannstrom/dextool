#ifndef system_hpp
#define system_hpp

#include "event.h"
#include "util.h"

class System {
public:
    virtual void update() = 0;
    virtual void handleEvent(const EvAny& ev) {}
};

#endif
