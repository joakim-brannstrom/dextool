if(BUILD_TEST)
    include(dextool_unit_threaded.cmake)
endif()

include(dextool_scriptlike.cmake)
include(dextool_llvm_d.cmake)
include(dextool_d2sqlite3.cmake)
include(dextool_gtest.cmake)
