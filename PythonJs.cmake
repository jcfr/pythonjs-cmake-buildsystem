cmake_minimum_required(VERSION 3.4)

set(CONFIGURE_ARGS)

# Convenience macro to set a variable and update list of configure arguments
macro(set_arg varname vartype value)
  set(arg -D${varname}:${vartype}=${value})
  list(APPEND CONFIGURE_ARGS ${arg})
  message(STATUS "Configuring using ${arg}")
  set(${varname} ${value} ${ARGN})
endmacro()

# Set PYTHON_CMAKE_BUILDSYSTEM_DIR if none was specified
if(NOT DEFINED PYTHON_CMAKE_BUILDSYSTEM_DIR) 
  set(PYTHON_CMAKE_BUILDSYSTEM_DIR "${CMAKE_CURRENT_LIST_DIR}/../python-cmake-buildsystem")
endif()
if(NOT EXISTS ${PYTHON_CMAKE_BUILDSYSTEM_DIR})
  message(FATAL_ERROR "Failed to locate python CMake buildsystem. Re-configure setting PYTHON_CMAKE_BUILDSYSTEM_DIR")
endif()
message(STATUS "Setting PYTHON_CMAKE_BUILDSYSTEM_DIR to '${PYTHON_CMAKE_BUILDSYSTEM_DIR}'")

# Set a default build type if none was specified
if(NOT CMAKE_BUILD_TYPE)
  message(STATUS "Setting build type to 'Release' as none was specified.")
  set_arg(CMAKE_BUILD_TYPE STRING Release)
endif()

# Set python version if none was specified
if(NOT DEFINED PY_VERSION_MAJOR)
  set(PY_VERSION_MAJOR 2)
endif()
if(NOT DEFINED PY_VERSION_MINOR)
  set(PY_VERSION_MINOR 7)
endif()
if(NOT DEFINED PY_VERSION_PATCH)
  set(PY_VERSION_PATCH 11)
endif()
set_arg(PY_VERSION_MAJOR STRING ${PY_VERSION_MAJOR})
set_arg(PY_VERSION_MINOR STRING ${PY_VERSION_MINOR})
set_arg(PY_VERSION_PATCH STRING ${PY_VERSION_PATCH})
set(version "${PY_VERSION_MAJOR}.${PY_VERSION_MINOR}.${PY_VERSION_PATCH}")

# Convenience boolean variables to easily test python version
set(IS_PY3 0)
set(IS_PY2 1)
if(PY_VERSION_MAJOR VERSION_GREATER 2)
    set(IS_PY3 1)
    set(IS_PY2 0)
endif()

# Toolchain
if(NOT EXISTS $ENV{CMAKE_TOOLCHAIN_FILE})
  message(FATAL_ERROR "CMAKE_TOOLCHAIN_FILE env variable is not set.")
endif()
set_arg(CMAKE_TOOLCHAIN_FILE FILEPATH $ENV{CMAKE_TOOLCHAIN_FILE})

# See https://github.com/kripken/emscripten/issues/2872
set(ENV{CFLAGS} "$ENV{CFLAGS} -s EMULATE_FUNCTION_POINTER_CASTS=1")

# Set to 1 to disable optimization
set(_disable_optimization 0)
if(_disable_optimization)
  set(ENV{CFLAGS} "$ENV{CFLAGS} -O0 -s ASSERTIONS=2 --js-opts 0 -g4")
endif()
message(STATUS "$ENV{CFLAGS}: $ENV{CFLAGS}")

# Include only python standard library
set_arg(INSTALL_DEVELOPMENT BOOL 0)
set_arg(INSTALL_MANUAL BOOL 0)
set_arg(INSTALL_TEST BOOL 0)

# Force all HAVE_SIG* to 0
# $ for sig  in $(cat cmake/config-unix/pyconfig.h.in | ack "HAVE_SIG" | cut -d" " -f2 | sed "/HAVE_SIGNAL_H/d"); do \
#     echo "$sig"; done;"
foreach(var 
  HAVE_SIGACTION
  HAVE_SIGALTSTACK
  HAVE_SIGINTERRUPT
  HAVE_SIGPENDING
  HAVE_SIGRELSE
  HAVE_SIGTIMEDWAIT
  HAVE_SIGWAIT
  HAVE_SIGWAITINFO
)
  set_arg(${var} BOOL 0)
endforeach()

# Explicitly disable code using ioctl.
#  * It is partially implemented in emscripten.
#  * FIOCLEX, FIONBIO and FIONCLEX used in Python/fileutils.c are missing.
if(IS_PY3)
  set_arg(HAVE_SYS_IOCTL_H BOOL 0)
