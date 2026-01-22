add_executable(quoodle-privileged-daemon
    src/daemon_main.c
    src/uds_server.c
    src/executor.c
    src/jcs.c
    src/crypto.c
    src/state_store.c
    third_party/cjson/cJSON.c
)

target_include_directories(quoodle-privileged-daemon PRIVATE include)
target_include_directories(quoodle-privileged-daemon PRIVATE third_party/cjson)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBSODIUM REQUIRED libsodium)
target_include_directories(quoodle-privileged-daemon PRIVATE ${LIBSODIUM_INCLUDE_DIRS})
target_link_libraries(quoodle-privileged-daemon ${LIBSODIUM_LIBRARIES} m)
