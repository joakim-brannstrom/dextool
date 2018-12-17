#
# Common CPack configuration
#
set(CPACK_PACKAGE_NAME ${CMAKE_PROJECT_NAME})
set(CPACK_PACKAGE_VERSION ${DEXTOOL_EMBEDDED_VERSION_PATH})
set(CPACK_PACKAGE_CONTACT "joakim.brannstrom.public@gmx.com")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Dextool: C/C++ tooling for test and analysis")

#
# Debian specifics
#
execute_process(COMMAND dpkg --print-architecture OUTPUT_VARIABLE CPACK_DEBIAN_PACKAGE_ARCHITECTURE) 
set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
