//!Virtual Machine Hart
program_counter: [*]const u32,
registers: [32]u64,

pub fn init() Vm {
    return .{
        .program_counter = undefined,
        .registers = std.mem.zeroes([32]u64),
    };
}

pub fn deinit(self: *Vm) void {
    self.* = undefined;
}

pub inline fn readRegister(self: *Vm, register: u5) u64 {
    if (register == 0) return 0;

    return self.registers[register];
}

pub inline fn setRegister(self: *Vm, register: u5, value: u64) void {
    if (register != 0) {
        self.registers[register] = value;
    }
}

///Execute a stream of RISC-V instructions located in memory
///The executing program will view this as identical to a JAL/JALR to this address
pub fn execute(
    self: *Vm,
    comptime config: ExecuteConfig,
    ///Instruction address that will be executed
    address: [*]const u32,
) void {
    self.program_counter = address;

    while (true) {
        const instruction = self.program_counter[0];
        const instruction_generic: InstructionGeneric = @bitCast(instruction);

        switch (instruction_generic.opcode) {
            .lui => {
                const u_instruction: InstructionU = @bitCast(instruction);

                std.log.info("lui x{}, {}", .{ u_instruction.rd, u_instruction.imm });

                const value: packed struct(i32) {
                    lower: u12,
                    upper: u20,
                } = .{
                    .lower = 0,
                    .upper = u_instruction.imm,
                };

                const sign_extended: i64 = @as(i32, @bitCast(value));

                self.setRegister(u_instruction.rd, @bitCast(sign_extended));
            },
            .auipc => {
                const u_instruction: InstructionU = @bitCast(instruction);

                const value: packed struct(i32) {
                    lower: u12,
                    upper: u20,
                } = .{
                    .lower = 0,
                    .upper = u_instruction.imm,
                };

                const sign_extended_offset: i64 = @as(i32, @bitCast(value));

                const base: i64 = @bitCast(@intFromPtr(self.program_counter));

                const actual_address: u64 = @bitCast(base + sign_extended_offset);

                self.setRegister(u_instruction.rd, actual_address);

                std.log.info("auipc x{}, {}", .{ u_instruction.rd, u_instruction.imm });
            },
            .op => {
                const r_instruction: InstructionR = @bitCast(instruction);
                const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .add => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result = a + b;

                        self.setRegister(r_instruction.rd, @bitCast(result));

                        std.log.info("add x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                    },
                    .sub => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result = a - b;

                        self.setRegister(r_instruction.rd, @bitCast(result));

                        std.log.info("sub x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                    },
                    .@"and" => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a & b;

                        self.setRegister(r_instruction.rd, result);

                        std.log.info("and x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                    },
                    .@"or" => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a | b;

                        self.setRegister(r_instruction.rd, result);

                        std.log.info("or x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                    },
                    .xor => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a ^ b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .sll => {},
                    .slt => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: u64 = @intFromBool(a < b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    .sltu => {
                        const a: u64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: u64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: u64 = @intFromBool(a < b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    .srl => unreachable,
                    .sra => unreachable,
                }
            },
            .op_imm => {
                const i_instruction: InstructionI = @bitCast(instruction);
                const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .addi => {
                        //effectively sign extends the immedidate by casting to i12 then to i64 (full width)
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result = @as(i64, @intCast(self.registers[i_instruction.rs1])) + immediate;

                        self.setRegister(i_instruction.rd, @bitCast(result));

                        std.log.info("addi x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                    },
                    .slti => unreachable,
                    .sltiu => unreachable,
                    .xori => unreachable,
                    .ori => unreachable,
                    .andi => {
                        //effectively sign extends the immedidate by casting to i12 then to i64 (full width)
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result = @as(i64, @intCast(self.registers[i_instruction.rs1])) & immediate;

                        self.setRegister(i_instruction.rd, @bitCast(result));

                        std.log.info("andi x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                    },
                    else => unreachable,
                }
            },
            .load => {
                const i_instruction: InstructionI = @bitCast(instruction);
                const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .lb => {
                        const pointer: *i8 = @ptrFromInt(self.registers[i_instruction.rs1 + i_instruction.imm]);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, @intCast(pointer.*)));
                    },
                    .lh => {
                        const pointer: *i16 = @ptrFromInt(self.registers[i_instruction.rs1 + i_instruction.imm]);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, @intCast(pointer.*)));
                    },
                    .lw => {
                        const pointer: *i32 = @ptrFromInt(self.registers[i_instruction.rs1 + i_instruction.imm]);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, @intCast(pointer.*)));
                    },
                    .lbu => {
                        const pointer: *u8 = @ptrFromInt(self.registers[i_instruction.rs1 + i_instruction.imm]);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    .lhu => {
                        const pointer: *u16 = @ptrFromInt(self.registers[i_instruction.rs1 + i_instruction.imm]);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    else => unreachable,
                }
            },
            .store => {
                const s_instruction: InstructionS = @bitCast(instruction);
                const masked_instruction: SInstructionMask = @enumFromInt(instruction & SInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .sb => {
                        const pointer: *u8 = @ptrFromInt(self.registers[s_instruction.rs1 + s_instruction.imm]);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);

                        std.log.info("sb x{}, x{} + 0x{x}", .{ s_instruction.rs1, s_instruction.rs2, s_instruction.imm });
                    },
                    .sh => {
                        std.log.info("sh x{}, x{} + 0x{x}", .{ s_instruction.rs1, s_instruction.rs2, s_instruction.imm });

                        const pointer: *u8 = @ptrFromInt(self.registers[s_instruction.rs1 + s_instruction.imm]);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);
                    },
                    .sw => {
                        std.log.info("sw x{}, x{} + 0x{x}", .{ s_instruction.rs1, s_instruction.rs2, s_instruction.imm });

                        const pointer: *u8 = @ptrFromInt(self.registers[s_instruction.rs1 + s_instruction.imm]);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);
                    },
                }
            },
            .branch => {
                const b_instruction: InstructionB = @bitCast(instruction);
                const masked_instruction: BInstructionMask = @enumFromInt(instruction & BInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .beq => {
                        const CombinedImmediate = packed struct(i13) {
                            zero: u1 = 0,
                            imm_0: u5,
                            imm_1: u7,
                        };

                        const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                        std.log.info("beq x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });

                        if (self.registers[b_instruction.rs1] == self.registers[b_instruction.rs2]) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(self.program_counter))) + @as(i64, @intCast(combined_immediate * 2));

                            self.program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));

                            self.program_counter -= 1;
                        }
                    },
                    .bne => {
                        const CombinedImmediate = packed struct(i13) {
                            zero: u1 = 0,
                            imm_0: u5,
                            imm_1: u7,
                        };

                        const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                        std.log.info("bne x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });

                        if (self.registers[b_instruction.rs1] != self.registers[b_instruction.rs2]) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(self.program_counter))) + @as(i64, @intCast(combined_immediate * 2));

                            self.program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));

                            self.program_counter -= 1;
                        }
                    },
                    .blt => unreachable,
                    .bge => unreachable,
                    .bltu => unreachable,
                    .bgeu => unreachable,
                }
            },
            .jal => {
                const j_instruction: InstructionJ = @bitCast(instruction);

                //rd has address of next instruction stored

                const offset: i20 = (@divTrunc(j_instruction.imm, 2));

                const next = (self.program_counter + 1);

                //return address
                self.registers[j_instruction.rd] = @intFromPtr(next);

                const jump_address = @as(i64, @intCast(@intFromPtr(self.program_counter))) + offset;

                self.program_counter = @ptrFromInt(@as(usize, @bitCast(jump_address)));
            },
            .jalr => {
                const j_instruction: InstructionI = @bitCast(instruction);

                //rd has address of next instruction stored

                const offset: i20 = (@divTrunc(j_instruction.imm, 2));

                const next = (self.program_counter + 1);

                //return address
                self.registers[j_instruction.rd] = @intFromPtr(next);

                const register_address: [*]const u32 = @ptrFromInt(self.registers[j_instruction.rs1]);

                const jump_address = @as(i64, @intCast(@intFromPtr(register_address))) + offset;

                self.program_counter = @ptrFromInt(@as(usize, @bitCast(jump_address)));
            },
            .system => {
                const i_instruction: InstructionI = @bitCast(instruction);

                switch (i_instruction.imm) {
                    //ecall
                    0 => {
                        if (config.ecall_handler) |ecall| {
                            switch (ecall(self)) {
                                .pass => {},
                                .halt => {
                                    return;
                                },
                            }
                        }
                    },
                    //ebreak
                    1 => {
                        if (config.ebreak_handler) |ebreak| {
                            switch (ebreak(self)) {
                                .pass => {},
                                .halt => {
                                    return;
                                },
                            }
                        }
                    },
                    else => {},
                }
            },
            else => {
                @panic("Unknown opcode");
            },
        }

        self.program_counter += 1;
    }
}

