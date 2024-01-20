//!Loader implementation for the elf file format

pub const Loaded = struct {
    image: []u8,
    entry_point: usize,
    stack: []u8,
};

///TODO: implement loader using mmap as a specialisation for loading files.
///Both loading from a file and from memory should work
pub fn load(
    allocator: std.mem.Allocator,
    elf_data: []const u8,
    //ComptimeStringMap(NativeCall, .{...})
    native_procedures: anytype,
) !Loaded {
    const header: *const ElfHeader = @ptrCast(elf_data.ptr);

    std.debug.assert(std.mem.eql(u8, &header.magic, "\x7fELF"));

    std.debug.assert(header.version == .current);
    std.debug.assert(header.abi == .systemv);
    std.debug.assert(header.class == .@"64bit");
    std.debug.assert(header.endianness == .little);
    std.debug.assert(header.machine == .riscv);
    std.debug.assert(header.type == .exec or header.type == .dyn);

    //TODO: support compressed instructions
    std.debug.assert(!header.flags.riscv_rvc);

    std.log.info("elf_header = {}", .{header.*});

    const program_header_start: [*]const ProgramHeader = @ptrCast(elf_data.ptr + header.e_phoff);

    const program_headers = program_header_start[0..header.e_phnum];

    for (program_headers) |program_header| {
        std.log.info("prog header: {}\n", .{program_header});
    }

    //size of the image mapped in memory
    var image_size: usize = 0;

    var minimum_virtual_address: usize = std.math.maxInt(usize);

    for (program_headers) |program_header| {
        switch (program_header.type) {
            .load => {
                minimum_virtual_address = @min(minimum_virtual_address, program_header.vaddr);

                image_size = @max(image_size, program_header.vaddr) - minimum_virtual_address;
                image_size += program_header.memsz;
            },
            else => {},
        }
    }

    std.debug.assert(minimum_virtual_address != std.math.maxInt(usize));

    std.log.info("minimum_virtual_address = {}", .{minimum_virtual_address});

    const image = allocator.rawAlloc(image_size, 32, @returnAddress()).?;
    errdefer allocator.free(image[0..image_size]);

    @memset(image[0..image_size], undefined);

    var stack_alignment: usize = 0;
    var stack_size: usize = 100 * 1024;

    for (program_headers) |program_header| {
        switch (program_header.type) {
            .load => {
                const program_header_data = elf_data[program_header.offset .. program_header.offset + program_header.filesz];

                const base_address = program_header.vaddr - minimum_virtual_address;

                @memcpy(image[base_address .. base_address + program_header_data.len], program_header_data);

                const rest_size = program_header.memsz - program_header.filesz;

                @memset(image[base_address + program_header_data.len .. base_address + program_header_data.len + rest_size], 0);
            },
            .dynamic => {
                //parse dynamic symbols

                const dynamic_section = elf_data[program_header.offset .. program_header.offset + program_header.filesz];

                const values_ptr: [*]const Dyn = @alignCast(@ptrCast(dynamic_section));
                const values = values_ptr[0 .. dynamic_section.len / @sizeOf(Dyn)];

                var relocation_table_size: usize = 0;

                var symbol_table: ?[*]const Sym = null;
                var string_table: ?[*]const u8 = null;
                var gnu_hash_table: ?[*]const u32 = null;

                for (values) |value| {
                    std.log.info("value: tag = {}, val = 0x{x}", .{ value.tag, value.val });

                    switch (value.tag) {
                        .pltgot => {},
                        .pltrelsz => {
                            relocation_table_size = value.val;
                        },
                        .symtab => {
                            std.log.info("symtab = 0x{x}", .{value.val});

                            const offset = value.val;

                            symbol_table = @ptrCast(@alignCast(elf_data.ptr + offset));
                        },
                        .strtab => {
                            const offset = value.val;

                            string_table = @ptrCast(elf_data.ptr + offset);
                        },
                        .gnu_hash => {
                            const offset = value.val;

                            gnu_hash_table = @ptrCast(@alignCast(elf_data.ptr + offset));
                        },
                        else => {},
                    }
                }

                std.log.info("first symbol: {}", .{symbol_table.?[1]});

                for (values) |value| {
                    switch (value.tag) {
                        .pltgot => {},
                        .jmprel => {
                            const offset = value.val;

                            const relocation_bytes = elf_data[offset .. offset + relocation_table_size];

                            const relocation_ptr: [*]const RelA = @ptrCast(@alignCast(relocation_bytes.ptr));
                            const relocations = relocation_ptr[0 .. relocation_bytes.len / @sizeOf(RelA)];

                            for (relocations) |relocation| {
                                //Location in the file where the address should be relocated
                                const relocation_offset = relocation.offset;

                                std.log.info("offset: 0x{}, info: 0x{}, addend: {}", .{ relocation.offset, relocation.info, relocation.addend });

                                const symbol = symbol_table.?[relocation.info.sym];

                                std.log.info("relocation symbol: value = 0x{x}", .{symbol.value});

                                const address_ptr: *u64 = @alignCast(@ptrCast(image + relocation_offset));

                                if (symbol.shndx == SHN_UNDEF) {
                                    //Symbol is undefined and must be resolved by us
                                    //For now, this ~only~ means resolving a native function from the host

                                    const string_ptr: [*:0]const u8 = @ptrCast(string_table.? + symbol.name);

                                    const string = std.mem.span(string_ptr);

                                    const native_procedure = native_procedures.get(string) orelse {
                                        std.log.info("Failed to find symbol '{s}'", .{string});

                                        return error.SymbolFailure;
                                    };

                                    address_ptr.* = Hart.nativeCallAddress(native_procedure);
                                } else {
                                    //Resolve local symbols from the elf file directly
                                    //I'm not sure why the program being loaded even has plt symbols which it knows at static link time anyway
                                    //But ok...
                                    address_ptr.* = @intFromPtr(image + symbol.value);
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            .gnu_stack => {
                stack_alignment = program_header.@"align";
                stack_size = @max(stack_size, program_header.memsz);
            },
            else => {},
        }
    }

    std.log.info("image base = {*}, image size = {}", .{ image, image_size });

    //TODO: stack should be local/unique to each hart, not to loaded modules
    const stack = allocator.rawAlloc(stack_size, 16, @returnAddress()).?;
    errdefer allocator.free(stack[0..stack_size]);

    std.log.info("stack base = {*}, stack size = {}", .{ stack, stack_size });

    return Loaded{
        .image = image[0..image_size],
        .entry_point = header.entry - minimum_virtual_address,
        .stack = stack[0..stack_size],
    };
}

///Lookup a symbol provided by the host
fn hostLookup(
    name: [*:0]const u8,
) void {
    _ = name; // autofix
}

///Lookup a symbol provided by the elf file
fn guestLookup(
    string_table: [*:0]const u8,
    symbol_table: [*]const Sym,
    hash_table: [*]const u32,
    name: [*:0]const u8,
) void {
    _ = string_table; // autofix
    _ = symbol_table; // autofix
    _ = hash_table; // autofix
    _ = name; // autofix
}

///Lookup a symbol provided by the elf file using GNU_HASH
fn gnuLookup(
    string_table: [*:0]const u8,
    symbol_table: [*]const Sym,
    hash_table: [*]const u32,
    name: [*:0]const u8,
) void {
    _ = name; // autofix
    _ = hash_table; // autofix
    _ = symbol_table; // autofix
    _ = string_table; // autofix
}

///Implementation of DT_GNU_HASH hashing for symbol lookup
fn gnuHash(name: [*:0]const u8) u32 {
    var hash: u32 = 5381;

    const char_index = 0;

    while (name[char_index] != 0) {
        defer char_index += 1;

        hash = (hash << 5) + hash + name[char_index];
    }

    return hash;
}

const Endianess = enum(u8) {
    little = 1,
    big = 2,
    _,
};

const Class = enum(u8) {
    @"32bit" = 1,
    @"64bit" = 2,
    _,
};

const Machine = enum(u16) {
    riscv = 243,
    _,
};

const ObjectType = enum(u16) {
    none = 0,
    rel = 1,
    exec = 2,
    dyn = 3,
    core = 4,
    _,
};

const Version = enum(u8) {
    current = 1,
    _,
};

pub const OsAbi = enum(u8) {
    systemv = 0,
    _,
};

pub const RiscvFlags = packed struct(u32) {
    ///Compressed instructions
    riscv_rvc: bool,
    pad0: u1,
    riscv_float_abi_single: bool,
    riscv_float_abi_double: bool,
    pad1: u4,
    pad2: u24,
};

const ElfHeader = extern struct {
    magic: [4]u8,
    class: Class,
    endianness: Endianess,
    version: Version,
    abi: OsAbi,
    /// abiversion: 0
    abi_version: u8,
    _padding: [7]u8,
    type: ObjectType align(1),
    machine: Machine align(1),
    /// version
    e_version: u32 align(1),
    entry: u64 align(1),

    /// start of program header
    /// It usually follows the file header immediately,
    /// making the offset 0x34 or 0x40
    /// for 32- and 64-bit ELF executables, respectively.
    e_phoff: u64 align(1),

    /// e_shoff
    /// start of section header table
    e_shoff: u64 align(1),

    flags: RiscvFlags align(1),

    /// Contains the size of this header,
    /// normally 64 Bytes for 64-bit and 52 Bytes for 32-bit format.
    e_ehsize: u16 align(1),

    /// size of program header
    e_phentsize: u16 align(1),

    /// number of entries in program header table
    e_phnum: u16 align(1),

    /// size of section header table entry
    e_shentsize: u16 align(1),

    /// number of section header entries
    e_shnum: u16 align(1),

    /// index of section header table entry that contains section names (.shstrtab)
    e_shstrndx: u16 align(1),
};

const PF_X = 0x1;
const PF_W = 0x2;
const PF_R = 0x4;
const PT_GNU_STACK = 0x6474e551;
const PT_GNU_RELRO = 0x6474e552;
///Section index which represents an undefined symbol
const SHN_UNDEF = 0;

const ProgramHeader = extern struct {
    type: Type align(1),
    flags: u32 align(1),
    offset: u64 align(1),
    vaddr: u64 align(1),
    paddr: u64 align(1),
    filesz: u64 align(1),
    memsz: u64 align(1),
    @"align": u64 align(1),

    pub const Type = enum(u32) {
        null = 0,
        load = 1,
        dynamic = 2,
        interp = 3,
        note = 4,
        shlib = 5,
        phdr = 6,
        tls = 7,
        num = 8,
        loos = 0x60000000,
        gnu_eh_frame = 0x6474e550,
        gnu_stack = 0x6474e551,
        gnu_relro = 0x6474e552,
        sunwbss = 0x6ffffffa,
        sunwstack = 0x6ffffffb,
        hisunw = 0x6fffffff,
        loproc = 0x70000000,
        hiproc = 0x7fffffff,
        _,
    };
};

const Dyn = extern struct {
    tag: Tag,
    val: u64,

    pub const Tag = enum(u64) {
        null = 0,
        needed = 1,
        pltrelsz = 2,
        pltgot = 3,
        hash = 4,
        strtab = 5,
        symtab = 6,
        rela = 7,
        relasz = 8,
        relaent = 9,
        strsz = 10,
        syment = 11,
        init = 12,
        fini = 13,
        soname = 14,
        rpath = 15,
        symbolic = 16,
        rel = 17,
        relsz = 18,
        relent = 19,
        pltrel = 20,
        jmprel = 23,
        flags = 30,
        gnu_hash = 0x6ffffef5,
        _,
    };
};

///Relocation
const RelA = extern struct {
    offset: u64,
    info: Info,
    addend: u64,

    pub const Info = packed struct(u64) {
        type: Type,
        sym: u32,

        pub const Type = enum(u32) {
            riscv_jump_slot = 5,
            _,
        };
    };
};

//Symbol found in the symbol table
const Sym = extern struct {
    ///Index into the string table
    name: u32,
    info: Info,
    other: u8,
    shndx: u16,
    value: u64,
    size: u64,

    pub fn visibility(self: Sym) Visibility {
        return @enumFromInt(self.other & 0x03);
    }

    pub const Info = packed struct(u8) {
        type: Type,
        bind: Bind,

        pub const Type = enum(u4) {
            notype = 0,
            object = 1,
            func = 2,
            section = 3,
            file = 4,
            common = 5,
            tls = 6,
            _,
        };

        pub const Bind = enum(u4) {
            local = 0,
            global = 1,
            weak = 2,
            _,
        };
    };

    pub const Visibility = enum(u8) {
        default = 0,
        internal = 1,
        hidden = 2,
        protected = 3,
        _,
    };
};

//TODO: not strictly needed, in fact the loader should NOT even look at sections
const SectionHeader = extern struct {
    name: u32 align(1),
    type: u32 align(1),
    flags: u32 align(1),
    addr: u64 align(1),
    offset: u64 align(1),
    size: u32 align(1),
    link: u32 align(1),
    info: u32 align(1),
    addralign: u32 align(1),
    entsize: u32 align(1),
};

const std = @import("std");
const Hart = @import("Hart.zig");
