// A c++11 variant class
// source: https://gist.github.com/S6066/f726a37b2b703efea7ee27103e5bec89

#ifndef variant_h
#define variant_h

#include <cassert>
#include <type_traits>
#include <utility>

template <typename...> struct IsOneOf { static constexpr bool value = false; };

template <typename T, typename S, typename... Ts> struct IsOneOf<T, S, Ts...> {
    static constexpr bool value = std::is_same<T, S>::value || IsOneOf<T, Ts...>::value;
};

#include <type_traits>

template <typename...> struct IndexOf;

// Found
template <class T, class... Rest>
struct IndexOf<T, T, Rest...> : std::integral_constant<std::size_t, 0u> {};

// Still searching
template <class T, class Other, class... Rest>
struct IndexOf<T, Other, Rest...>
    : std::integral_constant<std::size_t, 1 + IndexOf<T, Rest...>::value> {};

namespace Detail {

template <class... Ts> struct VariantHelper;

template <class Union, class T, class... Ts> struct VariantHelper<Union, T, Ts...> {
    inline static void destroy(std::size_t index, Union* data);
    inline static void move(std::size_t index, Union* oldValue, Union* newValue);
    inline static void copy(std::size_t index, const Union* oldValue, Union* new_v);
};

template <class Union> struct VariantHelper<Union> {
    inline static void destroy(std::size_t index, Union* data) {}
    inline static void move(std::size_t index, Union* oldValue, Union* newValue) {}
    inline static void copy(std::size_t index, const Union* oldValue, Union* newValue) {}
};

} // namespace Detail

template <class... Ts> class Variant {
public:
    static_assert(sizeof...(Ts) > 1, "Variant must have at least 2 different types");

    Variant() = default;

    template <class T, class... Args,
              class = typename std::enable_if<IsOneOf<T, Ts...>::value>::type>
    Variant(const T& t) {
        new (&m_data) T(t);
        m_index = IndexOf<T, void, Ts...>::value;
    }

    inline ~Variant();

    inline Variant(const Variant<Ts...>& other);
    inline Variant(Variant<Ts...>&& other);

    inline Variant<Ts...>& operator=(const Variant<Ts...>& other);
    inline Variant<Ts...>& operator=(Variant<Ts...>&& other);

    template <class T> inline bool is() const;

    inline bool valid() const;

    template <class T, class... Args,
              class = typename std::enable_if<IsOneOf<T, Ts...>::value>::type>
    inline void set(Args&&... args);

    template <class T, class = typename std::enable_if<IsOneOf<T, Ts...>::value>::type>
    inline const T& get() const;

    template <class T, class = typename std::enable_if<IsOneOf<T, Ts...>::value>::type>
    inline T& get();

    inline void reset();

private:
    using Data = typename std::aligned_union<0, Ts...>::type;
    using Helper = Detail::VariantHelper<Data, Ts...>;

    std::size_t m_index{};
    Data m_data;
};

namespace Detail {

template <class Union, class T, class... Ts>
void VariantHelper<Union, T, Ts...>::destroy(std::size_t index, Union* data) {
    if (index == 0u)
        reinterpret_cast<T*>(data)->~T();

    else {
        --index;
        VariantHelper<Union, Ts...>::destroy(index, data);
    }
}

template <class Union, class T, class... Ts>
void VariantHelper<Union, T, Ts...>::move(std::size_t index, Union* oldValue, Union* newValue) {
    if (index == 0u)
        new (newValue) T(std::move(*reinterpret_cast<T*>(oldValue)));

    else {
        --index;
        VariantHelper<Union, Ts...>::move(index, oldValue, newValue);
    }
}

template <class Union, class T, class... Ts>
void VariantHelper<Union, T, Ts...>::copy(std::size_t index, const Union* oldValue,
                                          Union* newValue) {
    if (index == 0u)
        new (newValue) T(*reinterpret_cast<const T*>(oldValue));

    else {
        --index;
        VariantHelper<Union, Ts...>::copy(index, oldValue, newValue);
    }
}

} // namespace Detail

template <class... Ts> Variant<Ts...>::~Variant() {
    if (valid())
        Helper::destroy(m_index - 1u, &m_data);
}

template <class... Ts>
Variant<Ts...>::Variant(const Variant<Ts...>& other) : m_index{other.m_index} {
    if (valid())
        Helper::copy(m_index - 1u, &other.m_data, &m_data);
}

template <class... Ts> Variant<Ts...>::Variant(Variant<Ts...>&& other) : m_index{other.m_index} {
    if (valid())
        Helper::move(m_index - 1u, &other.m_data, &m_data);
}

template <class... Ts> Variant<Ts...>& Variant<Ts...>::operator=(const Variant<Ts...>& other) {
    if (valid())
        Helper::destroy(m_index - 1u, &m_data);

    m_index = other.m_index;

    if (valid())
        Helper::copy(m_index - 1u, &other.m_data, &m_data);

    return *this;
}

template <class... Ts> Variant<Ts...>& Variant<Ts...>::operator=(Variant<Ts...>&& other) {
    if (valid())
        Helper::destroy(m_index - 1u, &m_data);

    m_index = other.m_index;

    if (valid())
        Helper::move(m_index - 1u, &other.m_data, &m_data);

    return *this;
}

template <class... Ts> template <class T> bool Variant<Ts...>::is() const {
    return m_index == IndexOf<T, void, Ts...>::value;
}

template <class... Ts> bool Variant<Ts...>::valid() const {
    return m_index != 0u; // void
}

template <class... Ts>
template <class T, class... Args, class>
void Variant<Ts...>::set(Args&&... args) {
    if (valid())
        Helper::destroy(m_index - 1u, &m_data);

    new (&m_data) T(std::forward<Args>(args)...);
    m_index = IndexOf<T, void, Ts...>::value;
}

template <class... Ts> template <class T, class> const T& Variant<Ts...>::get() const {
    assert(valid() && "Uninitialized variant !");

    if (m_index == IndexOf<T, void, Ts...>::value) {
        const T* ptr = reinterpret_cast<const T*>(&m_data);
        return *ptr;
    }

    else
        throw std::bad_cast{};
}

template <class... Ts> template <class T, class> T& Variant<Ts...>::get() {
    assert(valid() && "Uninitialized variant !");

    if (m_index == IndexOf<T, void, Ts...>::value) {
        T* ptr = reinterpret_cast<T*>(&m_data);
        return *ptr;
    }

    else
        throw std::bad_cast{};
}

template <class... Ts> void Variant<Ts...>::reset() {
    if (valid())
        Helper::destroy(m_index - 1u, &m_data);

    m_index = 0u;
}

template <class... Ts> using variant = Variant<Ts...>;

#endif /* variant_hpp */
