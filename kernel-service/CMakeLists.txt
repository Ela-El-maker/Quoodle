cmake_minimum_required(VERSION 3.16)
project(kernel_service LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(kernel_service STATIC
    service/main.cpp
    service/dispatcher.cpp
    service/opcodes/lock_screen.cpp
    service/opcodes/ping.cpp
    service/utils/logger.cpp
)

target_include_directories(kernel_service PUBLIC service)
