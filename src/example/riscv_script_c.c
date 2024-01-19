
//print function defined by our zig file
extern void zprint(const char* str);

int lol() {
    zprint("hello from c");

    return 4;
}
