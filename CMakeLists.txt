cmake_minimum_required(VERSION 3.16)
project(drac-util VERSION 1.0.0 LANGUAGES CXX)

include_directories("include")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (WIN32)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif ()

find_package(Threads REQUIRED)
find_package(Git QUIET)

set(IMGUI_PATH "${CMAKE_CURRENT_SOURCE_DIR}/external/imgui")
set(IMPLOT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/external/implot")
set(AMP1394_PATH "${CMAKE_CURRENT_SOURCE_DIR}/external/mechatronics-software")

set(DRACTEST_RELEASE_COMPONENT "dractest-runtime")
if (WIN32)
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION .)
  set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT ${DRACTEST_RELEASE_COMPONENT})
  include(InstallRequiredSystemLibraries)
endif ()

set(DRACTWEAK_GIT_SHA "unknown")
if (GIT_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.git")
  execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE DRACTWEAK_GIT_SHA
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
endif ()

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/dractest-release-readme.txt.in"
  "${CMAKE_CURRENT_BINARY_DIR}/README.txt"
  @ONLY
)


add_subdirectory("${AMP1394_PATH}")
set (CMAKE_PREFIX_PATH "${Amp1394_BINARY_DIR}" ${CMAKE_PREFIX_PATH})
find_package(Amp1394 REQUIRED)
include_directories("${Amp1394_INCLUDE_DIR};${Amp1394_BINARY_DIR}")
link_directories (${Amp1394_LIBRARY_DIR})

find_package(glfw3 REQUIRED)
include_directories(${GLFW_INCLUDE_DIRS})
# link_libraries(${GLFW_LIBRARY_DIRS})

cmake_policy (SET CMP0072 NEW)
find_package(OpenGL REQUIRED)
include_directories(${OPENGL_INCLUDE_DIRS})

find_package(GLEW REQUIRED)
include_directories(${GLEW_INCLUDE_DIRS})

add_executable(dractweak dractweak.cpp)


include_directories("${IMGUI_PATH};${IMGUI_PATH}/backends;${IMGUI_PATH}/misc/cpp")
include_directories("${IMPLOT_PATH}")

set(COMMON_FILES
"${IMGUI_PATH}/imgui.cpp"
"${IMGUI_PATH}/imgui_draw.cpp"
"${IMGUI_PATH}/imgui_demo.cpp"
"${IMGUI_PATH}/imgui_tables.cpp"
"${IMGUI_PATH}/imgui_widgets.cpp"
"${IMGUI_PATH}/backends/imgui_impl_opengl3.cpp"
"${IMGUI_PATH}/backends/imgui_impl_glfw.cpp"
"${IMGUI_PATH}/misc/cpp/imgui_stdlib.cpp"
"${IMPLOT_PATH}/implot.cpp"
"${IMPLOT_PATH}/implot_items.cpp"
)

target_sources(dractweak PUBLIC ${COMMON_FILES})
target_link_libraries(dractweak Amp1394 OpenGL::GL OpenGL::GLU glfw GLEW::GLEW Threads::Threads ${CMAKE_DL_LIBS})

add_executable(dractest dractest.cpp)
target_sources(dractest PUBLIC ${COMMON_FILES})
target_link_libraries(dractest Amp1394 OpenGL::GL OpenGL::GLU glfw GLEW::GLEW Threads::Threads ${CMAKE_DL_LIBS})

add_executable(dractune dractune.cpp)
target_sources(dractune PUBLIC ${COMMON_FILES})
target_link_libraries(dractune Amp1394 OpenGL::GL OpenGL::GLU glfw GLEW::GLEW Threads::Threads ${CMAKE_DL_LIBS})


install(TARGETS dractweak RUNTIME DESTINATION bin)
install(TARGETS dractest RUNTIME DESTINATION bin)
install(TARGETS dractune RUNTIME DESTINATION bin)

if (WIN32)
  install(
    TARGETS dractest
    RUNTIME DESTINATION .
    COMPONENT ${DRACTEST_RELEASE_COMPONENT}
  )
  install(
    FILES $<TARGET_RUNTIME_DLLS:dractest>
    DESTINATION .
    COMPONENT ${DRACTEST_RELEASE_COMPONENT}
  )
  install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/README.txt"
    DESTINATION .
    COMPONENT ${DRACTEST_RELEASE_COMPONENT}
  )

  set(DRACTEST_RELEASE_STAGE_DIR "${CMAKE_CURRENT_BINARY_DIR}/release/$<CONFIG>/dractest")
  set(DRACTEST_RELEASE_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/release/dractest-$<CONFIG>-windows-x64.zip")
  add_custom_target(
    dractest_package
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/release/$<CONFIG>"
    COMMAND ${CMAKE_COMMAND} -E remove_directory "${DRACTEST_RELEASE_STAGE_DIR}"
    COMMAND ${CMAKE_COMMAND} --install "${CMAKE_CURRENT_BINARY_DIR}" --config $<CONFIG> --component ${DRACTEST_RELEASE_COMPONENT} --prefix "${DRACTEST_RELEASE_STAGE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${DRACTEST_RELEASE_ARCHIVE}"
    COMMAND ${CMAKE_COMMAND} -E chdir "${CMAKE_CURRENT_BINARY_DIR}/release/$<CONFIG>" ${CMAKE_COMMAND} -E tar cf "${DRACTEST_RELEASE_ARCHIVE}" --format=zip dractest
    DEPENDS dractest
    COMMENT "Staging and zipping the dractest portable Windows release"
    VERBATIM
  )
endif ()
