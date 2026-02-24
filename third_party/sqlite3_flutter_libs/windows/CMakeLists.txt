cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlite3_flutter_libs")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "sqlite3_flutter_libs_plugin")

# Essentially, the idea of this build script is to compile a sqlite3.dll
# and make Fluter bundle that with the final app.
# It looks like we can't avoid building a sqlite3_flutter_libs.dll too,
# but that's not on me.

add_library(${PLUGIN_NAME} SHARED
  "sqlite3_flutter_libs_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(_winsqlite3 "$ENV{SystemRoot}/System32/winsqlite3.dll")
if (NOT EXISTS "${_winsqlite3}")
  message(FATAL_ERROR "winsqlite3.dll not found at ${_winsqlite3}.")
endif()

set(_sqlite3_dll "${CMAKE_CURRENT_BINARY_DIR}/sqlite3.dll")
add_custom_command(
  OUTPUT "${_sqlite3_dll}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_winsqlite3}" "${_sqlite3_dll}"
  DEPENDS "${_winsqlite3}"
)

add_custom_target(sqlite3_copy ALL DEPENDS "${_sqlite3_dll}")
add_dependencies(${PLUGIN_NAME} sqlite3_copy)

# List of absolute paths to libraries that should be bundled with the plugin
set(sqlite3_flutter_libs_bundled_libraries
  "${_sqlite3_dll}"
  PARENT_SCOPE
)
