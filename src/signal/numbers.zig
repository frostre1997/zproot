pub const SIGTRAP: i32 = 5;
pub const SIGSYS: i32 = 31;
pub const SIGCHLD_FLAG: u64 = 17;

pub const ENOSYS: u64 = @bitCast(@as(i64, 38));
pub const NT_PRSTATUS: usize = 1;
