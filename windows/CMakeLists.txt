# Project-level configuration.
cmake_minimum_required(VERSION 3.14)

# ==========================================================================
#  MSVC bootstrap - has to run before project().
#
#  Why this is here:
#
#  This Flutter toolchain builds Windows with the single-config Ninja
#  generator and locates only cmake.exe. It never puts cl.exe, link.exe,
#  rc.exe, mt.exe or ninja.exe on PATH and never imports the Visual Studio
#  environment, so a plain `flutter run -d windows` from a normal
#  command prompt used to die during configuration with
#
#      CMake Error: CMake was unable to find a build program corresponding
#                    to "Ninja".  CMAKE_MAKE_PROGRAM is not set.
#      CMake Error: CMAKE_CXX_COMPILER not set, after EnableLanguage
#
#  The launchers in the project root used to work around this by calling
#  vcvars64.bat first, which made the build depend on which shell happened
#  to start it. Everything is now found and set up from inside the project,
#  so `flutter run -d windows` and `flutter build windows` work from any
#  prompt and no wrapper script is required.
#
#  Three things are needed and none of them can be guessed:
#
#    1. An absolute cl.exe (CMAKE_CXX_COMPILER). CMake derives link.exe from
#       the compiler's own directory, so this one setting covers both.
#    2. Absolute rc.exe and mt.exe (CMAKE_RC_COMPILER / CMAKE_MT). CMake
#       resolves these while enabling the RC language; if it cannot, it
#       bakes the literal string "CMAKE_MT-NOTFOUND" into the link rule and
#       the build dies with a bare "no such file or directory".
#    3. The INCLUDE / LIB search paths at BUILD time. CMake does not bake the
#       compiler's implicit include directories into the generated rules, and
#       it hands system libraries such as kernel32.lib to the linker by name,
#       so a build started without INCLUDE and LIB fails with
#       "fatal error C1034: cassert: no include path set" and
#       "LNK1104: cannot open file 'kernel32.lib'". These are given to the
#       build explicitly instead: include_directories() for the C++ and
#       resource compilers, /LIBPATH: for the linker.
#
#  When the environment is already set up - a Visual Studio developer
#  prompt, or the project launchers - none of this runs and the build
#  behaves exactly as it always did.
# ==========================================================================
set(RAMYAR_MSVC_CONFIGURED_BY_CMAKE FALSE)

find_program(RAMYAR_CL_EXE NAMES cl.exe)
if(RAMYAR_CL_EXE)
  message(STATUS "RAMYAR: using the MSVC environment already in this shell")
