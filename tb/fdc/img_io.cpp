// Byte write into the bench's image file (Verilator's $fwrite drops NUL bytes).
#include <cstdio>

extern "C" int img_wr(const char *path, int off, char b) {
  FILE *f = std::fopen(path, "r+b");
  if (!f) return -1;
  std::fseek(f, off, SEEK_SET);
  std::fputc(static_cast<unsigned char>(b), f);
  std::fclose(f);
  return 0;
}
