#include <algorithm>
#include <sycl/sycl.hpp>

int main() {
  sycl::queue q;
  std::cout << q.get_device().get_info<sycl::info::device::name>() << "\n";
  sycl::range<1> r{128};
  sycl::buffer<int, 1> b{r};
  q.submit([&](sycl::handler& h) {
    auto a = b.get_access(h);
    h.parallel_for(r, [=](sycl::item<> i) {
      a[i] = i;
    });
  });
  auto fail = false;
  {
    auto a = b.get_host_access();
    for(auto i = 0; i < r.size(); i++) {
      if (a[i] != i) {
        std::cerr << "Failure in device calcuation\n"
                  << "a[" << i << "] = " << a[i] << "\n";
        fail |= true;
      }
    }
  }
  return fail;
}

