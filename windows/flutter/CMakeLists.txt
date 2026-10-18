# This file controls Flutter-level build steps. It should not be edited.
cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# TODO: Move the rest of this into files in ephemeral. See
# https://github.com/flutter/flutter/issues/57146.
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")

# Set fallback configurations for older versions of the flutter tool.
if (NOT DEFINED FLUTTER_TARGET_PLATFORM)
  set(FLUTTER_TARGET_PLATFORM "windows-x64")
endif()

# === Flutter Library ===
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")

# Published to parent scope for install step.
set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_DIR}/build/" PARENT_SCOPE)
set(AOT_LIBRARY "${PROJECT_DIR}/build/windows/app.so" PARENT_SCOPE)

list(APPEND FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_windows.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)
list(TRANSFORM FLUTTER_LIBRARY_HEADERS PREPEND "${EPHEMERAL_DIR}/")
add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}.lib")
add_dependencies(flutter flutter_assemble)

# === Wrapper ===
list(APPEND CPP_WRAPPER_SOURCES_CORE
  "core_implementations.cc"
  "standard_codec.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_CORE PREPEND "${WRAPPER_ROOT}/")
list(APPEND CPP_WRAPPER_SOURCES_PLUGIN
  "plugin_registrar.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_PLUGIN PREPEND "${WRAPPER_ROOT}/")
list(APPEND CPP_WRAPPER_SOURCES_APP
  "flutter_engine.cc"
  "flutter_view_controller.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_APP PREPEND "${WRAPPER_ROOT}/")

# Wrapper sources needed for a plugin.
add_library(flutter_wrapper_plugin STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
)
apply_standard_settings(flutter_wrapper_plugin)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  POSITION_INDEPENDENT_CODE ON)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_dependencies(flutter_wrapper_plugin flutter_assemble)

# Wrapper sources needed for the runner.
add_library(flutter_wrapper_app STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_APP}
)
apply_standard_settings(flutter_wrapper_app)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_dependencies(flutter_wrapper_app flutter_assemble)

# === Flutter tool backend ===
# _phony_ is a non-existent file to force this command to run every time,
# since currently there's no way to get a full input/output list from the
# flutter tool.
set(PHONY_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/_phony_")
set_source_files_properties("${PHONY_OUTPUT}" PROPERTIES SYMBOLIC TRUE)

# The import library is listed as an OUTPUT on purpose.
#
# tool_backend.bat writes flutter_windows.dll.lib into the ephemeral folder
# next to the DLL, and the link of ramyar_pos.exe takes that file as an input
# (see target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}.lib")
# above). It is not a declared output in the stock template, so on a build
# where the ephemeral folder is still empty - which is every first build,
# every `flutter clean` and every fresh clone - ninja resolves its dependency
# graph, finds the import library missing with no rule to make it, and stops
# before it ever runs the command that would have produced it:
#
#     ninja: error: '...\ephemeral\flutter_windows.dll.lib', needed by
#     'runner/ramyar_pos.exe', missing and no known rule to make it
#
# Declaring it makes the ordering explicit: the rule runs, the file appears,
# and the link can read it.
add_custom_command(
  OUTPUT ${FLUTTER_LIBRARY} "${FLUTTER_LIBRARY}.lib" ${FLUTTER_LIBRARY_HEADERS}
    ${CPP_WRAPPER_SOURCES_CORE} ${CPP_WRAPPER_SOURCES_PLUGIN}
    ${CPP_WRAPPER_SOURCES_APP}
    ${PHONY_OUTPUT}
  COMMAND ${CMAKE_COMMAND} -E env
    ${FLUTTER_TOOL_ENVIRONMENT}
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      ${FLUTTER_TARGET_PLATFORM} $<CONFIG>
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIBRARY}"
  "${FLUTTER_LIBRARY}.lib"
  ${FLUTTER_LIBRARY_HEADERS}
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
  ${CPP_WRAPPER_SOURCES_APP}
)

# === Native asset recovery ===
# Runs immediately before the flutter tool backend on every build.
#
# ../CMakeLists.txt does the same check at configure time, but CMake only
# re-configures when build.ninja is out of date, so that check alone would not
# run for a plain incremental build - exactly the build that carries the stale
# state. The Dart build hooks keep their own record of what they produced under
# .dart_tool/flutter_build/<hash>/ and declare only those state files as their
# outputs, never the binaries the install step copies out of
# <project>/build/native_assets. A missing or emptied sqlite3.dll therefore
# leaves them looking up to date, they get skipped, and the build can finish
# green having produced an exe with no database behind it. This is declared as
# a dependency of flutter_assemble rather than as a command inside it so the
# stock tool backend invocation above is left exactly as the template has it,
# and it is added after flutter_assemble exists because add_dependencies()
# rejects a target that has not been declared yet.
if(RAMYAR_REQUIRED_NATIVE_ASSETS)
  string(REPLACE ";" "|" RAMYAR_REQUIRED_NATIVE_ASSETS_ARG
    "${RAMYAR_REQUIRED_NATIVE_ASSETS}")
  add_custom_target(ramyar_native_assets_recovery
    COMMAND ${CMAKE_COMMAND}
      "-DRAMYAR_NATIVE_ASSETS_PROJECT_DIR=${PROJECT_DIR}"
      "-DRAMYAR_NATIVE_ASSETS_DIR=${RAMYAR_NATIVE_ASSETS_DIR}"
      "-DRAMYAR_REQUIRED_NATIVE_ASSETS=${RAMYAR_REQUIRED_NATIVE_ASSETS_ARG}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/../ramyar_native_assets.cmake"
    VERBATIM
  )
  add_dependencies(flutter_assemble ramyar_native_assets_recovery)
endif()
