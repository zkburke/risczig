///Debug the execution of an instruction
inline fn debugInstruction(self: *const Hart, instruction: u32) void {
    const instruction_generic: Hart.InstructionGeneric = @bitCast(instruction);

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
                .srlw => {
                    std.log.info("srlw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
                .sraw => {
                    std.log.info("sraw x{}, x{}, x{}", .{ r_instruction.rd, r_instruction.rs1, r_instruction.rs2 });
                },
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
                .slti => {
                    std.log.info("slti x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .sltiu => {
                    std.log.info("sltiu x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .xori => {
                    std.log.info("xori x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
                .ori => {
                    std.log.info("ori x{}, x{}, {}", .{ i_instruction.rd, i_instruction.rs1, immediate });
                },
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
                    std.log.info("sb x{}, {}(x{})", .{ s_instruction.rs2, offset, s_instruction.rs1 });
                },
                .sh => {
                    std.log.info("sh x{}, {}(x{})", .{ s_instruction.rs2, offset, s_instruction.rs1 });
                },
                .sw => {
                    std.log.info("sw x{}, {}(x{})", .{ s_instruction.rs2, offset, s_instruction.rs1 });
                },
                .sd => {
                    std.log.info("sd x{}, {}(x{})", .{ s_instruction.rs2, offset, s_instruction.rs1 });
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

const InstructionU = Hart.InstructionU;
const InstructionI = Hart.InstructionI;
const InstructionB = Hart.InstructionB;
const InstructionR = Hart.InstructionR;
const InstructionS = Hart.InstructionS;
const InstructionJ = Hart.InstructionJ;

const RInstructionMask = Hart.RInstructionMask;
const IInstructionMask = Hart.IInstructionMask;
const BInstructionMask = Hart.BInstructionMask;
const SInstructionMask = Hart.SInstructionMask;

const Hart = @import("Hart.zig");
const std = @import("std");
