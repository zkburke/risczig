//!Loader implementation for the elf file format

pub const Loaded = struct {
    image: []u8,
    entry_point: usize,
    stack: []u8,
};

///TODO: implement loader using mmap as a specialisation for loading files.
///Both loading from a file and from memory should work
pub fn load(allocator: std.mem.Allocator, elf_data: []const u8) !Loaded {
    const header: *const ElfHeader = @ptrCast(elf_data.ptr);

    std.debug.assert(std.mem.eql(u8, &header.magic, "\x7fELF"));

    std.debug.assert(header.version == .current);
    std.debug.assert(header.abi == .systemv);
    std.debug.assert(header.class == .@"64bit");
    std.debug.assert(header.endianness == .little);
    std.debug.assert(header.machine == .riscv);
    std.debug.assert(header.type == .exec);

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
            1, 6 => {
                minimum_virtual_address = @min(minimum_virtual_address, program_header.vaddr);

                image_size = @max(image_size, program_header.vaddr) - minimum_virtual_address;
                image_size += program_header.memsz;
            },
            else => {},
        }
    }

    std.debug.assert(minimum_virtual_address != std.math.maxInt(usize));

    std.log.info("minimum_virtual_address = {}", .{minimum_virtual_address});

    const image = allocator.rawAlloc(image_size, 0, @returnAddress()).?;

    @memset(image[0..image_size], undefined);

    var stack_alignment: usize = 0;
    var stack_size: usize = 0;

    for (program_headers) |program_header| {
        switch (program_header.type) {
            1, 6 => {
                const program_header_data = elf_data[program_header.offset .. program_header.offset + program_header.filesz];

                const base_address = program_header.vaddr - minimum_virtual_address;

                @memcpy(image[base_address .. base_address + program_header_data.len], program_header_data);

                const rest_size = program_header.memsz - program_header.filesz;

                @memset(image[base_address + program_header_data.len .. base_address + program_header_data.len + rest_size], 0);
            },
            PT_GNU_STACK => {
                stack_alignment = program_header.@"align";
                stack_size = program_header.memsz;
            },
            else => {},
        }
    }

    std.log.info("image base = {*}, image size = {}", .{ image, image_size });

    //TODO: stack should be local/unique to each hart, not to loaded modules
    const stack = allocator.rawAlloc(stack_size, @intCast(stack_alignment), @returnAddress()).?;

    return Loaded{
        .image = image[0..image_size],
        .entry_point = header.entry - minimum_virtual_address,
        .stack = stack[0..stack_size],
    };
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

const ProgramHeader = extern struct {
    type: u32 align(1),
    flags: u32 align(1),
    offset: u64 align(1),
    vaddr: u64 align(1),
    paddr: u64 align(1),
    filesz: u64 align(1),
    memsz: u64 align(1),
    @"align": u64 align(1),
};

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
