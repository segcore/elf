#import "Basic";
#import "File";

readelf :: (file: string) -> success: bool {
    print("=== % ===\n", file);
    // TODO: Check if mmap() the file is quicker
    file_data, success := read_entire_file(file);
    if !success return false;
    if file_data.count < size_of(Elf64_Header) {
        log_error("File too small to contain an ELF header");
        return false;
    }

    elf_header := cast(*Elf64_Header) file_data.data;
    if memcmp(elf_header.ident.magic.data, ELF_MAGIC.data, ELF_MAGIC.count) != 0 {
        log_error("Invalid magic");
        return false;
    }
    print("ELF. Ident: %  %  version %  OS ABI: % version %\n", elf_header.ident.class, elf_header.ident.data, elf_header.ident.version, elf_header.ident.os_abi, elf_header.ident.abi_version);
    print("     %  Machine: %  version %   entry-point: %\n", elf_header.type, elf_header.machine, elf_header.version, elf_header.entry);
    print("     Program headers at byte:     %\n", elf_header.program_header_offset);
    print("     Section headers at byte:     %\n", elf_header.section_header_offset);
    print("     Flags:                       %\n", elf_header.flags);
    print("     ELF Header size:             %\n", elf_header.elf_header_size);
    print("     Program header size each:    %\n", elf_header.program_header_entry_size);
    print("     Program header count:        %\n", elf_header.program_header_count);
    print("     Section header size each:    %\n", elf_header.section_header_entry_size);
    print("     Section header count:        %\n", elf_header.section_header_count);
    print("     Section names in section:    %\n", elf_header.section_names_section_index);

    if elf_header.section_header_entry_size != size_of(Elf_Section_Header) {
        log_error("Section header entry size does not match");
        return false;
    }

    sections_raw := cast(*Elf_Section_Header)(file_data.data + elf_header.section_header_offset);
    sections: []Elf_Section_Header = .{elf_header.section_header_count, sections_raw};

    section_names_section := sections[elf_header.section_names_section_index];
    section_names_table := string.{xx section_names_section.size, file_data.data + section_names_section.offset};
    for section : sections {
        name := string_from_table(section_names_table, section.name_offset);
        print(" -- Section %: %  %\n", formatInt(it_index, minimum_digits=2), right_pad(name, 16), section);
    }

    return true;
}

string_from_table :: (table: string, offset: u32) -> string {
    return to_string(table.data + offset);
}

right_pad :: (s: string, len: int) -> string {
    if s.count >= len  return s;
    out := talloc_string(len);
    memcpy(out.data, s.data, s.count);
    memset(out.data + s.count, " ", out.count - s.count);
    return out;
}
