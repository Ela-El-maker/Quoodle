cmake_minimum_required(VERSION 3.16)
project(windows-agent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

FetchContent_Declare(
  ixwebsocket
  GIT_REPOSITORY https://github.com/machinezone/IXWebSocket.git
  GIT_TAG v11.1.8
)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
)

FetchContent_MakeAvailable(ixwebsocket)
FetchContent_MakeAvailable(nlohmann_json)

add_executable(agent
  src/main.cpp
  src/ws/ws_client.cpp
  src/ws/ws_protocol.cpp
  src/utils/json_canonicalizer.cpp
  src/kernel/ioctl_client.cpp
)

target_include_directories(agent PRIVATE src)
target_link_libraries(agent PRIVATE ixwebsocket::ixwebsocket nlohmann_json::nlohmann_json)
