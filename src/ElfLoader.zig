//!Loader implementation for the elf file format

pub const Loaded = struct {
    image: []u8,
    entry_point: usize,
    ///just some 'fake' stack to make things work
    stack: []u8,
};

pub fn load(allocator: std.mem.Allocator, elf_data: []const u8) !Loaded {
    const header: *const ElfHeader = @ptrCast(elf_data.ptr);

    std.debug.assert(std.mem.eql(u8, &header.magic, "\x7fELF"));

    std.log.info("elf_header = {}", .{header.*});

    const program_header_start: [*]const ProgramHeader = @ptrCast(elf_data.ptr + header.e_phoff);

    const program_headers = program_header_start[0..header.e_phnum];

    for (program_headers) |program_header| {
        std.log.info("prog header: {}\n", .{program_header});
    }

    //TODO: this is BODGED, but it's correct for now. These are our instructions
    const data_segment = program_headers[3];
    const text_segment = program_headers[2];

    const instruction_bytes = elf_data[text_segment.p_offset .. text_segment.p_offset + text_segment.p_filesz];
    const data_bytes = elf_data[data_segment.p_offset .. data_segment.p_offset + data_segment.p_filesz];

    std.log.info("instruction count approx = {}", .{instruction_bytes.len / 4});

    std.log.info("first instruction: 0x{x}", .{@as(*const u32, @alignCast(@ptrCast(instruction_bytes.ptr))).*});

    std.log.info("data: filesz = {}, memsz = {}", .{ data_bytes.len, data_segment.p_memsz });
    std.log.info("data: {s}", .{data_bytes});

    const sorted_program_headers = try allocator.dupe(ProgramHeader, program_headers);
    defer allocator.free(sorted_program_headers);

    const S = struct {
        pub fn lessThan(_: void, lhs: ProgramHeader, rhs: ProgramHeader) bool {
            if (lhs.p_vaddr < rhs.p_vaddr) {
                return true;
            }

            return false;
        }
    };
    _ = S; // autofix

    //sort the segments based on virtual addresses
    // std.sort.insertion(ProgramHeader, sorted_program_headers, {}, S.lessThan);

    //size of the image mapped in memory
    var image_size: usize = 0;

    for (sorted_program_headers) |program_header| {
        switch (program_header.p_type) {
            1, 6, 2, 0x70000000, PT_GNU_RELRO => {
                image_size = @max(image_size, program_header.p_vaddr);
                image_size += program_header.p_memsz;
            },
            else => {},
        }
    }

    const image = allocator.rawAlloc(image_size, 0, @returnAddress()).?;

    @memset(image[0..image_size], undefined);

    var stack_alignment: usize = 0;
    var stack_size: usize = 0;

    for (sorted_program_headers) |program_header| {
        switch (program_header.p_type) {
            1, 6, 2, 0x70000000, PT_GNU_RELRO => {
                const program_header_data = elf_data[program_header.p_offset .. program_header.p_offset + program_header.p_filesz];

                @memcpy(image[program_header.p_vaddr .. program_header.p_vaddr + program_header_data.len], program_header_data);

                const rest_size = program_header.p_memsz - program_header.p_filesz;

                @memset(image[program_header.p_vaddr + program_header_data.len .. program_header.p_vaddr + program_header_data.len + rest_size], 0);
            },
            PT_GNU_STACK => {
                stack_alignment = program_header.p_align;
                stack_size = program_header.p_memsz;
            },
            else => {},
        }
    }

    std.log.info("(size = {}) image = {s}", .{ image_size, image[0..image_size] });

    if (false) std.os.exit(0);

    const stack = allocator.rawAlloc(stack_size, @intCast(stack_alignment), @returnAddress()).?;

    return Loaded{
        .image = image[0..image_size],
        .entry_point = header.e_entry,
        .stack = stack[0..stack_size],
    };
}

const ElfHeader = extern struct {
    /// e_ident
    magic: [4]u8 = "\x7fELF".*,
    /// 32 bit (1) or 64 (2)
    class: u8 = 2,
    /// endianness little (1) or big (2)
    endianness: u8 = 1,
    /// ELF version
    version: u8 = 1,
    /// osabi: we want systemv which is 0
    abi: u8 = 0,
    /// abiversion: 0
    abi_version: u8 = 0,
    /// paddding
    padding: [7]u8 = [_]u8{0} ** 7,

    /// object type
    e_type: u16 align(1),

    /// arch
    e_machine: u16 align(1),

    /// version
    e_version: u32 align(1),

    /// entry point
    e_entry: u64 align(1),

    /// start of program header
    /// It usually follows the file header immediately,
    /// making the offset 0x34 or 0x40
    /// for 32- and 64-bit ELF executables, respectively.
    e_phoff: u64 align(1),

    /// e_shoff
    /// start of section header table
    e_shoff: u64 align(1),

    /// ???
    e_flags: u32 align(1),

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
    /// type of segment
    /// 1 for loadable
    p_type: u32 align(1),

    /// segment dependent
    /// NO PROTECTION
    p_flags: u32 align(1),

    /// offset of the segment in the file image
    p_offset: u64 align(1),

    /// virtual addr of segment in memory. start of this segment
    p_vaddr: u64 align(1),

    /// same as vaddr except on physical systems
    p_paddr: u64 align(1),

    p_filesz: u64 align(1),

    p_memsz: u64 align(1),

    /// 0 and 1 specify no alignment.
    /// Otherwise should be a positive, integral power of 2,
    /// with p_vaddr equating p_offset modulus p_align.
    p_align: u64 align(1),
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
