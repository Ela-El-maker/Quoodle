#include <cassert>
#include "../service/opcodes/ping.cpp"
#include "../service/opcodes/lock_screen.cpp"

int main() {
    assert(execute_ping() == "pong");
    assert(execute_lock_screen());
    return 0;
}