pub const SInstructionMask = enum(u32) {
    sb = @bitCast(InstructionS{
        .opcode = 0b0100011,
        .funct3 = 0b000,
    }),
    sh = @bitCast(InstructionS{
        .opcode = 0b0100011,
        .funct3 = 0b001,
    }),
    sw = @bitCast(InstructionS{
        .opcode = 0b0100011,
        .funct3 = 0b010,
    }),

    pub const removing_mask: u32 = @bitCast(InstructionS{
        .opcode = 0b1111111,
        .funct3 = 0b111,
    });
};

///masks that allow us to mask off bits that don't change instructions
///registers and immediates are zero in this mask
pub const RInstructionMask = enum(u32) {
    add = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct7 = 0b0000000,
    }),
    sub = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct7 = 0b0100000,
    }),
    @"and" = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b111,
    }),
    xor = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b100,
    }),
    @"or" = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b110,
    }),
    sll = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b001,
    }),
    slt = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b010,
    }),
    sltu = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b011,
    }),
    srl = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b101,
    }),
    sra = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b101,
        .funct7 = 0b0100000,
    }),

    pub const removing_mask: u32 = @bitCast(InstructionR{
        .opcode = 0b1111111,
        .funct3 = 0b111,
        .funct7 = 0b1111111,
    });
};

