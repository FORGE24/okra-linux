cmake_minimum_required(VERSION 3.16)
project(kanina-installer VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

add_executable(kanina-installer src/main.cpp)
target_link_libraries(kanina-installer PRIVATE Qt6::Widgets)
install(TARGETS kanina-installer RUNTIME DESTINATION bin)