else()
  # --- Locate the Visual Studio installation ---------------------------
  # vswhere.exe ships in the VS installer and is what the flutter tool uses
  # too, so this follows the machine rather than a hardcoded edition path.
  set(RAMYAR_VSWHERE "$ENV{VSWHERE}")
  if(NOT RAMYAR_VSWHERE)
    set(RAMYAR_VSWHERE
      "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe")
  endif()

  set(RAMYAR_VS_DIR "$ENV{VSINSTALLDIR}")
  if(NOT RAMYAR_VS_DIR AND EXISTS "${RAMYAR_VSWHERE}")
    file(TO_CMAKE_PATH "${RAMYAR_VS_DIR}" RAMYAR_VS_DIR)
    execute_process(
      COMMAND "${RAMYAR_VSWHERE}" -latest -products * -prerelease
              -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64
              -property installationPath
      OUTPUT_VARIABLE RAMYAR_VS_DIR
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
  endif()
  if(RAMYAR_VS_DIR)
    file(TO_CMAKE_PATH "${RAMYAR_VS_DIR}" RAMYAR_VS_DIR)
    string(REGEX REPLACE "/+$" "" RAMYAR_VS_DIR "${RAMYAR_VS_DIR}")
  endif()

  if(NOT RAMYAR_VS_DIR)
    message(FATAL_ERROR
      "No MSVC toolchain found. Install the \"Desktop development with C++\" "
      "workload in Visual Studio, or build from a Visual Studio developer "
      "command prompt.")
  endif()

  # --- The compiler: newest MSVC toolset under the installation --------
  file(GLOB RAMYAR_MSVC_CANDIDATES "${RAMYAR_VS_DIR}/VC/Tools/MSVC/*")
  list(SORT RAMYAR_MSVC_CANDIDATES COMPARE NATURAL ORDER DESCENDING)
  set(RAMYAR_MSVC_DIR "")
  foreach(candidate IN LISTS RAMYAR_MSVC_CANDIDATES)
    if(EXISTS "${candidate}/bin/Hostx64/x64/cl.exe")
      set(RAMYAR_MSVC_DIR "${candidate}")
      break()
    endif()
  endforeach()
  if(NOT RAMYAR_MSVC_DIR)
    message(FATAL_ERROR
      "Found Visual Studio at ${RAMYAR_VS_DIR} but no MSVC toolset with "
      "cl.exe under VC/Tools/MSVC.")
  endif()

  # --- The Windows SDK: rc.exe, mt.exe, headers and libraries ---------
  # The newest version that has the tools AND the matching include and lib
  # trees is used, because the headers and the libraries handed to the build
  # below have to come from the same SDK as the tools.
  set(RAMYAR_SDK_ROOT "$ENV{WindowsSdkDir}")
  if(NOT RAMYAR_SDK_ROOT)
    set(RAMYAR_SDK_ROOT "C:/Program Files (x86)/Windows Kits/10")
  endif()
  file(TO_CMAKE_PATH "${RAMYAR_SDK_ROOT}" RAMYAR_SDK_ROOT)
  string(REGEX REPLACE "/+$" "" RAMYAR_SDK_ROOT "${RAMYAR_SDK_ROOT}")

  file(GLOB RAMYAR_SDK_CANDIDATES "${RAMYAR_SDK_ROOT}/bin/*/x64")
  list(SORT RAMYAR_SDK_CANDIDATES COMPARE NATURAL ORDER DESCENDING)
  set(RAMYAR_SDK_BIN_DIR "")
  set(RAMYAR_SDK_VERSION "")
  foreach(candidate IN LISTS RAMYAR_SDK_CANDIDATES)
    if(NOT EXISTS "${candidate}/rc.exe" OR NOT EXISTS "${candidate}/mt.exe")
      continue()
    endif()
    get_filename_component(sdk_bin_dir "${candidate}" DIRECTORY)
    get_filename_component(sdk_version "${sdk_bin_dir}" NAME)
    set(sdk_ok TRUE)
    foreach(needed IN ITEMS
        "Include/${sdk_version}/ucrt"
        "Include/${sdk_version}/shared"
        "Include/${sdk_version}/um"
        "Lib/${sdk_version}/ucrt/x64"
        "Lib/${sdk_version}/um/x64")
      if(NOT EXISTS "${RAMYAR_SDK_ROOT}/${needed}")
        set(sdk_ok FALSE)
        break()
      endif()
    endforeach()
    if(sdk_ok)
      set(RAMYAR_SDK_BIN_DIR "${candidate}")
      set(RAMYAR_SDK_VERSION "${sdk_version}")
      break()
    endif()
  endforeach()
  if(NOT RAMYAR_SDK_BIN_DIR)
    message(FATAL_ERROR
      "No usable Windows SDK under ${RAMYAR_SDK_ROOT}: a version needs "
      "rc.exe, mt.exe, Include/<version>/{ucrt,shared,um} and "
      "Lib/<version>/{ucrt,um}/x64.")
  endif()

  # --- Ninja ----------------------------------------------------------
  set(RAMYAR_NINJA_EXE "${RAMYAR_VS_DIR}/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe")
  if(NOT EXISTS "${RAMYAR_NINJA_EXE}")
    # Older layouts put it one level up, next to the CMake bin folder.
    file(GLOB_RECURSE RAMYAR_NINJA_CANDIDATES
      "${RAMYAR_VS_DIR}/Common7/IDE/CommonExtensions/Microsoft/CMake/*/ninja.exe")
    list(SORT RAMYAR_NINJA_CANDIDATES COMPARE NATURAL ORDER DESCENDING)
    if(RAMYAR_NINJA_CANDIDATES)
      list(GET RAMYAR_NINJA_CANDIDATES 0 RAMYAR_NINJA_EXE)
    endif()
  endif()
  if(NOT EXISTS "${RAMYAR_NINJA_EXE}")
    message(FATAL_ERROR
      "No ninja.exe under the Visual Studio CMake tools. Install the "
      "\"Desktop development with C++\" workload, or add ninja to PATH.")
  endif()

  # --- Everything is addressed by absolute path from here on ----------
  # Forward slashes throughout: CMake 3.31 writes the compiler/RC paths into
  # generated cmake files verbatim and then re-parses them, so a path that
  # holds both a space and parentheses stored with backslashes fails with
  # "Invalid character escape '\P'".
  set(CMAKE_MAKE_PROGRAM "${RAMYAR_NINJA_EXE}" CACHE FILEPATH
    "Build program (Ninja, from the Visual Studio CMake tools)" FORCE)
  set(CMAKE_CXX_COMPILER "${RAMYAR_MSVC_DIR}/bin/Hostx64/x64/cl.exe" CACHE
    FILEPATH "C++ compiler" FORCE)
  set(CMAKE_AR "${RAMYAR_MSVC_DIR}/bin/Hostx64/x64/lib.exe" CACHE FILEPATH
    "Archiver, used for the static libraries in windows\\flutter" FORCE)
  set(CMAKE_RC_COMPILER "${RAMYAR_SDK_BIN_DIR}/rc.exe" CACHE FILEPATH
    "Windows resource compiler" FORCE)
  set(CMAKE_MT "${RAMYAR_SDK_BIN_DIR}/mt.exe" CACHE FILEPATH
    "Windows manifest tool" FORCE)

  # --- The include and library search paths --------------------------
  # These replace the INCLUDE and LIB environment variables that
  # vcvars64.bat would otherwise export, and they have to be in the rules
  # themselves: CMake does not copy the compiler's implicit include
  # directories into what it generates, and it hands system libraries such as
  # kernel32.lib to the linker by name, so a build without them dies with
  #   fatal error C1034: cassert: no include path set
  #   LINK : fatal error LNK1104: cannot open file 'kernel32.lib'
  #
  # include_directories() is used rather than
  # CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES because Runner.rc includes
  # winres.h, so the resource compiler needs the SDK headers too. Being
  # directory scoped, it reaches windows\\runner and windows\\flutter.
  set(RAMYAR_MSYSTEM_INCLUDE_DIRS
    "${RAMYAR_MSVC_DIR}/include"
    "${RAMYAR_SDK_ROOT}/Include/${RAMYAR_SDK_VERSION}/ucrt"
    "${RAMYAR_SDK_ROOT}/Include/${RAMYAR_SDK_VERSION}/shared"
    "${RAMYAR_SDK_ROOT}/Include/${RAMYAR_SDK_VERSION}/um"
    "${RAMYAR_SDK_ROOT}/Include/${RAMYAR_SDK_VERSION}/winrt")
  set(RAMYAR_MSYSTEM_LIB_DIRS
    "${RAMYAR_MSVC_DIR}/lib/x64"
    "${RAMYAR_SDK_ROOT}/Lib/${RAMYAR_SDK_VERSION}/ucrt/x64"
    "${RAMYAR_SDK_ROOT}/Lib/${RAMYAR_SDK_VERSION}/um/x64")
  include_directories(SYSTEM ${RAMYAR_MSYSTEM_INCLUDE_DIRS})

  # /LIBPATH: is the linker's equivalent of LIB. Set as a normal variable as
  # well as through the _INIT form, because windows\\runner calls project()
  # again and that re-reads CMAKE_EXE_LINKER_FLAGS for its own directory.
  set(RAMYAR_LIBPATH_FLAGS "")
  foreach(lib_dir IN LISTS RAMYAR_MSYSTEM_LIB_DIRS)
    set(RAMYAR_LIBPATH_FLAGS "${RAMYAR_LIBPATH_FLAGS} /LIBPATH:\"${lib_dir}\"")
  endforeach()
  set(CMAKE_EXE_LINKER_FLAGS_INIT "${RAMYAR_LIBPATH_FLAGS}")
  set(CMAKE_EXE_LINKER_FLAGS "${RAMYAR_LIBPATH_FLAGS}")
  set(CMAKE_SHARED_LINKER_FLAGS_INIT "${RAMYAR_LIBPATH_FLAGS}")
  set(CMAKE_MODULE_LINKER_FLAGS_INIT "${RAMYAR_LIBPATH_FLAGS}")

  # Helps anything CMake itself runs during the configure step find the
  # toolchain; the build no longer depends on it.
  set(ENV{PATH}
    "${RAMYAR_MSVC_DIR}/bin/Hostx64/x64;${RAMYAR_SDK_BIN_DIR};$ENV{PATH}")

  set(RAMYAR_MSVC_CONFIGURED_BY_CMAKE TRUE)
  message(STATUS
    "RAMYAR: MSVC not in this shell - using ${RAMYAR_MSVC_DIR}, Windows SDK "
    "${RAMYAR_SDK_VERSION} and the Ninja from Visual Studio")
endif()

# Captured BEFORE project() on purpose.
#
# CMake seeds CMAKE_BUILD_TYPE itself while project() runs
# (CMakeInitializeConfigs.cmake does `set(CMAKE_BUILD_TYPE Debug CACHE STRING
# ...)`), so past project() the variable always looks "already set" and the
# stock template's `if(NOT CMAKE_BUILD_TYPE)` can never fire. Reading it up
# here, where the only thing that can have set it is an explicit
# -DCMAKE_BUILD_TYPE on the command line, is what makes the difference between
# "the caller asked for X" and "CMake invented Debug" visible at all.
if(DEFINED CMAKE_BUILD_TYPE)
  set(RAMYAR_REQUESTED_BUILD_TYPE "${CMAKE_BUILD_TYPE}")
endif()

project(ramyar_pos LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "ramyar_pos")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  # This Flutter toolchain always selects the single-config "Ninja" generator
  # (VisualStudio.cmakeGenerator in flutter_tools returns 'Ninja'
  # unconditionally) and it does NOT pass -DCMAKE_BUILD_TYPE when it configures
  # the project. It also passes --config to `cmake --build`, which a
  # single-config generator ignores, and there is no other trace of the
  # requested mode: the flutter tool writes nothing mode-dependent into
  # windows\flutter\ephemeral\generated_config.cmake for Windows (both
  # TREE_SHAKE_ICONS and TRACK_WIDGET_CREATION are false for every Windows
  # build, debug or release). So the mode genuinely cannot be inferred here
  # and has to be declared.
  #
  # Precedence: the launchers in the project root (run_windows.bat /
  # run_windows_dev.bat) declare the mode through RAMYAR_BUILD_TYPE; an
  # explicit -DCMAKE_BUILD_TYPE is honoured next; with neither, Debug is the
  # default, which is the mode `flutter run -d windows` needs and the mode a
  # wrong guess fails least badly in. Getting this wrong is not cosmetic -
  # CMAKE_BUILD_TYPE is what "$<CONFIG>" passes to tool_backend.bat, so it
  # decides which engine is staged and whether the app is built JIT
  # (kernel_blob.bin) or AOT (app.so). A release request therefore needs
  # RAMYAR_BUILD_TYPE=Release, which is what run_windows.bat sets.
  if(DEFINED ENV{RAMYAR_BUILD_TYPE} AND NOT "$ENV{RAMYAR_BUILD_TYPE}" STREQUAL "")
    set(RAMYAR_BUILD_TYPE_RESOLVED "$ENV{RAMYAR_BUILD_TYPE}")
  elseif(RAMYAR_REQUESTED_BUILD_TYPE)
    set(RAMYAR_BUILD_TYPE_RESOLVED "${RAMYAR_REQUESTED_BUILD_TYPE}")
  else()
    set(RAMYAR_BUILD_TYPE_RESOLVED "Debug")
  endif()
  if(NOT RAMYAR_BUILD_TYPE_RESOLVED MATCHES "^(Debug|Profile|Release)$")
    message(FATAL_ERROR
      "Unsupported build type '${RAMYAR_BUILD_TYPE_RESOLVED}'. "
      "Use Debug, Profile or Release.")
  endif()
  # FORCE is required: project() has already put Debug in the cache.
  set(CMAKE_BUILD_TYPE "${RAMYAR_BUILD_TYPE_RESOLVED}" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
  message(STATUS "RAMYAR: building ${BINARY_NAME} in ${CMAKE_BUILD_TYPE}")
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  # The warning numbers must be written WITHOUT quotes. The stock template uses
  # /wd"4100", which only works because the Visual Studio (multi-config)
  # generator normalises the quotes on the way to cl.exe. This project is built
  # with the single-config Ninja generator, which passes the string through
  # verbatim, and cl.exe then rejects it with
  #   cl : Command line error D8021 : invalid numeric argument '/wd"4100"'
  # failing every translation unit in the build.
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100)
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# ==========================================================================
#  Native assets - keep a missing sqlite3.dll from going unnoticed.
#
#  The app cannot open its database without sqlite3.dll, which the sqlite3
#  package's Dart build hook compiles. The flutter tool records what those
#  hooks produced under .dart_tool\flutter_build\<hash>\:
#
#      dart_build.stamp / dart_build_result.json     the hook run
#      install_code_assets.stamp / native_assets.json   copying the result
#
#  Both targets declare ONLY those state files as their outputs. The
#  binaries the install step copies out of build\native_assets\windows\ do
#  not appear in the depfiles, so removing or emptying that directory
#  leaves both targets looking up to date and the build system skips them
#  ("Skipping target: dart_build", "Skipping target: install_code_assets")
#  while the stamps and the empty recorded manifest stay put.
#
#  That then goes wrong in one of two ways, and the second is the
#  dangerous one:
#
#    * the directory is gone, so the install step stops with
#      "file INSTALL cannot find .../build/native_assets/windows", or
#    * the directory is still there but empty, so the install step
#      succeeds having copied nothing and produces an exe that starts,
#      opens no database and shows no window - from a build log that is
#      entirely green.
#
#  This is reachable from ordinary use, not only from hand-editing: a hook
#  run that records an empty code_assets list latches the "already done"
#  state permanently, and a sync/clean script that removes
#  build\native_assets without also clearing .dart_tool\flutter_build
#  reproduces it. Deleting the state for exactly these two targets when the
#  library is missing makes the flutter_assemble step re-run the hooks and
#  redo the install copy, so the build heals itself. The guard after the
#  install rules below then refuses to let a build finish in that state,
#  so the failure can never be silent again.
#
#  When the library is present nothing here runs and the build behaves
#  exactly as it always did.
# ==========================================================================
get_filename_component(RAMYAR_PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}" DIRECTORY)
set(RAMYAR_BUILD_DIR "${RAMYAR_PROJECT_DIR}/build")
set(RAMYAR_NATIVE_ASSETS_DIR "${RAMYAR_BUILD_DIR}/native_assets/windows")

# The native assets this app cannot start without. sqlite3.dll is loaded
# through FFI by sqflite_common_ffi; without it the database never opens.
# Keep this in step with pubspec.yaml dependencies that ship a build hook.
set(RAMYAR_REQUIRED_NATIVE_ASSETS "sqlite3.dll")

# Repaired at configure time here and again before every flutter tool backend
# run; see ramyar_native_assets.cmake for why, and for the shape of the bug
# this guards against.
include("${CMAKE_CURRENT_SOURCE_DIR}/ramyar_native_assets.cmake")
ramyar_recover_native_assets_state(
  "${RAMYAR_PROJECT_DIR}"
  "${RAMYAR_NATIVE_ASSETS_DIR}"
  ${RAMYAR_REQUIRED_NATIVE_ASSETS})

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Refuse to finish a build whose native assets did not arrive.
#
# install(DIRECTORY) only fails when the source directory is missing; an
# existing but empty one installs nothing and reports success, so on its
# own it cannot tell a good build from a broken one. This runs last, after
# the copy above, and turns that silent case into a loud stop with the
# command that fixes it. See the "Native assets" note above the
# FLUTTER_MANAGED_DIR add_subdirectory for the underlying cause.
if(RAMYAR_REQUIRED_NATIVE_ASSETS)
  # The list is handed over as a "|" joined string and split again inside the
  # install script. It cannot be interpolated as ${RAMYAR_REQUIRED_NATIVE_ASSETS}
  # because that would expand to a bare list where foreach(... IN LISTS ...)
  # expects a variable name, and it cannot be referenced by name either:
  # install(CODE ...) runs in its own scope, where a variable from this one does
  # not exist - which left the loop iterating over nothing and the guard inert.
  string(REPLACE ";" "|" RAMYAR_REQUIRED_NATIVE_ASSETS_ARG
    "${RAMYAR_REQUIRED_NATIVE_ASSETS}")
  install(CODE "
    string(REPLACE \"|\" \";\" ramyar_required \"${RAMYAR_REQUIRED_NATIVE_ASSETS_ARG}\")
    set(RAMYAR_BUNDLE_LIB_DIR \"${INSTALL_BUNDLE_LIB_DIR}\")
    set(RAMYAR_MISSING_NATIVE_ASSETS \"\")
    foreach(ramyar_asset IN LISTS ramyar_required)
      if(NOT EXISTS \"\${RAMYAR_BUNDLE_LIB_DIR}/\${ramyar_asset}\")
        list(APPEND RAMYAR_MISSING_NATIVE_ASSETS \"\${ramyar_asset}\")
      endif()
    endforeach()
    if(RAMYAR_MISSING_NATIVE_ASSETS)
      list(JOIN RAMYAR_MISSING_NATIVE_ASSETS \", \" RAMYAR_MISSING_NATIVE_ASSETS)
      message(FATAL_ERROR
        \"The build did not produce the native asset(s) \${RAMYAR_MISSING_NATIVE_ASSETS}, \"
        \"so the app in \${RAMYAR_BUNDLE_LIB_DIR} cannot open its database and will \"
        \"stop on its startup error screen. The Dart build hooks that compile them \"
        \"either did not run or ran and recorded nothing. Run 'flutter clean' in the \"
        \"project root and build again; if it still happens, build once with '-v' and \"
        \"look for the 'dart_build' and 'install_code_assets' targets.\")
    endif()
    " COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
# CONFIGURATIONS only filters with a multi-config generator; with the
# single-config Ninja generator it is ignored, so a Debug build would try to
# install an app.so that a debug build never produces and the install step
# would fail. Both are handled so either generator works.
if(IS_MULTICONFIG)
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    CONFIGURATIONS Profile;Release
    COMPONENT Runtime)
elseif(NOT "${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    COMPONENT Runtime)
endif()
