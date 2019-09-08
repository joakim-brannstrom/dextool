#ifndef util_hpp
#define util_hpp

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <random>
#include <sstream>
#include <string>
#include <unordered_map>

// reference to an entity or component
struct ident {
public:
    constexpr explicit ident(uint32_t i) : i_{i} {}

    operator bool() { return i_ != 0; }

    bool operator==(const ident& other) const { return i_ == other.i_; }
    bool operator!=(const ident& other) const { return !(*this == other); }

    ident operator++(int) {
        uint32_t old = i_++;
        return ident{old};
    }

protected:
    uint32_t i_;
    friend std::hash<ident>;
    friend std::string to_string(const ident& id);
};

constexpr ident invalid_id{0};

inline std::string to_string(const ident& id) { return std::string("#") + std::to_string(id.i_); }

namespace std {
// for std::unordered_map<id, ...>
template <> struct hash<::ident> {
    size_t operator()(::ident i) const noexcept { return hash<uint32_t>()(i.i_); }
};
}; // namespace std

// packed-array map for components
template <typename T> class container {
public:
    using key_type = ident;
    using value_type = T;

    container() {
        const int initialElems = 4096;
        values_.reserve(initialElems);
    }

    value_type& add(value_type value = {}) {
        key_type key = nextKey_++;
        size_t index = values_.size();
        values_.push_back(std::move(value));
        values_.back().id = key;
        indices_[key] = index;
        return values_.back();
    }

    value_type& operator[](key_type key) {
        auto it = indices_.find(key);
        if (it == indices_.end())
            return nullElement_;
        else
            return values_[it->second];
    }

    void remove(key_type key) {
        auto it = indices_.find(key);
        assert(it != indices_.end());
        size_t index = it->second;
        auto& back = values_.back();
        indices_[back.id] = index;
        values_[index] = std::move(back);
        values_.pop_back();
        indices_.erase(it);
    }

    std::vector<T>& values() { return values_; }

protected:
    std::unordered_map<key_type, size_t> indices_;
    std::vector<T> values_;
    key_type nextKey_{1};
    T nullElement_{};

    template <typename U> friend std::string to_string(const container<U>& container);
};

template <typename T> std::string to_string(const container<T>& container) {
    std::ostringstream oss;
    oss << "[";
    for (const auto& v : container.values_) {
        oss << "(" << container.indices_.at(v.id) << ":" << to_string(v) << ") ";
    }
    oss << "]";
    return oss.str();
}

// a buffered, safer version of container
// preserves references to elements until sync() is called
template <typename T> class buffered_container : public container<T> {
    using super = container<T>;

public:
    using key_type = typename super::key_type;
    using value_type = typename super::value_type;

    buffered_container() {
        add_.reserve(max_size());
        remove_.reserve(max_size());

        remove_.clear();
        add_.clear();
    }

    constexpr int max_size() const { return 1024; }

    int size() const { return (int)add_.size(); }

    value_type& add(value_type value = {}) {
        if (add_.size() >= max_size()) {
            throw std::runtime_error("Exceeded buffer capacity");
        }

        buffered_ = true;
        key_type key = super::nextKey_++;
        add_.push_back(std::move(value));
        add_.back().id = key;
        return add_.back();
    }

    void remove(key_type key) {
        bool inContainer = super::indices_.find(key) != super::indices_.end();
        bool inBuffer = std::find_if(add_.begin(), add_.end(),
                                     [key](T& value) { return value.id == key; }) != add_.end();
        assert(inContainer || inBuffer);

        buffered_ = true;
        remove_.push_back(key);
    }

    value_type& operator[](key_type key) {
        if (buffered_) {
            auto remove_it = std::find(remove_.begin(), remove_.end(), key);
            if (remove_it != remove_.end())
                return super::nullElement_;

            if (super::indices_.count(key) == 0) {
                auto add_it = std::find_if(add_.begin(), add_.end(),
                                           [key](const T& t) { return t.id == key; });
                if (add_it != add_.end())
                    return *add_it;
            }
        }
        return super::operator[](key);
    }

    void sync() {
        for (auto& value : add_) {
            size_t index = super::values_.size();
            super::values_.push_back(std::move(value));
            super::indices_[value.id] = index;
        }

        for (auto& id : remove_) {
            super::remove(id);
        }

        add_.clear();
        remove_.clear();
        buffered_ = false;
    }

protected:
    bool buffered_ = false;
    std::vector<T> add_{};
    std::vector<ident> remove_{};
};

