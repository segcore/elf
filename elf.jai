#import "Basic";
#import "String";
#import "File";
#import "executable_formats";

SHN_UNDEF :: 0;

Elf_Program_Header_Type :: enum u32 {
    NULL :: 0;
    LOAD :: 1;
};

Elf_Program_Header_Flag :: enum u32 {
    X :: 1;
    W :: 2;
    R :: 4;
};

Elf_Program_Header :: struct(Offset_Type: Type = u64) {
    type:   Elf_Program_Header_Type;
    flags:  Elf_Program_Header_Flag;
    offset: Offset_Type;
    vaddr:  Offset_Type;
    paddr:  Offset_Type;
    filesz: Offset_Type;
    memsz:  Offset_Type;
    align:  Offset_Type;
};


write_raw :: (file: *File, val: $T) -> u64, bool #expand {
    return size_of(T), file_write(file, *val, size_of(T));
}

generate_exe_truefalse :: (path: string, program: bool) -> bool {
    out, ok := file_open(path, for_writing = true);
    if !ok { log("Failed to open %", path); return false; }
    defer file_close(*out);

    /*
       0:   f3 0f 1e fa             endbr64
       4:   48 c7 c0 3c 00 00 00    mov    rax,60
       b:   48 c7 c7 45 00 00 00    mov    rdi,69
      19:   0f 05                   syscall
      1b:   90                      nop
      1c:   0f 0b                   ud2
    */
    exe_return_value := cast(u8) ifx program then 0 else 1;
    machine_code := u8.[
        // syscall(SYS_exit, exe_return_value)
        0x48, 0xc7, 0xc0, 0x3c, 0x00, 0x00, 0x00,
        0x48, 0xc7, 0xc7, exe_return_value, 0x00, 0x00, 0x00,
        0x0f, 0x05,
    ];

    elf_header : Elf_Header_64;
    program_header_offset : u64 : size_of(Elf_Header_64);
    segment_begin : u64 : program_header_offset + size_of(Elf_Program_Header);

    // 0x10000 seems to be the smallest supported virtual address we can use
    vaddr :: 0x10000 + segment_begin;
    entry_location : u64 = vaddr;

    elf_header.ident.magic = 0x7f | (#char "E" << 8) | (#char "L" << 16) | (#char "F" << 24);
    elf_header.ident.class = ._64_BIT;
    elf_header.ident.data = .LSB;
    elf_header.ident.version = 1;
    elf_header.ident.os_abi = .SYSTEM_V;
    elf_header.ident.abi_version = 0;

    elf_header.type = .EXEC;
    elf_header.machine = .AMD_x64;
    elf_header.version = 1;
    elf_header.entry = entry_location;
    elf_header.program_header_offset = program_header_offset;
    elf_header.flags = 0;
    elf_header.ehsize = size_of(Elf_Header_64);
    elf_header.phentsize = size_of(Elf_Program_Header);
    elf_header.phnum = 1;
    elf_header.section_header_entry_size = 0; // non-zero if containing sections
    elf_header.num_section_headers = 0;
    elf_header.section_names_section_index = SHN_UNDEF; // non-zero if containing sections

    program_header : Elf_Program_Header;
    program_header.type = .LOAD;
    program_header.flags = 0;
    program_header.offset = segment_begin;
    program_header.vaddr = vaddr;
    program_header.paddr = vaddr;
    program_header.filesz = xx machine_code.count;
    program_header.memsz = xx machine_code.count;
    program_header.flags = .X; // | .R;
    program_header.align = 16;

    nowsize : u64 = 0;
    nowsize += write_raw(*out, elf_header);
    nowsize += write_raw(*out, program_header);
    ok = file_write(*out, cast(string)machine_code);
    if !ok { log("Failed to write data"); }

    return ok;
}

main :: () {
    generate_exe_truefalse("true", true);
    generate_exe_truefalse("false", false);
}
