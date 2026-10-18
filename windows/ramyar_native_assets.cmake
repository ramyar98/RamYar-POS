# Recovery logic for the Dart build hooks' native assets.
#
# This file is used from two places, and there is deliberately only one copy
# of the logic so the two can never disagree:
#
#   * ../CMakeLists.txt includes it and calls the function at configure time,
#     so a fresh configure reports and repairs the problem before the build
#     starts, and
#   * ../flutter/CMakeLists.txt runs it with -P immediately before the flutter
#     tool backend, because CMake only re-configures when build.ninja is out
#     of date. Without the build-time call, a build that does not re-configure
#     would keep trusting stale state - which is the case that silently
#     produced a broken executable.

# ramyar_recover_native_assets_state(<project_dir> <assets_dir> <required...>)
#
# The app cannot open its database without the native assets named in
# <required>: sqlite3.dll is loaded through FFI by sqflite_common_ffi. When one
# of them is not in <assets_dir> the stale state that is hiding this is
# cleared, so that the flutter tool re-runs the hooks and redoes the install
# copy on the build that is already under way.
#
# A no-op when everything required is present, which is the normal case.
function(ramyar_recover_native_assets_state project_dir assets_dir)
  set(required ${ARGN})
  if(NOT required)
    return()
  endif()

  set(missing "")
  foreach(asset IN LISTS required)
    if(NOT EXISTS "${assets_dir}/${asset}")
      set(missing "${missing} ${asset}")
    endif()
  endforeach()
  if(NOT missing)
    return()
  endif()

  # Where the problem comes from.
  #
  # The flutter tool records what the hooks produced in
  # .dart_tool/flutter_build/<hash>/, one directory per build environment:
  #
  #     dart_build.stamp / dart_build_result.json      the hook run
  #     install_code_assets.stamp / native_assets.json    copying the result
  #
  # Both targets declare ONLY those state files as their outputs. The binaries
  # the install step copies out of build/native_assets are not in the
  # depfiles, so a hook run that recorded an empty code_assets list - or a
  # cleanup that empties build/native_assets without also clearing
  # .dart_tool/flutter_build - leaves both targets looking up to date. They are
  # then skipped ("Skipping target: dart_build", "Skipping target:
  # install_code_assets") while the empty recorded manifest stays put.
  #
  # From there the install either stops on a missing directory, or - if the
  # directory is still there and empty - succeeds having copied nothing and
  # produces an exe that starts, opens no database and shows no window, from a
  # build log that is entirely green. Clearing this state is what makes the
  # hooks run again; the install guard in ../CMakeLists.txt then fails the
  # build loudly if they still did not produce the library.
  file(GLOB stale_state
    "${project_dir}/.dart_tool/flutter_build/*/dart_build.stamp"
    "${project_dir}/.dart_tool/flutter_build/*/dart_build_result.json"
    "${project_dir}/.dart_tool/flutter_build/*/install_code_assets.stamp"
    "${project_dir}/.dart_tool/flutter_build/*/native_assets.json")
  if(stale_state)
    message(STATUS
      "RAMYAR: native assets missing (${missing}) in ${assets_dir} - clearing "
      "the stale Dart hook state so the flutter tool rebuilds them")
    file(REMOVE ${stale_state})
  endif()
endfunction()

# Standalone entry point, used by ../flutter/CMakeLists.txt:
#
#   cmake -DRAMYAR_NATIVE_ASSETS_PROJECT_DIR=<project dir>
#         -DRAMYAR_NATIVE_ASSETS_DIR=<...>/build/native_assets/windows
#         -DRAMYAR_REQUIRED_NATIVE_ASSETS=<names joined with "|">
#         -P ramyar_native_assets.cmake
#
# The names are joined with "|" rather than ";" so the whole list stays a
# single command line argument under VERBATIM.
if(DEFINED RAMYAR_NATIVE_ASSETS_PROJECT_DIR)
  string(REPLACE "|" ";" ramyar_required "${RAMYAR_REQUIRED_NATIVE_ASSETS}")
  ramyar_recover_native_assets_state(
    "${RAMYAR_NATIVE_ASSETS_PROJECT_DIR}"
    "${RAMYAR_NATIVE_ASSETS_DIR}"
    ${ramyar_required})
endif()