pub const IInstructionMask = enum(u32) {
    addi = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b000,
    }),
    slti = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b010,
    }),
    sltiu = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b011,
    }),
    xori = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b100,
    }),
    ori = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b110,
    }),
    andi = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b111,
    }),
    lb = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b000,
    }),
    lh = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b001,
    }),
    lw = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b010,
    }),
    lbu = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b100,
    }),
    lhu = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b101,
    }),

    pub const removing_mask: u32 = @bitCast(InstructionI{
        .opcode = 0b1111111,
        .funct3 = 0b111,
    });
};

pub const BInstructionMask = enum(u32) {
    beq = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b000,
    }),
    bne = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b001,
    }),
    blt = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b100,
    }),
    bge = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b101,
    }),
    bltu = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b110,
    }),
    bgeu = @bitCast(InstructionB{
        .opcode = 0b1100011,
        .funct3 = 0b111,
    }),

    pub const removing_mask: u32 = @bitCast(InstructionB{
        .opcode = 0b1111111,
        .funct3 = 0b111,
    });
};

///Standard Risc-V extension
pub const Extension = enum {
    ///Multiply and Divide
    m,
    ///Atomics
    a,
    ///
    ziscr,
    ///
    zifencei,
    ///32bit floating point
    f,
    ///64bit floating point
    d,
    ///128bit floating point
    q,
    ///compressed instructions
    c,
};

pub const InterruptResult = enum {
    ///Execution continues
    pass,
    ///Execution halts
    halt,
};

///Compile time configuration for how an execute function should work
pub const ExecuteConfig = struct {
    ecall_handler: ?fn (vm: *Vm) InterruptResult = null,
    ebreak_handler: ?fn (vm: *Vm) InterruptResult = null,
};

pub const Register = enum(u5) {
    x0,
    x1,
    x2,
    x3,
    x4,
    x5,
    x6,
    x7,
    x8,
    x9,
    x10,
    x11,
    x12,
    x13,
    x14,
    x15,
    x16,
    x17,
    x18,
    x19,
    x20,
    x21,
    x22,
    x23,
    x24,
    x25,
    x26,
    x27,
    x28,
    x29,
    x30,
    x31,
};

pub const AbiRegister = enum(u5) {
    zero,
    ra,
    sp,
    gp,
    tp,
    t0,
    t1,
    t2,
    fp,
    s1,
    a0,
    a1,
    a2,
    a3,
    a4,
    a5,
    a6,
    a7,
    s2,
    s3,
    s4,
    s5,
    s6,
    s7,
    s8,
    s9,
    s10,
    s11,
    t3,
    t4,
    t5,
    t6,
};

pub const InstructionGeneric = packed struct(u32) {
    opcode: Opcode,
    rest: u25,
};

pub const InstructionR = packed struct(u32) {
    opcode: u7 = 0,
    //register
    rd: u5 = 0,
    funct3: u3 = 0,
    //register
    rs1: u5 = 0,
    //register
    rs2: u5 = 0,
    funct7: u7 = 0,
};

pub const InstructionI = packed struct(u32) {
    opcode: u7 = 0,
    rd: u5 = 0,
    funct3: u3 = 0,
    rs1: u5 = 0,
    imm: u12 = 0,
};

pub const InstructionS = packed struct(u32) {
    opcode: u7 = 0,
    imm: u5 = 0,
    funct3: u3 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm_1: u7 = 0,
};

pub const InstructionU = packed struct(u32) {
    opcode: u7 = 0,
    rd: u5 = 0,
    imm: u20 = 0,
};

pub const InstructionB = packed struct(u32) {
    opcode: u7 = 0,
    imm: u5 = 0,
    funct3: u3 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm_1: u7 = 0,
};

pub const InstructionJ = packed struct(u32) {
    opcode: u7 = 0,
    rd: u5 = 0,
    imm: i20 = 0,
};

///The Major opcode encoding
pub const Opcode = enum(u7) {
    op = 0b01_100_11,
    op_imm = 0b00_100_11,
    op_32 = 0b01_110_11,
    op_imm32 = 0b00_110_11,
    op_fp = 0b10_100_11,
    load_fp = 0b00_001_11,
    store_fp = 0b01_001_11,
    lui = 0b01_101_11,
    auipc = 0b00_101_11,
    load = 0b00_000_11,
    store = 0b01_000_11,
    system = 0b11_100_11,
    jalr = 0b11_001_11,
    jal = 0b11_011_11,
    branch = 0b11_000_11,
    _,
};

const Vm = @This();
const std = @import("std");
