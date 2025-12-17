#include <iostream>
#include "../src/kernel/ioctl_client.hpp"

int main()
{
  IoctlClient client;
  auto res = client.ping("test-req-1");
  std::cout << "ping result: status=" << res.status << " result=" << res.result << " error=" << res.error_message << std::endl;

  auto res2 = client.lock_screen("test-req-2");
  std::cout << "lock_screen result: status=" << res2.status << " result=" << res2.result << " error=" << res2.error_message << std::endl;
  return 0;
}
