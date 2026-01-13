#include <cassert>
#include "../service/validation/schema_validator.hpp"

int main() {
    std::vector<validation::ValidationError> errors;
    bool ok = validation::validate_request_schema("EXEC_LOCK_SCREEN", "{}", errors);
    assert(ok);
    return 0;
}
