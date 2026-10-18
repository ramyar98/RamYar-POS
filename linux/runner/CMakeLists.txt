cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Embed the application icon in the binary as a GResource so the window and
# taskbar icon are available no matter how the app is launched. The generated
# source is plain C, compiled here as C++ (the runner project only enables
# the CXX language).
set(ICON_RESOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/resources")
set(ICON_RESOURCE_XML "${ICON_RESOURCE_DIR}/my_application_icon.gresource.xml")
set(ICON_GENERATED_C "${CMAKE_CURRENT_BINARY_DIR}/my_application_icon.c")

add_custom_command(
  OUTPUT "${ICON_GENERATED_C}"
  COMMAND glib-compile-resources
          --sourcedir "${ICON_RESOURCE_DIR}"
          --generate-source
          --target "${ICON_GENERATED_C}"
          "${ICON_RESOURCE_XML}"
  DEPENDS "${ICON_RESOURCE_XML}"
          "${ICON_RESOURCE_DIR}/my_application_icon.png"
)

add_custom_target(icon_resources DEPENDS "${ICON_GENERATED_C}")
add_dependencies(${BINARY_NAME} icon_resources)

set_source_files_properties("${ICON_GENERATED_C}" PROPERTIES LANGUAGE CXX)
target_sources(${BINARY_NAME} PRIVATE "${ICON_GENERATED_C}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
