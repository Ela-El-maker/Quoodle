cmake_minimum_required(VERSION 3.16)
project(kernel_service LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optional libsodium for Ed25519 signing/verification
find_path(SODIUM_INCLUDE_DIR sodium.h)
find_library(SODIUM_LIB sodium)
if(SODIUM_INCLUDE_DIR AND SODIUM_LIB)
    message(STATUS "Found libsodium for Ed25519 support")
    set(HAVE_SODIUM 1)
endif()
if(NOT HAVE_SODIUM)
    include(FetchContent)
    FetchContent_Declare(
        libsodium
        GIT_REPOSITORY https://github.com/jedisct1/libsodium.git
        GIT_TAG stable
    )
    FetchContent_MakeAvailable(libsodium)
    if(TARGET libsodium)
        set(SODIUM_LIB libsodium)
        set(SODIUM_INCLUDE_DIR ${libsodium_SOURCE_DIR}/src/libsodium/include)
        set(HAVE_SODIUM 1)
    endif()
endif()

add_library(kernel_service STATIC
    service/main.cpp
    service/dispatcher.cpp
    service/crypto/ed25519_verify_wrapper.cpp
    service/crypto/ed25519_wrapper.cpp
    service/utils/dpapi_loader.cpp
    service/opcodes/lock_screen.cpp
    service/opcodes/ping.cpp
    service/opcodes/stage_update.cpp
    service/opcodes/commit_update.cpp
    service/opcodes/tamper_check.cpp
    service/opcodes/process_list.cpp
    service/opcodes/logout.cpp
    service/opcodes/reboot.cpp
    service/opcodes/shutdown.cpp
    service/utils/logger.cpp
    service/utils/json_canonicalizer.cpp
)

target_include_directories(kernel_service PUBLIC service)
if(HAVE_SODIUM)
    target_include_directories(kernel_service PUBLIC ${SODIUM_INCLUDE_DIR})
    target_link_libraries(kernel_service PUBLIC ${SODIUM_LIB})
    target_compile_definitions(kernel_service PUBLIC HAVE_SODIUM=1)
endif()
if(WIN32)
    target_link_libraries(kernel_service PUBLIC crypt32)
endif()