endif()

# Disable dynamic loader
set_arg(HAVE_LIBDL BOOL 0)

# Disable python specific memory allocator
set_arg(WITH_PYMALLOC BOOL 0)

# Expect static libraries
set_arg(WITH_STATIC_DEPENDENCIES BOOL 1)

# Disable thread support.
set_arg(WITH_THREAD BOOL 0)

# Disable modules
set(disabled_modules
  CTYPES
  CTYPES_TEST
  LINUXAUDIODEV
  OSSAUDIODEV
  SOCKET
  TESTCAPI
  TERMIOS
)
if(IS_PY3)
  list(APPEND disabled_modules DECIMAL)
endif()
foreach(module IN LISTS disabled_modules)
  set_arg(ENABLE_${module} BOOL 0)
endforeach()

# Build directory
set(_build_dir ${CMAKE_CURRENT_BINARY_DIR}/python-cmake-buildsystem-${version}-build)
file(MAKE_DIRECTORY ${_build_dir})

# Installation directory
set(_install_dir ${CMAKE_CURRENT_BINARY_DIR}/python-cmake-buildsystem-${version}-install)
file(MAKE_DIRECTORY ${_install_dir})
set_arg(CMAKE_INSTALL_PREFIX PATH ${_install_dir})

# Uncomment line to display configure command
set(text)
foreach(arg ${CMAKE_COMMAND} ${CONFIGURE_ARGS} ${PYTHON_CMAKE_BUILDSYSTEM_DIR})
  set(text "${text} ${arg}")
endforeach()
#message(STATUS "Configure command: ${text}")

# Configure 
execute_process(
  COMMAND ${CMAKE_COMMAND} ${CONFIGURE_ARGS} ${PYTHON_CMAKE_BUILDSYSTEM_DIR}
  WORKING_DIRECTORY ${_build_dir}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to configure")
endif()

# Build
execute_process(
  COMMAND ${CMAKE_COMMAND} --build ${_build_dir} -- -j5
  WORKING_DIRECTORY ${_build_dir}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to build")
endif()

# Install
execute_process(
  COMMAND ${CMAKE_COMMAND} --build ${_build_dir} --target install
  WORKING_DIRECTORY ${_build_dir}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to install")
endif()

# Read prejs header and footer
file(READ ${CMAKE_CURRENT_LIST_DIR}/js/pre_header.js prejs_header)
file(READ ${CMAKE_CURRENT_LIST_DIR}/js/pre_footer.js prejs_footer)

# Generate filesystem map
#   Adapted from https://github.com/replit/empythoned/blob/master/map_filesystem.py
#   XXX Use this approach instead: https://github.com/aidanhs/empython/blob/master/mapfiles.py
find_package(PythonInterp REQUIRED)

set(_msg "Generating python standard library FileSystem map")
message(STATUS "${_msg}")
execute_process(
  COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_LIST_DIR}/utils/map_filesystem.py ${CMAKE_INSTALL_PREFIX}
  OUTPUT_VARIABLE prejs_fs
  RESULT_VARIABLE result
)
if(result EQUAL 0)
  message(STATUS "${_msg} - done")
else()
  message(FATAL_ERROR "Failed to re-configure using ${_prejs_arg}")
endif()

# Generate pre.js
set(_prejs_path ${_build_dir}/pre.js)
set(_msg "Configuring '${_prejs_path}'")
message(STATUS "${_msg}")
file(WRITE ${_prejs_path} 
"${prejs_header}
${prejs_fs}
${prejs_footer}")
message(STATUS "${_msg} - done")

# Re-build python.js setting EMCC_CFLAGS env. variable
set(ENV{EMCC_CFLAGS} "--pre-js ${_prejs_path}")
message(STATUS "Setting EMCC_CFLAGS env variable to '$ENV{EMCC_CFLAGS}'")
execute_process(
  COMMAND ${CMAKE_COMMAND} --build ${_build_dir} --target python/fast -- -B
  WORKING_DIRECTORY ${_build_dir}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to build 'python' target")
endif()

# Install
execute_process(
  COMMAND ${CMAKE_COMMAND} --build ${_build_dir} --target install
  WORKING_DIRECTORY ${_build_dir}
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to install")
endif()

# Install python.js.mem
execute_process(
  COMMAND ${CMAKE_COMMAND} -E copy
    ${_build_dir}/bin/python.js.mem
    ${_install_dir}/bin/python.js.mem
  RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Failed to copy '${_build_dir}/bin/python.js.mem' into '${_install_dir}/bin'")
endif()


