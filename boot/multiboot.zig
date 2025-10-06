pub const MultibootHeader = extern struct {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    end_tag: u64,
};

const MULTIBOOT2_MAGIC: u32 = 0xE85250D6;
const MULTIBOOT2_ARCHITECTURE: u32 = 0; // i386

export const multiboot_header align(8) linksection(".multiboot") = MultibootHeader{
    .magic = MULTIBOOT2_MAGIC,
    .architecture = MULTIBOOT2_ARCHITECTURE,
    .header_length = @sizeOf(MultibootHeader),
    .checksum = ~(MULTIBOOT2_MAGIC +% MULTIBOOT2_ARCHITECTURE +% @sizeOf(MultibootHeader)) +% 1,
    .end_tag = 0,
};
