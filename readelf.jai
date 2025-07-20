#import "Basic";
#import "File";
#import "String";


col_reset :: () -> string {
    return "\e[0m";
}
col_string :: () -> string {
    return "\e[36m";
}

readelf :: (file: string) -> success: bool {
    print("=== % ===\n", file);
    // TODO: Check if mmap() the file is quicker
    file_data, success := read_entire_file(file);
    defer free(file_data);
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

    sections_raw : *Elf_Section_Header = null;
    if elf_header.section_header_offset > 0 {

        if elf_header.section_header_entry_size != size_of(Elf_Section_Header) {
            log_error("Section header entry size does not match. Got %, expected %", elf_header.section_header_entry_size, size_of(Elf_Section_Header));
            return false;
        }

        sections_raw = cast(*Elf_Section_Header)(file_data.data + elf_header.section_header_offset);
        sections: []Elf_Section_Header = .{section_header_count(elf_header, sections_raw), sections_raw};

        name_index := section_names_index(elf_header, sections_raw);
        if name_index >= sections.count {
            log_error("Section names index is outside of bounds of the sections");
            return false;
        }

        section_names_section := sections[name_index];
        section_names_table := slice(file_data, xx section_names_section.offset, xx section_names_section.size);
        print_sections(sections, file_data, section_names_table);
    }

    if elf_header.program_header_entry_size != size_of(Elf_Program_Header) {
        log_error("Program header entry size does not match. Got %, expected %", elf_header.program_header_entry_size, size_of(Elf_Program_Header));
        return false;
    }

    if elf_header.program_header_offset > 0 {
        program_header_raw := cast(*Elf_Program_Header)(file_data.data + elf_header.program_header_offset);
        program_headers : []Elf_Program_Header = .{program_header_count(elf_header, sections_raw), program_header_raw};
        print("% Program Headers:\n", program_headers.count);
        print_program_headers(program_headers, file_data);
    }

    return true;
}

string_from_table :: (table: string, offset: u32) -> string {
    // print("table = %, size %, offset = %\n", table, table.count, offset);
    if offset == 0 return "";
    if offset > table.count return "";
    return to_string(table.data + offset);
}

right_pad :: (s: string, len: int) -> string {
    if s.count >= len  return s;
    out := talloc_string(len);
    memcpy(out.data, s.data, s.count);
    memset(out.data + s.count, " ", out.count - s.count);
    return out;
}

print_program_headers :: (program_headers: []Elf_Program_Header, file_data: string) {
    for ph : program_headers {
        print(" -- %\n", ph);
        data := slice(file_data, xx ph.offset, xx ph.filesz);
        print_printable_data(data);
    }
}

print_sections :: (sections: []Elf_Section_Header, file_data: string, section_names_table: string) {
    for section : sections {
        name := string_from_table(section_names_table, section.name_offset);
        print(" -- Section %: %  %\n", formatInt(it_index, minimum_digits=2), right_pad(name, 16), section);
        data := slice(file_data, xx section.offset, xx section.size);
        print_printable_data(data);
        if section.type == {
            case .SYMTAB; #through;
            case .DYNSYM;
                symbol_table : []Elf_Symbol;
                symbol_table.data = xx data.data;
                symbol_table.count = data.count / size_of(Elf_Symbol);
                if symbol_table.count * size_of(Elf_Symbol) != data.count {
                    log_error("Invalid symbol table size, not a multiple of %", size_of(Elf_Symbol));
                    continue;
                }

                string_section := sections[section.link];
                string_table := slice(file_data, xx string_section.offset, xx string_section.size);

                for sym : symbol_table {
                    name := string_from_table(string_table, sym.name_offset);
                    type := get_type(sym);
                    binding := get_binding(sym);
                    visibility := get_visibility(sym);
                    sym_section := ifx sym.section_index < sections.count then sections[sym.section_index] else .{};
                    sym_section_name := string_from_table(section_names_table, sym_section.name_offset);

                    print(" ---- Symbol %: %@%  %  %  %  section=% %  value=% size=%\n",
                            formatInt(it_index, minimum_digits=2), right_pad(name, 15), sym.name_offset,
                            type, binding, visibility, sym.section_index, sym_section_name,
                            sym.value, sym.size);
                }
            case .REL;
                relocs : []Elf64_Relocation;
                relocs.data = xx data.data;
                relocs.count = data.count / size_of(Elf64_Relocation);
                if relocs.count * size_of(Elf64_Relocation) != data.count {
                    log_error("Invalid relocation table size, not a multiple of %", size_of(Elf64_Relocation));
                    continue;
                }
                for relocs {
                    print(" ---- Relocation no addend: %\n", it);
                }
            case .RELA;
                relocs : []Elf64_RelocationA;
                relocs.data = xx data.data;
                relocs.count = data.count / size_of(Elf64_RelocationA);
                if relocs.count * size_of(Elf64_RelocationA) != data.count {
                    log_error("Invalid relocation table size, not a multiple of %", size_of(Elf64_Relocation));
                    continue;
                }
                for relocs {
                    print(" ---- Relocations: %\n", it);
                }
        }
    }
}

print_printable_data :: (data: string) {
    // If it looks printable, print it
    strings : [..]string;
    defer array_free(strings);

    printable := true;
    begin := 0;
    for data {
        if it == {
        case 0;
            str := slice(data, begin, it_index - begin);
            if strings.count == 0 || str != strings.data[strings.count-1] {
                array_add(*strings, str);
            }
            begin = it_index + 1;
        case;
            if !is_print(it) {
                printable = false;
                break;
            }
        }
    }

    if printable {
        if begin < data.count {
            str := slice(data, begin, data.count - begin);
            if strings.count == 0 || str != strings.data[strings.count-1] {
                array_add(*strings, str);
            }
        }
        if strings.count > 0 {
            print("       %2%1%3\n", strings, col_string(), col_reset());
        }
    }
}
