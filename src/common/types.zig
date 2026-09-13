pub const pid_t = i32;

pub const iovec = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

pub const user_pt_regs = extern struct {
    regs: [31]u64,
    sp: u64,
    pc: u64,
    pstate: u64,
};

pub const user_regs_struct = extern struct {
    r15: u64, r14: u64, r13: u64, r12: u64,
    rbp: u64, rbx: u64, r11: u64, r10: u64,
    r9: u64, r8: u64, rax: u64, rcx: u64,
    rdx: u64, rsi: u64, rdi: u64, orig_rax: u64,
    rip: u64, cs: u64, eflags: u64, rsp: u64,
    ss: u64, fs_base: u64, gs_base: u64,
    ds: u64, es: u64, fs: u64, gs: u64,
};
