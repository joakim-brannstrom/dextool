#ifndef window_hpp
#define window_hpp

#include "termbox.h"
#include "util.h"

enum class WindowEvent {
    Unknown,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
};

inline std::string to_string(WindowEvent ev) {
    switch (ev) {
    case WindowEvent::Unknown:
    default:
        return "Unknown";

    case WindowEvent::ArrowUp:
        return "ArrowUp";
    case WindowEvent::ArrowDown:
        return "ArrowDown";
    case WindowEvent::ArrowLeft:
        return "ArrowLeft";
    case WindowEvent::ArrowRight:
        return "ArrowRight";
    }
}

struct Pos {
    int x{0};
    int y{0};
    char c{0};
};

class Window {
public:
    Window();
    ~Window();
    int32_t width() const;
    int32_t height() const;

    bool handleEvents(); // returns false on quit
    const std::vector<WindowEvent>& events() const { return events_; }
    void render();

    void clear();
    void set(int x, int y, char c, uint16_t fg, uint16_t bg);

    /// Testing interface where events are synthetically injected.
    void inject(WindowEvent ev) { events_.push_back(ev); }

    /// The position updates that has been generated. Used for testing purpose.
    std::vector<Pos> layoutEvents;

private:
    std::vector<WindowEvent> events_;
};

#endif
