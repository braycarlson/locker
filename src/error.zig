pub const LockerError = error{
    AllocationFailed,
    EmptyBuffer,
    HookFailed,
    IconLoadFailed,
    InvalidCapacity,
    LogOpenFailed,
    MenuCreationFailed,
    ModuleHandleNotFound,
    PatternTooLarge,
    TrayIconCreationFailed,
    WindowCreationFailed,
    WindowRegistrationFailed,
};
