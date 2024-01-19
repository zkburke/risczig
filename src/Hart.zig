//!Virtual Machine Hart implementation for RV64I-MAFD, along with zfencei and zicsr
//!Contains all Hart internal state
///General purpose registers
registers: [32]u64,
program_counter: [*]const u32,

pub fn init() Hart {
    return .{
        .registers = std.mem.zeroes([32]u64),
        .program_counter = undefined,
    };
}

pub fn deinit(self: *Hart) void {
    self.* = undefined;
}

pub inline fn readRegister(self: *Hart, register: u5) u64 {
    if (register == 0) return 0;

    return self.registers[register];
}

pub inline fn setRegister(self: *Hart, register: u5, value: u64) void {
    if (register != 0) {
        self.registers[register] = value;
    }
}

///The signature for a native call
pub const NativeCall = fn (hart: *Hart) void;

///Converts a function pointer to a native call function to a compatable address
///The resulting address will cause the native call to be called when passed to the jalr instruction in rs1
pub fn nativeCallAddress(native_call: *const NativeCall) u64 {
    var actual_address: u64 = @intFromPtr(native_call);

    actual_address <<= 16;

    //set the native call flag bit at lsb
    actual_address |= 0x00000000_00000001;

    return actual_address;
}

///Converts a native call address (which can be used by jalr when passed in rs1) to a function pointer
pub fn nativeCallPointer(address: u64) *const NativeCall {
    const Bits = packed struct(u64) {
        lsb: u1,
        upper: u63,
    };

    var bits: Bits = @bitCast(address);

    std.debug.assert(bits.lsb == 1);

    bits.lsb = 0;

    var actual_address: u64 = @bitCast(bits);

    actual_address >>= 16;

    return @ptrFromInt(actual_address);
}

pub const ExecuteError = error{
    UnsupportedInstruction,
};

