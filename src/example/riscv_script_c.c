#include "stdint.h"
#include "stddef.h"

//print function defined by our zig file
extern void zprint(const char* str);

//Native implementation of printf
extern void printf(const char* format, ...);
//Native implementation of puts
extern void puts(const char* string);

//Native function defined in our host program
extern void native_call(uint32_t x);

int funny_value = 21;

void mod_init() {
    printf("Hello from mod init from c!");

    native_call(0xf32);
}

void mod_deinit() {
    printf("Hello from mod deinit from c!");
}

int lol() {
    zprint("hello from c");

    funny_value = 3;

    int res = 0;

    for (int i = 0; i < 10; i++) {
        res = i;
    }

    native_call(res);

    int* ptr = 0;

    // *ptr = 10;

    printf("res = %i", res);
    printf("funny_value = %i", funny_value);
    printf("String Value = {'%s'}", "Hello, cstr!");

    return res;
}