// Mathematics

template <typename T> struct vec2 {
    T x, y;

    template <typename U> explicit operator vec2<U>() {
        return vec2<U>{static_cast<U>(x), static_cast<U>(y)};
    }
};

using vec2i = vec2<int32_t>;
using vec2d = vec2<double>;

template <typename T> inline vec2<T> operator-(vec2<T> a) { return {-a.x, -a.y}; }
template <typename T> inline vec2<T> operator+(vec2<T> a, vec2<T> b) {
    return {a.x + b.x, a.y + b.y};
}
template <typename T> inline vec2<T> operator-(vec2<T> a, vec2<T> b) {
    return {a.x - b.x, a.y - b.y};
}
template <typename T> inline vec2<T> operator*(vec2<T> a, T m) { return {a.x * m, a.y * m}; }
template <typename T> inline vec2<T> operator/(vec2<T> a, T m) { return {a.x / m, a.y / m}; }
template <typename T> inline vec2<T>& operator+=(vec2<T>& a, vec2<T> b) { return a = a + b; }
template <typename T> inline vec2<T>& operator-=(vec2<T>& a, vec2<T> b) { return a = a + b; }
template <typename T> inline vec2<T>& operator*=(vec2<T>& a, T b) { return a = a * b; }
template <typename T> inline vec2<T>& operator/=(vec2<T>& a, T b) { return a = a / b; }
template <typename T> inline bool operator==(vec2<T> a, vec2<T> b) {
    return a.x == b.x && a.y == b.y;
}
template <typename T> inline bool operator!=(vec2<T> a, vec2<T> b) {
    return a.x != b.x || a.y != b.y;
}

struct recti {
    int32_t left, top, width, height;
    inline bool contains(const vec2i& p) const {
        return p.x >= left && p.x < left + width && p.y <= top && p.y > top - height;
    }
};

template <typename T> inline std::string to_string(const vec2<T>& vec) {
    using namespace std::string_literals;
    return "{"s + std::to_string(vec.x) + ", "s + std::to_string(vec.y) + "}"s;
}

template <typename T> T sign(T t) {
    if (t > 0)
        return 1;
    else if (t < 0)
        return -1;
    else
        return 0;
}

// Helpful containers

template <typename T> struct Array2D {
public:
    Array2D(int width, int height, T nullVal = {})
        : nullVal_(nullVal), width_(width), height_(height), data_(width * height, nullVal) {}

    void resize(int newWidth, int newHeight) {
        width_ = newWidth;
        height_ = newHeight;
        data_.resize(width_ * height_, nullVal_);
        data_.shrink_to_fit();
    }

    int width() const { return width_; }

    int height() const { return height_; }

    void fill(T val) { std::fill(data_.begin(), data_.end(), val); }

    T& operator()(int x, int y) { return inBounds(x, y) ? data_[x + y * width_] : nullVal_; }

    T& operator()(vec2i p) { return (*this)(p.x, p.y); }

    const T& operator()(int x, int y) const {
        return inBounds(x, y) ? data_[x + y * width_] : nullVal_;
    }

    const T& operator()(vec2i p) const { return (*this)(p.x, p.y); }

    bool inBounds(int x, int y) const { return x >= 0 && x < width_ && y >= 0 && y < height_; }

    bool inBounds(vec2i p) const { return p.x >= 0 && p.x < width_ && p.y >= 0 && p.y < height_; }

    // Raw data access
    std::vector<T>& data() { return data_; }

private:
    T nullVal_{};
    int width_ = 0;
    int height_ = 0;
    std::vector<T> data_;
};

// Random number generation

inline std::default_random_engine& engine() {
    static std::default_random_engine engine_;
    return engine_;
}

inline int32_t randInt(int32_t from, int32_t to) {
    return std::uniform_int_distribution<>(from, to)(engine());
}

inline double random(double from = 0.0, double to = 1.0) {
    return std::uniform_real_distribution<>(from, to)(engine());
}

inline vec2i randVec2i(vec2i from, vec2i to) {
    return {randInt(from.x, to.x), randInt(from.y, to.y)};
}

template <typename T> T choose(const std::vector<T>& values) {
    return values[randInt(0, values.size() - 1)];
}

template <typename T> T choose(std::initializer_list<T> values) {
    return *(values.begin() + randInt(0, (int)values.size() - 1));
}

#endif
