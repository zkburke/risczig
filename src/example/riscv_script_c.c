
//print function defined by our zig file
extern void zprint(const char* str);

int funny_value = 21;

int lol() {
    zprint("hello from c");

    return 4;
}
