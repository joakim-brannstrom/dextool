/** @file main.cpp
 * @brief Functional testing of C++ test doubles.
 * @author Joakim Brännström (joakim.brannstrom@gmx.com)
 * @date 2015
 * @copyright GNU Licence
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include <iostream>
#include <assert.h>

#ifdef TEST_INCLUDE
#include "test_double.hpp"
#endif

#define start_test() do{std::cout << " # " <<  __func__ << "\t\t" << __FILE__ << ":" << __LINE__ << std::endl;}while(0)
#define msg(x) do{std::cout << __FILE__ << ":" << __LINE__ << " " << x << std::endl;}while(0)

void devtest() {
    start_test();
}

int main(int argc, char** argv) {
    std::cout << "functional testing" << std::endl;

    devtest();

    return 0;
}
