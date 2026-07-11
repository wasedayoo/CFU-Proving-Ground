int rand() { static int seed = 1; seed = seed * 1103515245 + 12345; return (seed >> 16) & 0x7FFF; }
