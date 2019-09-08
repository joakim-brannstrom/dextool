#include "window.h"
#include "termbox.h"

#include <iostream>
#include <thread>

#ifdef NO_WINDOW // Null window (for testing)

#include <iostream>
#include <thread>

Window::Window() {}
Window::~Window() {}

int32_t Window::width() const { return 256; }
int32_t Window::height() const { return 128; }

bool Window::handleEvents() {
    events_.clear();
    static int i = 0;
    static const std::vector<WindowEvent> evs{WindowEvent::ArrowUp, WindowEvent::ArrowLeft,
                                              WindowEvent::ArrowDown, WindowEvent::ArrowRight};
    events_.push_back(evs[(i++) % 4]);
    return true;
}

void Window::render() {
    std::cout << "Window::render()\n";
    using namespace std::chrono_literals;
    const auto delayPerFrame = 15ms;
    if (delayPerFrame != 0ms) {
        std::this_thread::sleep_for(delayPerFrame);
    }
}

void Window::clear() {}

void Window::set(int x, int y, char c, uint16_t fg, uint16_t bg) {
    layoutEvents.push_back(Pos{x, y, c});
}

#else // Terminal

Window::Window() {
    int code = tb_init();
    if (code < 0) {
        std::cerr << "termbox init failed, code: %d\n";
        throw std::runtime_error("termbox failed");
    }

    tb_select_input_mode(TB_INPUT_ESC);
    tb_clear();
    tb_select_output_mode(TB_OUTPUT_NORMAL);
}

Window::~Window() { tb_shutdown(); }

bool Window::handleEvents() {
    events_.clear();

    struct tb_event ev;
    if (tb_peek_event(&ev, 10)) {
        switch (ev.type) {
        case TB_EVENT_KEY:
            switch (ev.key) {
            case TB_KEY_ESC:
                return false;
                break;
            case TB_KEY_ARROW_LEFT:
                events_.push_back(WindowEvent::ArrowLeft);
                break;
            case TB_KEY_ARROW_RIGHT:
                events_.push_back(WindowEvent::ArrowRight);
                break;
            case TB_KEY_ARROW_UP:
                events_.push_back(WindowEvent::ArrowUp);
                break;
            case TB_KEY_ARROW_DOWN:
                events_.push_back(WindowEvent::ArrowDown);
                break;
            }
            break;
        case TB_EVENT_RESIZE:
            // draw_all();
            break;
        }
    }

    return true;
}

void Window::render() {
    using namespace std::chrono_literals;
    const auto delayPerFrame = 15ms;

    tb_present();

    if (delayPerFrame != 0ms) {
        std::this_thread::sleep_for(delayPerFrame);
    }
}

void Window::clear() { tb_clear(); }

void Window::set(int x, int y, char c, uint16_t fg, uint16_t bg) {
    tb_change_cell(x, y, c, fg, bg);
}

int32_t Window::width() const { return tb_width(); }

int32_t Window::height() const { return tb_height(); }

#endif
