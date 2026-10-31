cmake_minimum_required(VERSION 3.21)
project(vgiv CXX)
if(WIN32)
  enable_language(RC)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

if(MINGW AND NOT EXISTS "${MINGW_DEPS_PREFIX}/lib/cmake/vsg/vsgConfig.cmake"
   AND NOT EXISTS "${MINGW_DEPS_PREFIX}/lib64/cmake/vsg/vsgConfig.cmake")
  # Cross build: vsg/vsgXchange/spdlog aren't packaged for MinGW; build them once.
  message(STATUS "Building MinGW dependencies (tools/build-mingw-deps.sh)...")
  execute_process(COMMAND ${CMAKE_COMMAND} -E env MINGW_DEPS_PREFIX=${MINGW_DEPS_PREFIX}
                          ${CMAKE_SOURCE_DIR}/tools/build-mingw-deps.sh
                  RESULT_VARIABLE _deps_rc)
  if(NOT _deps_rc EQUAL 0)
    message(FATAL_ERROR "tools/build-mingw-deps.sh failed")
  endif()
endif()
find_package(vsg CONFIG REQUIRED)
find_package(vsgXchange CONFIG REQUIRED)
# (before Qt6, whose cross config rewrites the find root path)
find_package(spdlog CONFIG REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Concurrent Network)

# The system-wide vsgQt install (/usr/local) was built against Qt5, so it
# can't be used by this (Qt6) app - vsgQt is a thin library, so build it
# from source against our own Qt6 + the system vsg instead of vendoring a
# Qt6 build of all of Qt itself via vcpkg.
include(FetchContent)
set(QT_PACKAGE_NAME Qt6 CACHE STRING "" FORCE)
# EXCLUDE_FROM_ALL keeps vsgQt's example apps and install rules out of the
# build/install (vgiv still builds the vsgQt library it links). Needs 3.28+.
set(VGIV_VSGQT_EXCLUDE "")
if(NOT CMAKE_VERSION VERSION_LESS 3.28)
  set(VGIV_VSGQT_EXCLUDE EXCLUDE_FROM_ALL)
endif()
FetchContent_Declare(vsgQt
  GIT_REPOSITORY https://github.com/vsg-dev/vsgQt.git
  GIT_TAG v0.4.0
  GIT_SHALLOW TRUE
  ${VGIV_VSGQT_EXCLUDE}
)
FetchContent_MakeAvailable(vsgQt)

# ---------------------------------------------------------------------------
# Shader compilation (GLSL -> SPIR-V) via glslangValidator
# ---------------------------------------------------------------------------
find_program(GLSLANG_VALIDATOR NAMES glslangValidator)
if(NOT GLSLANG_VALIDATOR)
  message(FATAL_ERROR "glslangValidator not found - required to compile shaders/*.vert/*.frag to SPIR-V")
endif()

set(VGIV_SHADER_SOURCES
  ${CMAKE_SOURCE_DIR}/shaders/marks.vert
  ${CMAKE_SOURCE_DIR}/shaders/marks.frag
  ${CMAKE_SOURCE_DIR}/shaders/marks_label.frag
  ${CMAKE_SOURCE_DIR}/shaders/lines.vert
  ${CMAKE_SOURCE_DIR}/shaders/lines.frag
  ${CMAKE_SOURCE_DIR}/shaders/fill.vert
  ${CMAKE_SOURCE_DIR}/shaders/fill.frag
  ${CMAKE_SOURCE_DIR}/shaders/image.vert
  ${CMAKE_SOURCE_DIR}/shaders/image.frag
  ${CMAKE_SOURCE_DIR}/shaders/grid.vert
  ${CMAKE_SOURCE_DIR}/shaders/grid.frag
)

set(VGIV_SPIRV_BINARIES)
foreach(shader ${VGIV_SHADER_SOURCES})
  get_filename_component(shader_name ${shader} NAME)
  set(spirv "${CMAKE_BINARY_DIR}/shaders/${shader_name}.spv")
  add_custom_command(
    OUTPUT ${spirv}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/shaders
    COMMAND ${GLSLANG_VALIDATOR} -V ${shader} -o ${spirv}
    DEPENDS ${shader}
    COMMENT "Compiling SPIR-V shader ${shader_name}"
  )
  list(APPEND VGIV_SPIRV_BINARIES ${spirv})
