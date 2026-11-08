unsigned __gnat_grow (unsigned pages) {
   unsigned prev = __builtin_wasm_memory_grow (0, pages);
   if (prev == 0xffffffffu) {
      return 0;
   }
   return prev - pages;
}

char ds_exc[512];
unsigned ds_exc_len;
unsigned ds_exc_line;

void __gnat_put_exception (const char *msg, unsigned size, unsigned line) {
   unsigned n = size < 511u ? size : 511u;
   unsigned i;
   for (i = 0; i < n; i++) {
      ds_exc[i] = msg[i];
   }
   ds_exc[n] = 0;
   ds_exc_len = n;
   ds_exc_line = line;
}

int isatty (int fd) {
   (void) fd;
   return 0;
}

int tcgetpgrp (int fd) {
   (void) fd;
   return 0;
}

int getpgrp (void) {
   return 0;
}

long write (int fd, const void *buf, unsigned n) {
   (void) fd;
   (void) buf;
   return (long) n;
}

/* 64x64 -> 128 multiply. Written out of 32-bit products so it does not call itself. */
static unsigned long long mul_hi (unsigned long long a, unsigned long long b) {
   unsigned long long a0 = a & 0xffffffffull;
   unsigned long long a1 = a >> 32;
   unsigned long long b0 = b & 0xffffffffull;
   unsigned long long b1 = b >> 32;
   unsigned long long p0 = a0 * b0;
   unsigned long long p1 = a0 * b1;
   unsigned long long p2 = a1 * b0;
   unsigned long long p3 = a1 * b1;
   unsigned long long mid = (p0 >> 32) + (p1 & 0xffffffffull) + (p2 & 0xffffffffull);
   return p3 + (p1 >> 32) + (p2 >> 32) + (mid >> 32);
}

unsigned __int128 __multi3 (unsigned __int128 left, unsigned __int128 right) {
   unsigned long long a0 = (unsigned long long) left;
   unsigned long long a1 = (unsigned long long) (left >> 64);
   unsigned long long b0 = (unsigned long long) right;
   unsigned long long b1 = (unsigned long long) (right >> 64);
   unsigned long long lo = a0 * b0;
   unsigned long long hi = mul_hi (a0, b0) + a0 * b1 + a1 * b0;
   return ((unsigned __int128) hi << 64) | lo;
}

/* System.IO, used by the runtime, not by the preview transcript. */
void __gnat_put_char (int c) {
   (void) c;
}

void __gnat_put_string (const char *s, int n) {
   (void) s;
   (void) n;
}
