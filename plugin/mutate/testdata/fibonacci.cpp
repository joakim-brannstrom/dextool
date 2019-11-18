/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Niklas Pettersson (nikpe353@student.liu.se)
*/

int fibonacci(int x){
    if(x < 0){
        return -1;
    }
    if (x == 0){
        return 0;
    }
    if (x == 1){
        return 1;
    }
    return fibonacci(x-1)+fibonacci(x-2);
}