endforeach()

add_custom_target(vgiv_shaders DEPENDS ${VGIV_SPIRV_BINARIES})

# ---------------------------------------------------------------------------
# Third party
# ---------------------------------------------------------------------------
# EXCLUDE_FROM_ALL: QtAwesome installs its own library and CMake export set,
# which has no business landing in vgiv's install prefix. It still builds,
# since vgiv links it (used to theme the Open dialog's icons).
add_subdirectory(third_party/QtAwesome EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# Main executable
# ---------------------------------------------------------------------------
add_executable(vgiv
  src/main.cpp
  src/Logging.cpp
  src/GivColor.cpp
  src/GivParser.cpp
  src/GivThumbnailRenderer.cpp
  src/SvgLoader.cpp
  src/SceneBuilder.cpp
  src/CaliperTool.cpp
  src/PanZoomHandler.cpp
  src/LabelPicker.cpp
  src/BalloonController.cpp
  src/ImagePluginHost.cpp
  src/Colormaps.cpp
  src/ExifReader.cpp
  src/DisplayImage.cpp
  src/qt/GivViewer.cpp
  src/qt/VulkanViewport.cpp
  src/qt/PreferencesDialog.cpp
  src/qt/CalibrateDialog.cpp
  src/qt/ColorMapBar.cpp
  src/qt/HistogramWidget.cpp
  src/qt/ContrastPanel.cpp
  src/qt/InfoPanel.cpp
  src/qt/ColorTablePanel.cpp
  src/qt/MainWindow.cpp
  src/qt/MarkTreeView.cpp
  src/qt/OpenFileDialog.cpp
  src/qt/RpcServer.cpp
  resources/vgiv.qrc
)
if(WIN32)
  # vgiv.rc embeds the app icon (id 1) and the .giv file icon (id 2).
  target_sources(vgiv PRIVATE src/qt/WinDropTarget.cpp resources/vgiv.rc resources/vgiv.manifest)
  # rc.exe doesn't report include dependencies; without this, editing an
  # icon doesn't rebuild the resource and the exe keeps the stale icon.
  set_source_files_properties(resources/vgiv.rc PROPERTIES
    OBJECT_DEPENDS
      "${CMAKE_SOURCE_DIR}/resources/vgiv-logo.ico;${CMAKE_SOURCE_DIR}/resources/file-giv-logo.ico")
  target_link_libraries(vgiv PRIVATE ole32 shell32 uuid)
endif()

add_dependencies(vgiv vgiv_shaders)

target_include_directories(vgiv PRIVATE src ${CMAKE_SOURCE_DIR}/third_party)
target_link_libraries(vgiv PRIVATE vsg::vsg vsgXchange::vsgXchange vsgQt::vsgQt Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Concurrent Qt6::Network QtAwesome spdlog::spdlog)

# Version / commit info shown in Help > About. Generated at BUILD time by an
# always-out-of-date target (the header is rewritten only when it changes), so
# a new commit rebuilds just BuildInfo.cpp - no reconfigure needed.
file(READ ${CMAKE_SOURCE_DIR}/vcpkg.json _vcpkg_json)
string(JSON VGIV_VERSION GET "${_vcpkg_json}" version)
set(VGIV_BUILDINFO_HEADER ${CMAKE_BINARY_DIR}/generated/BuildInfo_gen.h)
add_custom_target(vgiv_buildinfo
  COMMAND ${CMAKE_COMMAND}
    -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
    -DHEADER_PATH=${VGIV_BUILDINFO_HEADER}
    -DVERSION=${VGIV_VERSION}
    -P ${CMAKE_SOURCE_DIR}/cmake/GenBuildInfo.cmake
  BYPRODUCTS ${VGIV_BUILDINFO_HEADER}
  COMMENT "Updating build info header"
  VERBATIM)
set_source_files_properties(src/BuildInfo.cpp PROPERTIES OBJECT_DEPENDS ${VGIV_BUILDINFO_HEADER})
target_sources(vgiv PRIVATE src/BuildInfo.cpp)
target_include_directories(vgiv PRIVATE ${CMAKE_BINARY_DIR}/generated)
add_dependencies(vgiv vgiv_buildinfo)

target_compile_definitions(vgiv PRIVATE
  VGIV_SHADER_DIR="${CMAKE_BINARY_DIR}/shaders"
  VGIV_PLUGIN_DIR="${CMAKE_BINARY_DIR}/plugins"
)

if(UNIX AND NOT APPLE)
  target_link_libraries(vgiv PRIVATE pthread ${CMAKE_DL_LIBS})
endif()

if(WIN32)
  # GUI subsystem: no console window. Keep the plain main() entry point
  # instead of requiring WinMain.
  set_target_properties(vgiv PROPERTIES WIN32_EXECUTABLE TRUE)
  if(MSVC)
    target_link_options(vgiv PRIVATE /ENTRY:mainCRTStartup)
  else()
    target_link_options(vgiv PRIVATE -Wl,-subsystem,windows -Wl,-e,mainCRTStartup)
  endif()
endif()


if(WIN32)
  # Qt needs its platform plugin next to the exe (vcpkg's applocal step only
  # copies DLLs linked at build time, not runtime-loaded plugins).
  if(MINGW)
    # Cross build with Fedora's mingw64-qt6-qtbase: <sysroot>/lib/qt6/plugins.
    find_file(VGIV_QWINDOWS_PLUGIN qwindows.dll
      PATHS ${CMAKE_FIND_ROOT_PATH} ${CMAKE_PREFIX_PATH}
      PATH_SUFFIXES lib/qt6/plugins/platforms plugins/platforms
      NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
  else()
    find_file(VGIV_QWINDOWS_PLUGIN qwindows.dll
      PATHS ${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/Qt6/plugins/platforms
      NO_DEFAULT_PATH)
  endif()
  add_custom_command(TARGET vgiv POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_FILE_DIR:vgiv>/platforms
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${VGIV_QWINDOWS_PLUGIN} $<TARGET_FILE_DIR:vgiv>/platforms/
  )
endif()
if(WIN32)
  # Installed layout (see AppPaths.h): bin/ holds vgiv.exe, every runtime DLL
  # that vcpkg's applocal step put in the build tree and Qt's platforms/
  # plugin dir; shaders in share/vgiv/, image plugins in lib/vgiv/plugins/
  # (installed by src/plugins), examples/ at the top. The NSIS installer
  # (Installers/) packages this prefix.
  install(TARGETS vgiv RUNTIME DESTINATION bin)
  install(DIRECTORY ${CMAKE_BINARY_DIR}/shaders DESTINATION share/vgiv)
  install(DIRECTORY ${CMAKE_SOURCE_DIR}/examples/ DESTINATION examples)
  install(CODE "
    file(GLOB _vgiv_dlls \"${CMAKE_BINARY_DIR}/*.dll\")
    file(INSTALL \${_vgiv_dlls} DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\")
    # Third-party DLLs the image plugins depend on (cfitsio, tiff, ...) land
    # in plugins/ next to the plugins themselves; install them into bin/,
    # where ImagePluginHost adds the exe directory to the DLL search path.
    file(GLOB _vgiv_plugin_deps \"${CMAKE_BINARY_DIR}/plugins/*.dll\")
    list(FILTER _vgiv_plugin_deps EXCLUDE REGEX \"/vgiv_[^/]*\$\")
    file(INSTALL \${_vgiv_plugin_deps} DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\")
    file(INSTALL \"${CMAKE_BINARY_DIR}/platforms/qwindows.dll\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin/platforms\")
  ")
  # App-local MSVC runtime, so no separate vc_redist install is needed.
  # (MinGW cross builds: tools/build-mingw.sh copies the DLLs instead.)
  if(MSVC)
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
    include(InstallRequiredSystemLibraries)
  endif()
else()
  install(TARGETS vgiv RUNTIME DESTINATION bin)
  install(DIRECTORY ${CMAKE_BINARY_DIR}/shaders DESTINATION share/vgiv)
  install(DIRECTORY ${CMAKE_SOURCE_DIR}/examples/ DESTINATION share/vgiv/examples)
endif()

# ---------------------------------------------------------------------------
# Image-format plugins (dlopen-loaded .so files, see src/ImagePluginHost)
# ---------------------------------------------------------------------------
add_subdirectory(src/plugins)