///Execute a stream of RISC-V instructions located in memory
///The executing program will view this as identical to a jal/jalr to this address
pub fn execute(
    self: *Hart,
    comptime config: ExecuteConfig,
    ///Instruction address that will be executed
    address: [*]const u32,
) ExecuteError!void {
    const debug_instructions = false;

    //Using a local program counter allows it to be put into a register
    //As such, all instructions should read and write this program counter, NOT the program counter stored in the hart
    //I would usually expect the compiler to be able to do this, but in this case, no.
    var program_counter: [*]const u32 = address;

    //Save the program counter into the hart state so it can be observed by host calls
    defer self.program_counter = program_counter;

    while (true) {
        const instruction = program_counter[0];
        const instruction_generic: InstructionGeneric = @bitCast(instruction);

        if (debug_instructions) {
            self.program_counter = program_counter;

            debugInstruction(self, instruction);
        }

        switch (instruction_generic.opcode) {
            .lui => {
                const u_instruction: InstructionU = @bitCast(instruction);

                const value: packed struct(i32) {
                    lower: u12,
                    upper: u20,
                } = .{
                    .lower = 0,
                    .upper = u_instruction.imm,
                };

                const sign_extended: i64 = @as(i32, @bitCast(value));

                self.setRegister(u_instruction.rd, @bitCast(sign_extended));

                program_counter += 1;
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

                const base: i64 = @bitCast(@intFromPtr(program_counter));

                const actual_address: i64 = base + sign_extended_offset;

                self.setRegister(u_instruction.rd, @bitCast(actual_address));

                program_counter += 1;
            },
            .op => {
                const r_instruction: InstructionR = @bitCast(instruction);
                const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .add => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result = a +% b;

                        self.setRegister(r_instruction.rd, @bitCast(result));
                    },
                    .sub => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result = a -% b;

                        self.setRegister(r_instruction.rd, @bitCast(result));
                    },
                    .@"and" => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a & b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .@"or" => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a | b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .xor => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a ^ b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .sll => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u6 = @truncate(self.registers[r_instruction.rs2]);

                        const result: u64 = a << b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .srl => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u6 = @truncate(self.registers[r_instruction.rs2]);

                        const result: u64 = a >> b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .sra => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: u6 = @truncate(self.registers[r_instruction.rs2]);

                        const result: i64 = a >> b;

                        self.setRegister(r_instruction.rd, @bitCast(result));
                    },
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
                    .mul => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result = a *% b;

                        self.setRegister(r_instruction.rd, @bitCast(result));
                    },
                    .mulhu => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a *% b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .remu => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = @rem(a, b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    .addw => unreachable,
                    .subw => unreachable,
                    .sllw => unreachable,
                    .srlw => unreachable,
                    .sraw => unreachable,
                    .mulw => unreachable,
                    .divw => unreachable,
                    .lr_w_aq,
                    .lr_w_rl,
                    .sc_w_aq,
                    .sc_w_rl,
                    .amoswap_w_aq,
                    .amoswap_w_rl,
                    => unreachable,
                    .mulh => unreachable,
                    .mulhsu => unreachable,
                    .div => unreachable,
                    .divu => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result = a / b;

                        self.setRegister(r_instruction.rd, result);
                    },
                    .rem => unreachable,
                    .divuw => unreachable,
                    .remw => unreachable,
                    .remuw => unreachable,
                    else => unreachable,
                }

                program_counter += 1;
            },
            .op_32 => {
                const r_instruction: InstructionR = @bitCast(instruction);
                const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .addw => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: i32 = @truncate(a +% b);

                        const sign_extended: i64 = @intCast(result);

                        self.setRegister(r_instruction.rd, @bitCast(sign_extended));
                    },
                    .subw => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: i32 = @truncate(a -% b);

                        const sign_extended: i64 = @intCast(result);

                        self.setRegister(r_instruction.rd, @bitCast(sign_extended));
                    },
                    .sllw => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u5 = @truncate(self.registers[r_instruction.rs2]);

                        const result: u32 = @truncate(a << b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    .srlw => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u5 = @truncate(self.registers[r_instruction.rs2]);

                        const result: u32 = @truncate(a >> b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    .sraw => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: u5 = @truncate(self.registers[r_instruction.rs2]);

                        const result: i32 = @truncate(a >> b);

                        const sign_extended: i64 = result;

                        self.setRegister(r_instruction.rd, @bitCast(sign_extended));
                    },
                    .mulw => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: i32 = @truncate(a *% b);
                        const sign_extended: i64 = @intCast(result);

                        self.setRegister(r_instruction.rd, @bitCast(sign_extended));
                    },
                    .divw => {
                        const a: i64 = @bitCast(self.registers[r_instruction.rs1]);
                        const b: i64 = @bitCast(self.registers[r_instruction.rs2]);

                        const result: i32 = @truncate(@divTrunc(a, b));
                        const sign_extended: i64 = @intCast(result);

                        self.setRegister(r_instruction.rd, @bitCast(sign_extended));
                    },
                    .divuw => {
                        const a: u64 = self.registers[r_instruction.rs1];
                        const b: u64 = self.registers[r_instruction.rs2];

                        const result: u32 = @truncate(a / b);

                        self.setRegister(r_instruction.rd, result);
                    },
                    else => unreachable,
                }

                program_counter += 1;
            },
            .op_imm => {
                const i_instruction: InstructionI = @bitCast(instruction);
                const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .addi => {
                        const rs1: i64 = @bitCast(self.registers[i_instruction.rs1]);
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result = rs1 +% immediate;

                        self.setRegister(i_instruction.rd, @bitCast(result));
                    },
                    .slti => {
                        const rs1: i64 = @bitCast(self.registers[i_instruction.rs1]);
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result: u64 = @intFromBool(rs1 < immediate);

                        self.setRegister(i_instruction.rd, result);
                    },
                    .sltiu => {
                        const a: u64 = self.registers[i_instruction.rs1];
                        const b: u64 = i_instruction.imm;

                        const result: u64 = @intFromBool(a < b);

                        self.setRegister(i_instruction.rd, result);
                    },
                    .xori => {
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result = @as(i64, @bitCast(self.registers[i_instruction.rs1])) ^ immediate;

                        self.setRegister(i_instruction.rd, @bitCast(result));
                    },
                    .ori => unreachable,
                    .andi => {
                        const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

                        const result = @as(i64, @bitCast(self.registers[i_instruction.rs1])) & immediate;

                        self.setRegister(i_instruction.rd, @bitCast(result));
                    },
                    .slli => {
                        const Immediate = packed struct(u12) {
                            shamt: u6,
                            funct6: u6,
                        };

                        const imm: Immediate = @bitCast(i_instruction.imm);

                        self.setRegister(i_instruction.rd, self.registers[i_instruction.rs1] << imm.shamt);
                    },
                    .srli_and_srai => {
                        const Immediate = packed struct(u12) {
                            shamt: u6,
                            funct6: u6,
                        };

                        const imm: Immediate = @bitCast(i_instruction.imm);

                        switch (imm.funct6) {
                            0b000000 => {
                                self.setRegister(i_instruction.rd, self.registers[i_instruction.rs1] >> imm.shamt);
                            },
                            0b010000 => {
                                const rs1: i64 = @bitCast(self.registers[i_instruction.rs1]);
                                const shamt: u6 = imm.shamt;

                                const result = rs1 >> shamt;

                                self.setRegister(i_instruction.rd, @bitCast(result));
                            },
                            else => unreachable,
                        }
                    },
                    .lb => unreachable,
                    .lh => unreachable,
                    .lw => unreachable,
                    .lbu => unreachable,
                    .lhu => unreachable,
                    .ld => unreachable,
                    .lwu => unreachable,
                    .addiw => unreachable,
                    .slliw => unreachable,
                    .srliw_and_sraiw => unreachable,
                }

                program_counter += 1;
            },
            .op_imm32 => {
                const i_instruction: InstructionI = @bitCast(instruction);
                const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .addiw => {
                        const rs1: i64 = @bitCast(self.registers[i_instruction.rs1]);
                        const immediate: i64 = @as(i12, @bitCast(i_instruction.imm));

                        const result = rs1 +% immediate;

                        const truncated: i32 = @truncate(result);

                        const sign_extended: i64 = truncated;

                        self.setRegister(i_instruction.rd, @bitCast(sign_extended));
                    },
                    .slliw => {
                        const Immediate = packed struct(u12) {
                            shamt: u6,
                            funct6: u6,
                        };

                        const imm: Immediate = @bitCast(i_instruction.imm);

                        const rs1 = self.registers[i_instruction.rs1];
                        const shift_ammount = imm.shamt;

                        const result: u32 = @truncate(rs1 << shift_ammount);

                        self.setRegister(i_instruction.rd, result);
                    },
                    .srliw_and_sraiw => {
                        const Immediate = packed struct(u12) {
                            shamt: u6,
                            funct6: u6,
                        };

                        const imm: Immediate = @bitCast(i_instruction.imm);
                        const rs1 = self.registers[i_instruction.rs1];
                        const shift_ammount = imm.shamt;

                        switch (imm.funct6) {
                            0b000000 => {
                                const result: u32 = @truncate(rs1 >> shift_ammount);

                                self.setRegister(i_instruction.rd, result);
                            },
                            0b010000 => {
                                const rs1_signed: i64 = @bitCast(rs1);

                                const result: i32 = @truncate(rs1_signed >> shift_ammount);

                                const sign_extended: i64 = result;

                                self.setRegister(i_instruction.rd, @bitCast(sign_extended));
                            },
                            else => unreachable,
                        }
                    },
                    else => unreachable,
                }

                program_counter += 1;
            },
            .load => {
                const i_instruction: InstructionI = @bitCast(instruction);
                const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

                const base: i64 = @bitCast(self.registers[i_instruction.rs1]);
                const offset: i64 = @as(i12, @bitCast(i_instruction.imm));
                const actual: u64 = @bitCast(base + offset);

                switch (masked_instruction) {
                    .lb => {
                        const pointer: *align(1) const i8 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, pointer.*));
                    },
                    .lh => {
                        const pointer: *align(1) const i16 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, pointer.*));
                    },
                    .lw => {
                        const pointer: *align(1) const i32 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = @bitCast(@as(i64, pointer.*));
                    },
                    .lbu => {
                        const pointer: *align(1) const u8 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    .lhu => {
                        const pointer: *align(1) const u16 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    .lwu => {
                        const pointer: *align(1) const u32 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    .ld => {
                        const pointer: *align(1) const u64 = @ptrFromInt(actual);

                        self.registers[i_instruction.rd] = pointer.*;
                    },
                    else => unreachable,
                }

                program_counter += 1;
            },
            .store => {
                const s_instruction: InstructionS = @bitCast(instruction);
                const masked_instruction: SInstructionMask = @enumFromInt(instruction & SInstructionMask.removing_mask);

                const immediate: packed struct(i12) {
                    lower: u5,
                    upper: u7,
                } = .{ .lower = s_instruction.imm, .upper = s_instruction.imm_1 };

                const offset: i64 = @as(i12, @bitCast(immediate));
                const base: i64 = @bitCast(self.registers[s_instruction.rs1]);
                const actual: u64 = @bitCast(base + offset);

                switch (masked_instruction) {
                    .sb => {
                        const pointer: *align(1) u8 = @ptrFromInt(actual);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);
                    },
                    .sh => {
                        const pointer: *align(1) u16 = @ptrFromInt(actual);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);
                    },
                    .sw => {
                        const pointer: *align(1) u32 = @ptrFromInt(actual);

                        pointer.* = @truncate(self.registers[s_instruction.rs2]);
                    },
                    .sd => {
                        const pointer: *align(1) u64 = @ptrFromInt(actual);

                        pointer.* = self.registers[s_instruction.rs2];
                    },
                }

                program_counter += 1;
            },
            .branch => {
                const b_instruction: InstructionB = @bitCast(instruction);
                const masked_instruction: BInstructionMask = @enumFromInt(instruction & BInstructionMask.removing_mask);

                const AddressImmediateUpper = packed struct(u7) {
                    imm10_5: i6,
                    imm12: i1,
                };

                const AddressImmediateLower = packed struct(u5) {
                    imm11: i1,
                    imm4_1: i4,
                };

                const imm_lower: AddressImmediateLower = @bitCast(b_instruction.imm);
                const imm_upper: AddressImmediateUpper = @bitCast(b_instruction.imm_1);

                const ReconstitudedImmediate = packed struct(i13) {
                    imm0: i1 = 0,
                    imm4_1: i4,
                    imm10_5: i6,
                    imm11: i1,
                    imm12: i1,
                };

                const imm_reconstituted: ReconstitudedImmediate = .{
                    .imm11 = imm_lower.imm11,
                    .imm4_1 = imm_lower.imm4_1,
                    .imm10_5 = imm_upper.imm10_5,
                    .imm12 = imm_upper.imm12,
                };

                const combined_immediate: i13 = @bitCast(imm_reconstituted);

                switch (masked_instruction) {
                    .beq => {
                        if (self.registers[b_instruction.rs1] == self.registers[b_instruction.rs2]) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(program_counter))) + @as(i64, @intCast(combined_immediate));

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                    .bne => {
                        if (self.registers[b_instruction.rs1] != self.registers[b_instruction.rs2]) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(program_counter))) + @as(i64, @intCast(combined_immediate));

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                    .blt => {
                        const rs1: i64 = @bitCast(self.registers[b_instruction.rs1]);
                        const rs2: i64 = @bitCast(self.registers[b_instruction.rs2]);

                        if (rs1 < rs2) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(program_counter))) + @as(i64, @intCast(combined_immediate));

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                    .bge => {
                        const rs1: i64 = @bitCast(self.registers[b_instruction.rs1]);
                        const rs2: i64 = @bitCast(self.registers[b_instruction.rs2]);

                        if (rs1 >= rs2) {
                            const base = @as(i64, @bitCast(@intFromPtr(program_counter)));
                            const offset = @as(i64, combined_immediate);

                            const signed_pc: i64 = base + offset;

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                    .bltu => {
                        const rs1: u64 = self.registers[b_instruction.rs1];
                        const rs2: u64 = self.registers[b_instruction.rs2];

                        if (rs1 < rs2) {
                            const base = @as(i64, @bitCast(@intFromPtr(program_counter)));
                            const offset = @as(i64, combined_immediate);

                            const signed_pc: i64 = base + offset;

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                    .bgeu => {
                        if (self.registers[b_instruction.rs1] >= self.registers[b_instruction.rs2]) {
                            const signed_pc: i64 = @as(i64, @intCast(@intFromPtr(program_counter))) + @as(i64, @intCast(combined_immediate));

                            program_counter = @ptrFromInt(@as(usize, @bitCast(signed_pc)));
                        } else {
                            program_counter += 1;
                        }
                    },
                }
            },
            .jal => {
                const j_instruction: InstructionJ = @bitCast(instruction);

                const base: i64 = @bitCast(@intFromPtr(program_counter));

                const ImmediateAddress = packed struct(i20) {
                    imm19_12: i8,
                    imm11: i1,
                    imm10_1: i10,
                    imm20: i1,
                };

                const ReconstitutedImmediate = packed struct(i20) {
                    imm10_1: i10,
                    imm11: i1,
                    imm19_12: i8,
                    imm20: i1,
                };

                const immediate_address: ImmediateAddress = @bitCast(j_instruction.imm);

                const immediate_reconstituted: ReconstitutedImmediate = .{
                    .imm10_1 = immediate_address.imm10_1,
                    .imm11 = immediate_address.imm11,
                    .imm19_12 = immediate_address.imm19_12,
                    .imm20 = immediate_address.imm20,
                };

                const half_offset: i20 = @bitCast(immediate_reconstituted);

                const offset: i64 = half_offset * 2;

                const return_address: u64 = @intFromPtr(program_counter) + 4;

                //return address
                self.setRegister(j_instruction.rd, return_address);

                const jump_address = base + offset;

                program_counter = @ptrFromInt(@as(usize, @bitCast(jump_address)));
            },
            .jalr => {
                //TODO: implement safe, fast and transparent native call apparatus using flag bits/pointer tagging
                //eg p = 0b000...111101111000 use last bits to encode flags (is this pointer a native call ect..)

                const j_instruction: InstructionI = @bitCast(instruction);

                const base: i64 = @bitCast(self.registers[j_instruction.rs1]);
                const offset: i64 = @as(i12, @bitCast(j_instruction.imm));

                const jump_address = base + offset;

                //return address
                self.setRegister(j_instruction.rd, @intFromPtr(program_counter) + 4);

                const Result = packed struct(i64) {
                    zero: u1,
                    rest: u63,
                };

                var result: Result = @bitCast(jump_address);

                //TODO: use low bit of function pointers to indicate native calling
                if (result.zero == 1) {
                    //call native procedure
                    std.log.info("hart: Native call reached, a0={}", .{self.registers[10]});

                    //encode 48bit address space into upper 48 bits of the address, leaving the last 16 bits for 'metadata'

                    const encoded_address: u64 = @bitCast(result);

                    const native_procedure = nativeCallPointer(encoded_address);

                    native_procedure(self);

                    //jump to next instruction after jalr, emulating the effect of a ret
                    program_counter += 1;

                    continue;
                }

                result.zero = 0;

                const actual_address: u64 = @bitCast(result);

                //TODO: when jalring to a special address, yield the interpreter (to be used when the host calls into the vm)
                if (actual_address == 0) {
                    return;
                }

                program_counter = @ptrFromInt(actual_address);
            },
            .system => {
                const i_instruction: InstructionI = @bitCast(instruction);

                //Make hart program counter coherent so that ecalls and ebreaks can read it
                self.program_counter = program_counter;

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

                program_counter += 1;
            },
            .op_fp => unreachable,
            .load_fp => unreachable,
            .store_fp => unreachable,
            .amo => {
                const r_instruction: InstructionR = @bitCast(instruction);
                const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

                switch (masked_instruction) {
                    .lr_w_aq_rl => {
                        const pointer: *const i32 = @ptrFromInt(self.registers[r_instruction.rs1]);

                        const result: i64 = @atomicLoad(i32, pointer, std.builtin.AtomicOrder.Acquire);

                        self.setRegister(r_instruction.rd, @bitCast(result));
                    },
                    else => unreachable,
                }

                program_counter += 1;
            },
            .misc_mem => {
                //TODO: handle fences
                //For X86-64, a fence is a no-op*

                program_counter += 1;
            },
            _ => {
                return error.UnsupportedInstruction;
            },
        }
    }
}

