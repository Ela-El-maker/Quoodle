cmake_minimum_required(VERSION 3.16)
project(quoodle_agent_linux LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

add_subdirectory(agent)
add_subdirectory(privileged)
