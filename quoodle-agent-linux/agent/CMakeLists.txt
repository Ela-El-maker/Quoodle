add_executable(quoodle-agent-linux
    src/agent_main.cpp
    src/wss_client.cpp
    src/privileged_client.cpp
    src/outbox.cpp
    src/command_processor.cpp
    src/policy.cpp
    src/replay.cpp
    src/state_store.cpp
    src/crypto.cpp
    src/jcs.cpp
)

target_include_directories(quoodle-agent-linux PRIVATE include)
target_include_directories(quoodle-agent-linux PRIVATE third_party)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBSODIUM REQUIRED libsodium)
pkg_check_modules(OPENSSL REQUIRED openssl)
target_include_directories(quoodle-agent-linux PRIVATE ${LIBSODIUM_INCLUDE_DIRS})
target_include_directories(quoodle-agent-linux PRIVATE ${OPENSSL_INCLUDE_DIRS})
target_link_libraries(quoodle-agent-linux ${LIBSODIUM_LIBRARIES} ${OPENSSL_LIBRARIES})