///Debug the execution of an instruction
inline fn debugInstruction(self: *const Hart, instruction: u32) void {
    const instruction_generic: InstructionGeneric = @bitCast(instruction);

    std.log.info("Executing instruction: encoded as: 0x{x}", .{instruction});

    switch (instruction_generic.opcode) {
        .lui => {
            const u_instruction: InstructionU = @bitCast(instruction);

            std.log.info("lui x{}, {}", .{ u_instruction.rd, u_instruction.imm });
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

            std.log.info("auipc x{}, {} (address = 0x{})", .{ u_instruction.rd, sign_extended_offset, actual_address });
        },
        .op => {
            const r_instruction: InstructionR = @bitCast(instruction);
            const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

            switch (masked_instruction) {
                .add => {
                    std.log.info("add x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sub => {
                    std.log.info("sub x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .@"and" => {
                    std.log.info("and x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .@"or" => {
                    std.log.info("or x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .xor => {
                    std.log.info("xor x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sll => {
                    std.log.info("sll x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .slt => {
                    std.log.info("sll x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sltu => {
                    std.log.info("sltu x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .srl => {
                    std.log.info("srl x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sra => {
                    std.log.info("sra x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .mul => {
                    std.log.info("mul x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .mulhu => {
                    std.log.info("mulhu x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .remu => {
                    std.log.info("remu x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .addw => unreachable,
                .subw => unreachable,
                .sllw => unreachable,
                .srlw => unreachable,
                .sraw => unreachable,
                .mulw => unreachable,
                .divw => unreachable,
                .lr_w_aq,
                .lr_w_rl,
                .sc_w_aq,
                .sc_w_rl,
                .amoswap_w_aq,
                .amoswap_w_rl,
                => unreachable,
                .mulh => unreachable,
                .mulhsu => unreachable,
                .div => unreachable,
                .divu => {
                    std.log.info("divu x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .rem => unreachable,
                .divuw => unreachable,
                .remw => unreachable,
                .remuw => unreachable,
                else => unreachable,
            }
        },
        .op_32 => {
            const r_instruction: InstructionR = @bitCast(instruction);
            const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

            switch (masked_instruction) {
                .addw => {
                    std.log.info("addw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .subw => {
                    std.log.info("subw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sllw => {
                    std.log.info("sllw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .srlw => unreachable,
                .sraw => unreachable,
                .mulw => {
                    std.log.info("mulw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .divw => unreachable,
                .divuw => {
                    std.log.info("divuw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                else => unreachable,
            }
        },
        .op_imm => {
            const i_instruction: InstructionI = @bitCast(instruction);
            const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

            const immediate: i64 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

            switch (masked_instruction) {
                .addi => {
                    std.log.info("addi x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .slti => unreachable,
                .sltiu => {
                    std.log.info("sltiu x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .xori => {
                    std.log.info("xori x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .ori => unreachable,
                .andi => {
                    std.log.info("andi x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .lb => unreachable,
                .lh => unreachable,
                .lw => unreachable,
                .lbu => unreachable,
                .lhu => unreachable,
                .ld => unreachable,
                .lwu => unreachable,
                .addiw => unreachable,
                .slliw => unreachable,
                .srliw_and_sraiw => unreachable,
                .slli => {
                    const Immediate = packed struct(u12) {
                        shamt: u6,
                        funct6: u6,
                    };

                    const imm: Immediate = @bitCast(i_instruction.imm);

                    std.log.info("slli x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, imm.shamt });
                },
                .srli_and_srai => {
                    const Immediate = packed struct(u12) {
                        shamt: u6,
                        funct6: u6,
                    };

                    const imm: Immediate = @bitCast(i_instruction.imm);

                    switch (imm.funct6) {
                        0b000000 => {
                            std.log.info("srli x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, imm.shamt });
                        },
                        0b010000 => {
                            std.log.info("srai x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, imm.shamt });
                        },
                        else => unreachable,
                    }
                },
            }
        },
        .op_imm32 => {
            const i_instruction: InstructionI = @bitCast(instruction);
            const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

            const immediate: i32 = @intCast(@as(i12, @bitCast(i_instruction.imm)));

            switch (masked_instruction) {
                .addiw => {
                    //effectively sign extends the immedidate by casting to i12 then to i64 (full width)

                    std.log.info("addi x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .slliw => {
                    std.log.info("slliw x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .srliw_and_sraiw => {
                    const Immediate = packed struct(u12) {
                        shamt: u6,
                        funct6: u6,
                    };

                    const imm: Immediate = @bitCast(i_instruction.imm);

                    switch (imm.funct6) {
                        0b000000 => {
                            std.log.info("srliw x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, imm.shamt });
                        },
                        0b010000 => {
                            std.log.info("sraiw x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, imm.shamt });
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .load => {
            const i_instruction: InstructionI = @bitCast(instruction);
            const masked_instruction: IInstructionMask = @enumFromInt(instruction & IInstructionMask.removing_mask);

            const base: i64 = @bitCast(self.registers[i_instruction.rs1]);
            const offset: i64 = @as(i12, @bitCast(i_instruction.imm));
            const actual: u64 = @bitCast(base + offset);

            switch (masked_instruction) {
                .lb => {
                    std.log.info("lb x{}, x{} + {}", .{ i_instruction.rd, i_instruction.rs1, offset });
                },
                .lh => {
                    std.log.info("lh x{}, x{} + {}", .{ i_instruction.rd, i_instruction.rs1, offset });
                },
                .lw => {
                    std.log.info("lw x{}, x{} + {}", .{ i_instruction.rd, i_instruction.rs1, offset });
                },
                .lbu => {
                    std.log.info("lbu x{}, x{} + {}", .{ i_instruction.rd, i_instruction.rs1, offset });
                },
                .lhu => {
                    std.log.info("lhu x{}, x{} + {} (address = 0x{x})", .{ i_instruction.rd, i_instruction.rs1, offset, actual });
                },
                .lwu => {
                    std.log.info("lwu x{}, {}(x{})(address = 0x{x})", .{ i_instruction.rd, offset, i_instruction.rs1, actual });
                },
                .ld => {
                    std.log.info("ld x{}, {}(x{}) (address = 0x{x})", .{ i_instruction.rd, offset, i_instruction.rs1, actual });
                },
                else => unreachable,
            }
        },
        .store => {
            const s_instruction: InstructionS = @bitCast(instruction);
            const masked_instruction: SInstructionMask = @enumFromInt(instruction & SInstructionMask.removing_mask);

            const immediate: packed struct(i12) {
                lower: u5,
                upper: u7,
            } = .{ .lower = s_instruction.imm, .upper = s_instruction.imm_1 };

            const offset: i64 = @as(i12, @bitCast(immediate));
            const base: i64 = @bitCast(self.registers[s_instruction.rs1]);
            const actual: u64 = @bitCast(base + offset);
            _ = actual; // autofix

            switch (masked_instruction) {
                .sb => {
                    std.log.info("sb x{}, x{} + 0x{x}", .{ s_instruction.rs2, s_instruction.rs2, s_instruction.imm });
                },
                .sh => {
                    std.log.info("sh x{}, x{} + 0x{x}", .{ s_instruction.rs2, s_instruction.rs1, s_instruction.imm });
                },
                .sw => {
                    std.log.info("sw x{}, x{} + 0x{x}", .{ s_instruction.rs2, s_instruction.rs2, s_instruction.imm });
                },
                .sd => {
                    std.log.info("sd x{}, x{} + 0x{x} (address = {})", .{ s_instruction.rs2, s_instruction.rs1, s_instruction.imm, self.registers[s_instruction.rs1] + s_instruction.imm });
                },
            }
        },
        .branch => {
            const b_instruction: InstructionB = @bitCast(instruction);
            const masked_instruction: BInstructionMask = @enumFromInt(instruction & BInstructionMask.removing_mask);

            const AddressImmediateUpper = packed struct(u7) {
                imm10_5: i6,
                imm12: i1,
            };

            const AddressImmediateLower = packed struct(u5) {
                imm11: i1,
                imm4_1: i4,
            };

            const imm_lower: AddressImmediateLower = @bitCast(b_instruction.imm);
            const imm_upper: AddressImmediateUpper = @bitCast(b_instruction.imm_1);

            const ReconstitudedImmediate = packed struct(i13) {
                imm0: i1 = 0,
                imm4_1: i4,
                imm10_5: i6,
                imm11: i1,
                imm12: i1,
            };

            const imm_reconstituted: ReconstitudedImmediate = .{
                .imm11 = imm_lower.imm11,
                .imm4_1 = imm_lower.imm4_1,
                .imm10_5 = imm_upper.imm10_5,
                .imm12 = imm_upper.imm12,
            };

            switch (masked_instruction) {
                .beq => {
                    const CombinedImmediate = packed struct(i13) {
                        zero: u1 = 0,
                        imm_0: u5,
                        imm_1: u7,
                    };

                    const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                    std.log.info("beq x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
                .bne => {
                    const CombinedImmediate = packed struct(i13) {
                        zero: u1 = 0,
                        imm_0: u5,
                        imm_1: u7,
                    };

                    const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                    std.log.info("bne x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
                .blt => {
                    const CombinedImmediate = packed struct(i13) {
                        zero: u1 = 0,
                        imm_0: u5,
                        imm_1: u7,
                    };

                    const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                    std.log.info("bne x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
                .bge => {
                    const combined_immediate: i13 = @bitCast(imm_reconstituted);

                    std.log.info("bge x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
                .bltu => {
                    const combined_immediate: i13 = @bitCast(imm_reconstituted);

                    std.log.info("bltu x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
                .bgeu => {
                    const CombinedImmediate = packed struct(i13) {
                        zero: u1 = 0,
                        imm_0: u5,
                        imm_1: u7,
                    };

                    const combined_immediate: i13 = @bitCast(CombinedImmediate{ .imm_0 = b_instruction.imm, .imm_1 = b_instruction.imm_1 });

                    std.log.info("bltu x{}, x{}, {}", .{ b_instruction.rs1, b_instruction.rs2, combined_immediate });
                },
            }
        },
        .jal => {
            const j_instruction: InstructionJ = @bitCast(instruction);

            std.log.info("jal x{}, pc + 0x{x}", .{ j_instruction.rd, j_instruction.imm });
        },
        .jalr => {
            const j_instruction: InstructionI = @bitCast(instruction);

            std.log.info("jalr x{}, x{} + 0x{x}", .{ j_instruction.rd, j_instruction.rs1, j_instruction.imm });
        },
        .system => {
            const i_instruction: InstructionI = @bitCast(instruction);

            switch (i_instruction.imm) {
                //ecall
                0 => {
                    std.log.info("ecall", .{});
                },
                //ebreak
                1 => {
                    std.log.info("ebreak", .{});
                },
                else => {},
            }
        },
        .amo => {
            const r_instruction: InstructionR = @bitCast(instruction);
            const masked_instruction: RInstructionMask = @enumFromInt(instruction & RInstructionMask.removing_mask);

            switch (masked_instruction) {
                .lr_w_aq_rl => {
                    std.log.info("lr.w.aq.rl x{}, x{}", .{ r_instruction.rd, r_instruction.rs1 });
                },
                else => {
                    std.log.info("Unknown instruction = {b}", .{instruction_generic.opcode});
                },
            }
        },
        else => {
            std.log.info("Unknown instruction = {b}", .{instruction_generic.opcode});
        },
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
    sd = @bitCast(InstructionS{
        .opcode = 0b0100011,
        .funct3 = 0b011,
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
    addw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b000,
        .funct7 = 0b0000000,
    }),
    subw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b000,
        .funct7 = 0b0100000,
    }),
    sllw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b001,
        .funct7 = 0b0000000,
    }),
    srlw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b101,
        .funct7 = 0b0000000,
    }),
    sraw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b101,
        .funct7 = 0b0100000,
    }),
    mul = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b000,
        .funct7 = 0b0000001,
    }),
    mulh = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b001,
        .funct7 = 0b0000001,
    }),
    mulhsu = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b010,
        .funct7 = 0b0000001,
    }),
    mulhu = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b011,
        .funct7 = 0b0000001,
    }),
    mulw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b000,
        .funct7 = 0b0000001,
    }),
    div = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b100,
        .funct7 = 0b0000001,
    }),
    divu = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b101,
        .funct7 = 0b0000001,
    }),
    rem = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b110,
        .funct7 = 0b0000001,
    }),
    remu = @bitCast(InstructionR{
        .opcode = 0b0110011,
        .funct3 = 0b111,
        .funct7 = 0b0000001,
    }),
    divw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b100,
        .funct7 = 0b0000001,
    }),
    divuw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b101,
        .funct7 = 0b0000001,
    }),
    remw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b110,
        .funct7 = 0b0000001,
    }),
    remuw = @bitCast(InstructionR{
        .opcode = 0b0111011,
        .funct3 = 0b111,
        .funct7 = 0b0000001,
    }),
    lr_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00010_10,
    }),
    lr_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00010_01,
    }),
    lr_w_aq_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00010_11,
    }),
    sc_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00011_10,
    }),
    sc_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00011_01,
    }),
    amoswap_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00001_10,
    }),
    amoswap_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00001_01,
    }),
    amoadd_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00000_10,
    }),
    amoadd_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00000_01,
    }),
    amoxor_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00100_10,
    }),
    amoxor_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b00100_01,
    }),
    amoand_w_aq = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b01100_10,
    }),
    amoand_w_rl = @bitCast(InstructionR{
        .opcode = 0b0101111,
        .funct3 = 0b010,
        .funct7 = 0b01100_01,
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
    ld = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b011,
    }),
    lwu = @bitCast(InstructionI{
        .opcode = 0b0000011,
        .funct3 = 0b110,
    }),
    addiw = @bitCast(InstructionI{
        .opcode = 0b0011011,
        .funct3 = 0b000,
    }),
    slli = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b001,
    }),
    srli_and_srai = @bitCast(InstructionI{
        .opcode = 0b0010011,
        .funct3 = 0b101,
    }),
    slliw = @bitCast(InstructionI{
        .opcode = 0b0011011,
        .funct3 = 0b001,
    }),
    srliw_and_sraiw = @bitCast(InstructionI{
        .opcode = 0b0011011,
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
    ecall_handler: ?fn (vm: *Hart) InterruptResult = null,
    ebreak_handler: ?fn (vm: *Hart) InterruptResult = null,
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
///TODO: least significant bits of this opcode don't change in the standard ISA, so no need to dispatch those last two bits
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
    amo = 0b01_011_11,
    misc_mem = 0b00_011_11,
    _,
};

const Hart = @This();
const std = @import("std");
