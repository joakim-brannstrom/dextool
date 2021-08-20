# vim: filetype=cmake
cmake_minimum_required(VERSION 3.0)
project(game_tutorial)
enable_testing()

set(SRC
    "src/game.cpp"
    "src/mob.cpp"
    "src/mobsystem.cpp"
    "src/physicssystem.cpp"
    "src/rendersystem.cpp"
    "src/window.cpp"
    )

set(TERMBOX_SRC
    "deps/termbox/termbox.c"
    "deps/termbox/utf8.c"
    )

set(TEST_SRC
    "test/basic.cpp"
    )

add_library(gtest ${GTEST_DIR}/gmock-gtest-all.cc ${GTEST_DIR}/main.cc)
target_include_directories(gtest PUBLIC ${GTEST_DIR})
target_link_libraries(gtest pthread)

add_library(termbox ${TERMBOX_SRC})
target_include_directories(termbox PUBLIC "deps/termbox")

add_library(variant INTERFACE)
target_include_directories(variant INTERFACE "deps")

add_executable(rl ${SRC} src/main.cpp)
target_compile_options(rl PRIVATE "-std=c++14" "-O3")
target_link_libraries(rl variant termbox m)
target_include_directories(rl PUBLIC src)

add_executable(rl_test ${TEST_SRC} ${SRC})
add_test(rl_test rl_test)
target_link_libraries(rl_test gtest variant termbox m)
target_compile_options(rl_test PRIVATE "-std=c++14" "-O3")
target_compile_definitions(rl_test PRIVATE -DNO_WINDOW)
target_include_directories(rl_test PUBLIC src)

if (GCOV)
    target_compile_options(rl_test PRIVATE "--coverage")
    target_link_libraries(rl_test gcov)
endif()
