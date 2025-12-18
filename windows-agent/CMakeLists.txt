cmake_minimum_required(VERSION 3.16)
project(windows-agent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Try to locate libsodium for Ed25519 support (optional)
find_path(SODIUM_INCLUDE_DIR sodium.h)
find_library(SODIUM_LIB sodium)
if(SODIUM_INCLUDE_DIR AND SODIUM_LIB)
  message(STATUS "Found libsodium for Ed25519 support")
  set(HAVE_SODIUM 1)
endif()

include(FetchContent)

FetchContent_Declare(
  ixwebsocket
  GIT_REPOSITORY https://github.com/machinezone/IXWebSocket.git
  GIT_TAG v11.4.6
)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.12.0
)

FetchContent_MakeAvailable(ixwebsocket)
FetchContent_MakeAvailable(nlohmann_json)

add_executable(agent
  src/main.cpp
  src/agent_state.hpp
  src/logging/logger.hpp
  src/ota/ota_manager.hpp
  src/quarantine/quarantine_manager.hpp
  src/recovery/recovery_manager.hpp
  src/ws/ws_client.cpp
  src/ws/ws_protocol.cpp
  src/utils/json_canonicalizer.cpp
  src/utils/sha256.cpp
  src/kernel/ioctl_client.cpp
)

target_include_directories(agent PRIVATE src)
target_link_libraries(agent PRIVATE ixwebsocket::ixwebsocket nlohmann_json::nlohmann_json)
if(HAVE_SODIUM)
  target_include_directories(agent PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(agent PRIVATE ${SODIUM_LIB})
  target_compile_definitions(agent PRIVATE HAVE_SODIUM=1)
endif()

# Integration tests
add_executable(ioctl_integration_test
  tests/integration/ioctl_pipe_test.cpp
  src/kernel/ioctl_client.cpp
  src/utils/sha256.cpp
)

target_include_directories(ioctl_integration_test PRIVATE src)
if(HAVE_SODIUM)
  target_include_directories(ioctl_integration_test PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(ioctl_integration_test PRIVATE ${SODIUM_LIB})
  target_compile_definitions(ioctl_integration_test PRIVATE HAVE_SODIUM=1)
endif()

include(CTest)
enable_testing()
add_test(NAME ioctl_integration_test COMMAND ioctl_integration_test)

