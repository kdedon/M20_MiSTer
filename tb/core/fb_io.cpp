// Frame buffer for tb_core: pixels set one at a time, dumped as binary PPM
// (Verilator's $fwrite drops NUL bytes).  fb_hash lets the bench skip
// dumping frames identical to the last one written.
#include <cstdio>
#include <cstdint>
#include <cstring>

namespace {
constexpr int W = 1024, H = 512;
uint8_t fb[H][W][3];
}

extern "C" void fb_set(int x, int y, int rgb) {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  fb[y][x][0] = static_cast<uint8_t>(rgb >> 16);
  fb[y][x][1] = static_cast<uint8_t>(rgb >> 8);
  fb[y][x][2] = static_cast<uint8_t>(rgb);
}

extern "C" int fb_hash(int w, int h) {
  uint32_t x = 2166136261u;
  for (int y = 0; y < h && y < H; y++)
    for (int i = 0; i < w * 3 && i < W * 3; i++) x = (x ^ fb[y][i / 3][i % 3]) * 16777619u;
  return static_cast<int>(x);
}

extern "C" int fb_dump(const char *path, int w, int h) {
  if (w > W) w = W;
  if (h > H) h = H;
  FILE *f = std::fopen(path, "wb");
  if (!f) return -1;
  std::fprintf(f, "P6\n%d %d\n255\n", w, h);
  for (int y = 0; y < h; y++) std::fwrite(fb[y], 3, static_cast<size_t>(w), f);
  std::fclose(f);
  return 0;
}
