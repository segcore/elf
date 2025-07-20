#import "Basic";
#import "String";
#import "File";
#import "executable_formats";
#load "write_truefalse.jai";
#load "readelf.jai";

SHN_UNDEF :: 0;

ELF_MAGIC :: u8.[0x7f, "E", "L", "F"];

Elf64_Header :: struct {
    ident: struct {
        magic:       [4] u8;
        class:       Elf_Class;
        data:        Elf_Endianness;
        version:     u8;
        os_abi:      Elf_Abi;
        abi_version: u8;
        pad:         [7] u8;
    }

    type:                        Elf_Type;
    machine:                     Elf_Machine;
    version:                     u32;
    entry:                       u64;

    program_header_offset:       u64; //phoff
    section_header_offset:       u64; //shoff
    flags:                       u32;
    elf_header_size:             u16; // ehsize
    program_header_entry_size:   u16; // phentsize

    // If count >= 0xffff, stores 0xffff, and section_header_table.sh_info has the real value
    program_header_count:        u16; // phnum
    section_header_entry_size:   u16; // shentsize

    // If count >= 0xff00, stores 0, and section_header_table.sh_size has the real value
    section_header_count:        u16; // shnum

    // If index >= 0xff00, stores 0xffff, and section_header_table.sh_link has the real value
    section_names_section_index: u16; // shstrndx
}

program_header_count :: (header: Elf64_Header, first_section: *Elf_Section_Header) -> int {
    if header.program_header_count < 0xffff return header.program_header_count;
    else if first_section return first_section.info;
    else return 0;
}

section_header_count :: (header: Elf64_Header, first_section: Elf_Section_Header) -> int {
    if header.section_header_count < 0xff00 return header.section_header_count;
    else return xx first_section.size;
}

section_names_index :: (header: Elf64_Header, first_section: Elf_Section_Header) -> int {
    if header.section_names_section_index < 0xff00 return header.section_names_section_index;
    else return first_section.link;
}

// From the standard library, we use
//  Elf_Section_Header
//  Elf_Symbol

Elf_Program_Header_Type :: enum u32 {
    NULL    :: 0;       /* Program header table entry unused */
    LOAD    :: 1;       /* Loadable program segment */
    DYNAMIC :: 2;       /* Dynamic linking information */
    INTERP  :: 3;       /* Program interpreter */
    NOTE    :: 4;       /* Auxiliary information */
    SHLIB   :: 5;       /* Reserved */
    PHDR    :: 6;       /* Entry for header table itself */
    TLS     :: 7;       /* Thread-local storage segment */
    LOOS    :: 0x60000000;          /* Start of OS-specific */
    GNU_EH_FRAME    :: 0x6474e550;  /* GCC .eh_frame_hdr segment */
    GNU_STACK       :: 0x6474e551;  /* Indicates stack executability */
    GNU_RELRO       :: 0x6474e552;  /* Read-only after relocation */
    GNU_PROPERTY    :: 0x6474e553;  /* GNU property */
};

Elf_Program_Header_Flag :: enum_flags u32 {
    X :: 1;
    W :: 2;
    R :: 4;
};

Elf_Program_Header :: struct(Offset_Type: Type = u64) {
    type:   Elf_Program_Header_Type;  /* Segment type */
    flags:  Elf_Program_Header_Flag;  /* Segment flags */
    offset: Offset_Type;              /* Segment file offset */
    vaddr:  Offset_Type;              /* Segment virtual address */
    paddr:  Offset_Type;              /* Segment physical address */
    filesz: Offset_Type;              /* Segment size in file */
    memsz:  Offset_Type;              /* Segment size in memory */
    align:  Offset_Type;              /* Segment alignment */
};

Elf64_Relocation :: struct {
    address:   u64;
    type:      Elf_Relocation_Type;
    symbol_id: Elf_Symbol_Id;
}

Elf64_RelocationA :: struct {
    using reloc: Elf64_Relocation;
    addend:    s64;
}


main :: () {
    generate_exe_truefalse("true", true);
    generate_exe_truefalse("false", false);

    for arg : get_command_line_arguments() {
        if it_index == 0 continue;
        readelf(arg);
    }
}
