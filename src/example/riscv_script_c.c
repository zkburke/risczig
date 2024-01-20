#include "stdint.h"
#include "stddef.h"

//print function defined by our zig file
extern void zprint(const char* str);

//Native implementation of printf
extern void printf(const char* format, ...);
//Native implementation of puts
extern void puts(const char* string);

//Native function defined in our host program
extern void testNativeCall(uint32_t x);

int funny_value = 21;

int lol() {
    zprint("hello from c");

    puts("Hello printf!");

    int res = 0;

    for (int i = 0; i < 10; i++) {
        testNativeCall(i);

        res = i;
    }

    puts("res = %i");

    return res;
}
