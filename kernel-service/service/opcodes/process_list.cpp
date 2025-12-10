#include <vector>
#include <string>

std::vector<std::string> execute_process_list(bool include_cmdline) {
    (void)include_cmdline;
    return {"explorer.exe", "agent.exe"};
}
