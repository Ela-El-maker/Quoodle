cmake_minimum_required(VERSION 3.16)
project(quoodle-agent-windows LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(WIN32)
  # Prevent Windows headers from defining min/max macros that break std::min/std::max.
  add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
endif()

# Dangerous: runtime exec fallback option (disabled by default). Set ON only for debugging.
option(ENABLE_EXEC_FALLBACK "Enable exec fallback (dangerous)" OFF)
# Prevent accidental fallback in Release builds
string(TOUPPER "${CMAKE_BUILD_TIME}" BUILD_TYPE_UPPER)
if(ENABLE_EXEC_FALLBACK AND BUILD_TYPE_UPPER STREQUAL "RELEASE")
    message(FATAL_ERROR "Security Gate: ENABLE_EXEC_FALLBACK cannot be enabled in RELEASE mode!")
endif()

if(ENABLE_EXEC_FALLBACK)
  message(WARNING "ENABLE_EXEC_FALLBACK is ON. This allows the agent to exec the kernel_service binary as a fallback — do not enable in production.")
  add_compile_definitions(ENABLE_EXEC_FALLBACK=1)
endif()

# libsodium is required for Ed25519 signing/verification.
# If a system package is unavailable, attempt to build bundled libsodium on Windows.
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
    URL https://codeload.github.com/jedisct1/libsodium/tar.gz/refs/heads/stable
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(libsodium)

  if(WIN32)
    set(_sodium_vs_dir "")
    if(CMAKE_GENERATOR MATCHES "Visual Studio 18")
      set(_sodium_vs_dir "vs2026")
    elseif(CMAKE_GENERATOR MATCHES "Visual Studio 17")
      set(_sodium_vs_dir "vs2022")
    elseif(CMAKE_GENERATOR MATCHES "Visual Studio 16")
      set(_sodium_vs_dir "vs2019")
    elseif(CMAKE_GENERATOR MATCHES "Visual Studio 15")
      set(_sodium_vs_dir "vs2017")
    endif()

    if(_sodium_vs_dir)
      set(_sodium_sln "${libsodium_SOURCE_DIR}/builds/msvc/${_sodium_vs_dir}/libsodium.sln")
      if(EXISTS "${_sodium_sln}")
        if(CMAKE_VS_PLATFORM_NAME)
          set(_sodium_platform "${CMAKE_VS_PLATFORM_NAME}")
        else()
          set(_sodium_platform "x64")
        endif()

        set(_msbuild_cmd "${CMAKE_VS_MSBUILD_COMMAND}")
        if(NOT _msbuild_cmd)
          set(_msbuild_cmd "MSBuild.exe")
        endif()

        message(STATUS "Building bundled libsodium (${_sodium_vs_dir}, ${_sodium_platform})")
        execute_process(
          COMMAND "${_msbuild_cmd}" "${_sodium_sln}" /m /t:Build "/p:Configuration=StaticRelease" "/p:Platform=${_sodium_platform}"
          RESULT_VARIABLE _sodium_build_rc
        )

        if(_sodium_build_rc EQUAL 0)
          file(GLOB_RECURSE _sodium_lib_candidates
            "${libsodium_SOURCE_DIR}/bin/${_sodium_platform}/Release/*/static/libsodium.lib"
            "${libsodium_SOURCE_DIR}/builds/msvc/bin/${_sodium_platform}/Release/*/static/libsodium.lib")
          list(LENGTH _sodium_lib_candidates _sodium_lib_count)
          if(_sodium_lib_count GREATER 0)
            list(GET _sodium_lib_candidates 0 SODIUM_LIB)
            set(SODIUM_INCLUDE_DIR "${libsodium_SOURCE_DIR}/src/libsodium/include")
            set(HAVE_SODIUM 1)
            message(STATUS "Using bundled libsodium: ${SODIUM_LIB}")
          else()
            message(WARNING "Bundled libsodium build succeeded, but libsodium.lib was not found.")
          endif()
        else()
          message(WARNING "Bundled libsodium build failed with code: ${_sodium_build_rc}")
        endif()
      endif()
    endif()
  endif()
endif()

if(NOT HAVE_SODIUM)
  message(FATAL_ERROR "libsodium is required for Ed25519 auth/signature support. Install libsodium or use a supported Visual Studio generator (17/18) so bundled libsodium can be built.")
endif()

include(FetchContent)

# ixwebsocket enables zlib by default and hard-requires a host zlib package.
# For local Windows E2E builds we keep transport simple and disable zlib to
# avoid an external dependency that is not otherwise needed.
set(USE_ZLIB OFF CACHE BOOL "Disable ixwebsocket zlib support" FORCE)
set(IXWEBSOCKET_INSTALL OFF CACHE BOOL "Disable ixwebsocket install target in superbuild" FORCE)

FetchContent_Declare(
  ixwebsocket
  URL https://codeload.github.com/machinezone/IXWebSocket/tar.gz/refs/tags/v11.4.6
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

# SQLite3 for persistent queue
find_package(SQLite3)
if(NOT SQLite3_FOUND)
  FetchContent_Declare(
    sqlite3
    URL https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(sqlite3)
  add_library(sqlite3_lib STATIC ${sqlite3_SOURCE_DIR}/sqlite3.c)
  target_include_directories(sqlite3_lib PUBLIC ${sqlite3_SOURCE_DIR})
  set(SQLITE3_LIB sqlite3_lib)
  set(SQLITE3_INCLUDE_DIR ${sqlite3_SOURCE_DIR})
else()
  set(SQLITE3_LIB SQLite::SQLite3)
  set(SQLITE3_INCLUDE_DIR ${SQLite3_INCLUDE_DIRS})
endif()

FetchContent_MakeAvailable(ixwebsocket)
FetchContent_MakeAvailable(nlohmann_json)

add_executable(agent
  src/main.cpp
  src/agent_state.hpp
  src/logging/logger.hpp
  src/ota/ota_manager.hpp
  src/quarantine/quarantine_manager.hpp
  src/recovery/recovery_manager.hpp
  src/telemetry/telemetry_collector.cpp
  src/telemetry/telemetry_queue.cpp
  src/telemetry/telemetry_http_client.cpp
  src/crypto/ed25519_sign.cpp
  src/crypto/ed25519_verify.cpp
  src/crypto/command_verifier.cpp
  src/crypto/json_canonicalizer.cpp
  src/crypto/kernel_response_verifier.cpp
  src/ws/ws_client.cpp
  src/ws/ws_protocol.cpp
  src/ws/sequence_manager.cpp
  src/utils/json_canonicalizer.cpp
  src/utils/sha256.cpp
  src/kernel/ioctl_client.cpp
  src/kernel/opcodes/collect_system_info_codec.cpp
  src/kernel/opcodes/basic_control_opcodes.cpp
  src/kernel/opcodes/opcode_map.cpp
  src/kernel/kernel_event_listener.cpp
  src/utils/dpapi_loader.cpp
  src/storage/sqlite_queue.cpp
)

target_include_directories(agent PRIVATE src ${SQLITE3_INCLUDE_DIR})
target_link_libraries(agent PRIVATE ixwebsocket::ixwebsocket nlohmann_json::nlohmann_json ${SQLITE3_LIB})
# Link Windows-specific system libraries used by telemetry and networking
if(WIN32)
  target_link_libraries(agent PRIVATE pdh iphlpapi crypt32 advapi32 winhttp)
endif()
if(HAVE_SODIUM)
  target_include_directories(agent PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(agent PRIVATE ${SODIUM_LIB})
  target_compile_definitions(agent PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

# Local harness for strict device-side collect_system_info soak validation.
add_executable(collect_system_info_soak
  src/tools/collect_system_info_soak.cpp
  src/kernel/ioctl_client.cpp
  src/kernel/opcodes/collect_system_info_codec.cpp
  src/kernel/opcodes/basic_control_opcodes.cpp
  src/kernel/opcodes/opcode_map.cpp
  src/crypto/ed25519_sign.cpp
  src/crypto/json_canonicalizer.cpp
  src/crypto/kernel_response_verifier.cpp
  src/utils/sha256.cpp
  src/utils/dpapi_loader.cpp
)
target_include_directories(collect_system_info_soak PRIVATE src)
target_link_libraries(collect_system_info_soak PRIVATE nlohmann_json::nlohmann_json)
if(WIN32)
  target_link_libraries(collect_system_info_soak PRIVATE iphlpapi crypt32 advapi32)
endif()
if(HAVE_SODIUM)
  target_include_directories(collect_system_info_soak PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(collect_system_info_soak PRIVATE ${SODIUM_LIB})
  target_compile_definitions(collect_system_info_soak PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

# Integration tests
add_executable(ioctl_integration_test
  tests/integration/ioctl_pipe_test.cpp
  src/kernel/ioctl_client.cpp
  src/kernel/opcodes/collect_system_info_codec.cpp
  src/kernel/opcodes/basic_control_opcodes.cpp
  src/kernel/opcodes/opcode_map.cpp
  src/crypto/kernel_response_verifier.cpp
  src/utils/sha256.cpp
)

add_executable(ioctl_signed_test
  tests/integration/ioctl_signed_test.cpp
  src/kernel/ioctl_client.cpp
  src/kernel/opcodes/collect_system_info_codec.cpp
  src/kernel/opcodes/basic_control_opcodes.cpp
  src/kernel/opcodes/opcode_map.cpp
  src/crypto/ed25519_sign.cpp
  src/crypto/json_canonicalizer.cpp
  src/crypto/kernel_response_verifier.cpp
  src/utils/sha256.cpp
  src/utils/dpapi_loader.cpp
)

add_executable(ws_protocol_signing_test
  tests/unit/ws_protocol_signing_test.cpp
  src/ws/ws_protocol.cpp
  src/ws/sequence_manager.cpp
  src/crypto/ed25519_sign.cpp
  src/crypto/json_canonicalizer.cpp
  src/telemetry/telemetry_collector.cpp
  src/utils/json_canonicalizer.cpp
  src/utils/dpapi_loader.cpp
)

target_include_directories(ioctl_integration_test PRIVATE src)
target_link_libraries(ioctl_integration_test PRIVATE nlohmann_json::nlohmann_json)
if(WIN32)
  target_link_libraries(ioctl_integration_test PRIVATE iphlpapi advapi32)
endif()
if(HAVE_SODIUM)
  target_include_directories(ioctl_integration_test PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(ioctl_integration_test PRIVATE ${SODIUM_LIB})
  target_compile_definitions(ioctl_integration_test PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

target_link_libraries(ioctl_signed_test PRIVATE nlohmann_json::nlohmann_json)
if(WIN32)
  target_link_libraries(ioctl_signed_test PRIVATE iphlpapi advapi32)
endif()
if(HAVE_SODIUM)
  target_include_directories(ioctl_signed_test PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(ioctl_signed_test PRIVATE ${SODIUM_LIB})
  target_compile_definitions(ioctl_signed_test PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

target_include_directories(ws_protocol_signing_test PRIVATE src)
target_link_libraries(ws_protocol_signing_test PRIVATE nlohmann_json::nlohmann_json)
if(WIN32)
  target_link_libraries(ws_protocol_signing_test PRIVATE pdh iphlpapi crypt32)
endif()
if(HAVE_SODIUM)
  target_include_directories(ws_protocol_signing_test PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(ws_protocol_signing_test PRIVATE ${SODIUM_LIB})
  target_compile_definitions(ws_protocol_signing_test PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

# Task 1.7: End-to-end signature chain integration test
add_executable(e2e_signature_chain_test
  tests/integration/e2e_signature_chain_test.cpp
)
target_include_directories(e2e_signature_chain_test PRIVATE src)
if(HAVE_SODIUM)
  target_include_directories(e2e_signature_chain_test PRIVATE ${SODIUM_INCLUDE_DIR})
  target_link_libraries(e2e_signature_chain_test PRIVATE ${SODIUM_LIB})
  target_compile_definitions(e2e_signature_chain_test PRIVATE HAVE_SODIUM=1 SODIUM_STATIC=1)
endif()

# Task 2.4: SQLite queue unit tests
add_executable(sqlite_queue_test
  tests/unit/sqlite_queue_test.cpp
  src/storage/sqlite_queue.cpp
)
target_include_directories(sqlite_queue_test PRIVATE src ${SQLITE3_INCLUDE_DIR})
target_link_libraries(sqlite_queue_test PRIVATE ${SQLITE3_LIB})

include(CTest)
enable_testing()
add_test(NAME ioctl_integration_test COMMAND ioctl_integration_test)
add_test(NAME ioctl_signed_test COMMAND ioctl_signed_test)
add_test(NAME ws_protocol_signing_test COMMAND ws_protocol_signing_test)
add_test(NAME e2e_signature_chain_test COMMAND e2e_signature_chain_test)
add_test(NAME sqlite_queue_test COMMAND sqlite_queue_test)

