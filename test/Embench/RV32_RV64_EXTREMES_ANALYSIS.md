# Embench 1.0 RV32/RV64 最大改善・最大悪化の分析

## 結論

- 最大改善は `aha-mont64`。score/MHz は `0.833444` から `1.794043`、比率は `2.152566`、変化率は `+115.257%` である。
- 最大悪化は `edn`。score/MHz は `0.819756` から `0.521335`、比率は `0.635964`、変化率は `-36.404%` である。
- `aha-mont64` の改善の主因は、64 bit整数演算をRV32の複数命令列からRV64の単一命令へ置き換えたことで、動的退役命令数が57.31%減ったことである。CPIは逆に8.82%悪化している。
- `edn` の悪化の主因はLP64のメモリ肥大ではなく、RV64乗算器のRTLレイテンシである。動的命令数は1.93%減った一方、573,417回の乗算がすべてRV64の7-cycle stall経路を通り、RV32との差5 cycle × 573,417回 = 2,867,085 cycleが非退役cycleの増分と完全一致する。

## 測定・解析条件

- Suite: Embench 1.0、commit `0466a18e4f6b47e19598d7c6ba72916d54b68f65`
- Compiler: xPack GNU RISC-V Embedded GCC 15.2.0-1
- RV32: `-march=rv32im -mabi=ilp32`
- RV64: `-march=rv64im -mabi=lp64`
- 共通: `-O2 -std=gnu99 -static -nostartfiles -ffunction-sections -fdata-sections -fno-unwind-tables -fno-asynchronous-unwind-tables`
- Link: `-Tapp/link.ld -Wl,--gc-sections -lm`
- Preprocessor: `CPU_MHZ=1`, `WARMUP_HEAT=1`
- `-mcmodel` は明示しておらず、両方ともGCCの既定値を使用する。
- `main.c` は `pg_perf_enable()` 直後から `benchmark()` 完了までを測る。verify、表示、終了処理はscoreのcycleに含まれない。
- score/MHzは `baseline_ms × CPU_MHZ × 1000 / cycles`。同じベンチマークのRV64/RV32比は厳密に `RV32 cycles / RV64 cycles` と等しい。

根拠は `Makefile` 31--36行、60--86行、`main.c` 13--22行、`scripts/embench_score.py` 11--43行である。

### データモデル

| 型 | RV32 ILP32 | RV64 LP64 |
|---|---:|---:|
| `char` | 8 bit | 8 bit |
| `short` | 16 bit | 16 bit |
| `int` | 32 bit | 32 bit |
| `long` | 32 bit | 64 bit |
| `long long` | 64 bit | 64 bit |
| pointer | 32 bit | 64 bit |

GCCの定義もRV32では `__SIZEOF_LONG__=4`, `__SIZEOF_POINTER__=4`、RV64ではそれぞれ8であった。`__SIZEOF_INT128__=16` はRV64だけで定義された。

## 全19ベンチマークの比較

| Benchmark | RV32 score/MHz | RV64 score/MHz | RV64/RV32 | Change [%] |
|---|---:|---:|---:|---:|
| aha-mont64 | 0.833444 | 1.794043 | 2.152566 | +115.257% |
| crc32 | 0.920971 | 0.767487 | 0.833345 | -16.665% |
| cubic | 0.305683 | 0.526222 | 1.721463 | +72.146% |
| edn | 0.819756 | 0.521335 | 0.635964 | -36.404% |
| huffbench | 1.650275 | 1.647069 | 0.998057 | -0.194% |
| matmult-int | 0.917824 | 0.644530 | 0.702237 | -29.776% |
| minver | 0.572114 | 0.702086 | 1.227178 | +22.718% |
| nbody | 0.591580 | 0.933911 | 1.578672 | +57.867% |
| nettle-aes | 0.918137 | 0.769649 | 0.838273 | -16.173% |
| nettle-sha256 | 1.028275 | 1.031938 | 1.003562 | +0.356% |
| nsichneu | 1.086825 | 1.087182 | 1.000328 | +0.033% |
| picojpeg | 0.966066 | 0.851653 | 0.881568 | -11.843% |
| qrduino | 1.228812 | 1.079348 | 0.878367 | -12.163% |
| sglib-combined | 1.369983 | 1.331525 | 0.971928 | -2.807% |
| slre | 1.485164 | 1.464404 | 0.986022 | -1.398% |
| st | 0.789895 | 1.126584 | 1.426245 | +42.625% |
| statemate | 2.422131 | 2.790436 | 1.152058 | +15.206% |
| ud | 0.802385 | 0.566748 | 0.706329 | -29.367% |
| wikisort | 1.586223 | 1.703680 | 1.074048 | +7.405% |

最大改善:

```text
Benchmark = aha-mont64
RV32      = 0.833444
RV64      = 1.794043
Change    = +115.257%
```

最大悪化:

```text
Benchmark = edn
RV32      = 0.819756
RV64      = 0.521335
Change    = -36.404%
```

## Cプログラムの性質

### `aha-mont64`

`mont64.c` は64×64→128 bit積、128 bit値の64 bit modulus、Montgomery multiplication、extended binary GCDを実行する。中心型は明示的な `uint64_t` と `int64_t` であり、64 bit shift、加減算、unsigned比較、carry処理、乗算を大量に使う。配列・structは中心ではなく、ポインタは128 bit積の上位・下位64 bitを書き戻す用途などに限られる。

重要な点は、RV32では64 bit値をレジスタ2本で表す必要がある一方、RV64では1本で表せることである。また `mulul64()` はRV64では `unsigned __int128`、RV32ではKnuth Algorithm Mのフォールバックを選ぶ。ソース上に除算相当のmodulus処理はあるが、生成コードの動的 `div/divu/rem/remu` は0回であり、shift/subtract loopで実現される。

### `edn`

`libedn.c` はFIR/IIR、dot product、lattice synthesis、JPEG DCTなどのDSPカーネルである。入力係数は主に `short` 配列、積は `short × short`、loop index・accumulator・出力配列・DCT一時配列は多数の `long int`、アクセスはpointer中心である。struct、明示的な `long long`、明示的な `int64_t` は中心処理にない。

したがってRV64 ISAの64 bit演算能力を本来必要とする処理というより、LP64によって `long` が意図せず64 bit化する処理である。乗算のオペランドは32 bitに整数昇格した値なので、RV64 GCCは主として `mulw` を生成する。

## 逆アセンブルの静的比較

`objdump -d -M no-aliases` で、実際に実行した各 `main.elf` のリンク後 `.text` を集計した。カテゴリは排他的で、W命令数だけはカテゴリに重なる補助指標である。

| Benchmark | Arch | 全命令 | ALU | load | store | branch | jump | shift | multiply | divide | W命令 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| aha-mont64 | RV32 | 721 | 402 | 54 | 45 | 47 | 42 | 74 | 57 | 0 | 0 |
| aha-mont64 | RV64 | 391 | 218 | 22 | 23 | 22 | 33 | 48 | 25 | 0 | 5 |
| edn | RV32 | 717 | 351 | 112 | 92 | 33 | 48 | 50 | 31 | 0 | 0 |
| edn | RV64 | 687 | 322 | 113 | 93 | 33 | 48 | 51 | 27 | 0 | 70 |

主要関数の静的命令数は次のとおりである。

| Benchmark/function | RV32 | RV64 | 備考 |
|---|---:|---:|---|
| aha `benchmark_body` | 402 | 197 | RV64は64 bit処理を大幅に短縮 |
| aha `montmul` | 101 | symbolなし | RV64ではbodyへ完全inline、RV32では1,269回call |
| edn `benchmark_body.isra.0` | 168 | 172 | RV64が4命令増加 |
| edn `fir` | 21 | 21 | 命令数同じ、`mul`→`mulw`, `sw`→`sd` |
| edn `fir_no_red_ld` | 33 | 33 | 命令数同じ、乗算は主に`mulw` |
| edn `iir1` | 25 | 25 | 命令数同じ |
| edn `jpegdct` | 194 | 194 | 命令数同じ |
| edn `verify_benchmark` | 45 | 42 | 測定区間外 |

ELFの関数全体ではahaが721→391命令（-45.77%）、ednが717→687命令（-4.18%）である。

## Cコードと生成アセンブリの対応

以下は同じGCC 15.2.0 `-O2` から得た命令列で、リンク後ELFの命令集計・動的PC対応にも使用した。

### 例1: ahaの64×64→128 bit乗算

```c
result = (unsigned __int128)u * v;
*wlo = result;
*whi = result >> 64;
```

RV32では `__SIZEOF_INT128__` がないため、実際にはCのフォールバックが選ばれる。32 bit部分積とcarryを多数の命令で組み立てる。

```asm
mul    a6,a1,a2
mulhu  t1,a0,a2
mul    a7,a0,a3
add    t1,a6,t1
sltu   a6,t1,a6
mulhu  t4,a1,a2
add    t1,a7,t1
sltu   a7,t1,a7
mulhu  t3,a0,a3
...                         # carryのadd/sltuが続く
mul    a0,a0,a2
sw     a0,0(a5)
sw     t1,4(a5)
sw     a7,0(a4)
sw     a6,4(a4)
```

RV64では低位・高位を各1命令で得る。

```asm
mul    a5,a0,a1
mulhu  a0,a0,a1
sd     a5,0(a3)
sd     a0,0(a2)
```

この差は動的multiplyが33,852→8,886、ALUが2,420,439→788,064へ減ったことに表れている。libgcc helperは両方とも使われない。

### 例2: ahaの128 bit shift/modulus loop

```c
t = (int64)x >> 63;
x = (x << 1) | (y >> 63);
y = y << 1;
if ((x | t) >= z) {
  x = x - z;
  y = y + 1;
}
```

RV32では各64 bit値が2レジスタになり、上下wordをまたぐshift、carry、2段比較が必要になる。

```asm
srli   a7,a0,31
slli   a6,a1,1
add    a6,a7,a6
srai   t1,a1,31
slli   a7,a3,1
srli   a1,a3,31
slli   a0,a0,1
srli   a3,a2,31
or     a0,a1,a0
add    a7,a3,a7
...                         # 上下word比較とborrow/carry
sub    t6,a0,s0
sltu   a4,t6,a0
sub    a6,a6,a5
```

RV64では同じ処理が単一wordで完結する。

```asm
srli   a6,a1,63
slli   a3,a0,1
srai   a5,a0,63
or     a0,a6,a3
or     a5,a5,a0
slli   a1,a1,1
bltu   a5,a2,skip
sub    a0,a0,a2
addi   a1,a1,1
```

動的shiftが1,548,180→730,945（-817,235）、branchが458,110→379,432（-78,678）となる根拠である。

### 例3: edn FIRの32 bit積と`long` accumulator/output

```c
sum += array1[i + j] * coeff[j];
output[i] = sum >> 15;
```

RV32 ILP32では `long` も32 bitである。

```asm
lh     a4,0(a5)
lh     a0,0(a3)
mul    a4,a4,a0
add    a2,a2,a4
srai   a2,a2,15
sw     a2,0(a7)
addi   a7,a7,4
```

RV64 LP64では積自体はCの32 bit `int`演算なので `mulw`、accumulator/outputは64 bitなので `add`、`srai`、`sd`となる。

```asm
lh     a4,0(a5)
lh     a0,0(a3)
mulw   a4,a4,a0
add    a2,a2,a4
srai   a2,a2,15
sd     a2,0(a7)
addi   a7,a7,8
```

命令数は変わらないが、本RTLでは `mulw` もRV64の7-cycle multiplierを通る。これがednの最重要箇所である。

### 例4: edn JPEG DCTのstack frame

```c
long int t[12];
```

```asm
# RV32
addi sp,sp,-128
sw   s0,124(sp)
...

# RV64
addi sp,sp,-240
sd   s0,232(sp)
...
```

`t[]` と保存レジスタの幅が倍になるため、`jpegdct` のframeは128→240 bytesとなる。`benchmark_body` は880→944 bytes、測定外の `verify_benchmark` は `long exp_output[200]` のため816→1,616 bytesとなった。

## 動的実行結果

`top.v` 78--83行は、performance counterがenableの間だけ、stallしていない有効なwrite-back命令のPCと命令wordを記録する。このため、headerを除くtrace行数を測定区間の退役命令数として使った。全PCはリンク後objdumpに対応し、未解決PCは0件であった。

| Benchmark | Arch | cycles | retired instructions | CPI | cycles/instructions以外のcycle |
|---|---|---:|---:|---:|---:|
| aha-mont64 | RV32 | 4,804,164 | 4,475,855 | 1.073351 | 328,309 |
| aha-mont64 | RV64 | 2,231,831 | 1,910,729 | 1.168052 | 321,102 |
| edn | RV32 | 4,891,697 | 3,466,757 | 1.411030 | 1,424,940 |
| edn | RV64 | 7,691,792 | 3,399,767 | 2.262447 | 4,292,025 |

性能差の分解は次のとおりである。

| Benchmark | instructions RV64/RV32 | CPI RV64/RV32 | cycles RV64/RV32 | 解釈 |
|---|---:|---:|---:|---|
| aha-mont64 | 0.426897 (-57.31%) | 1.088229 (+8.82%) | 0.464562 (-53.54%) | 命令削減がCPI悪化を上回る |
| edn | 0.980676 (-1.93%) | 1.603401 (+60.34%) | 1.572418 (+57.24%) | ほぼ全てCPI悪化 |

実際に `0.426897 × 1.088229 = 0.464562`、`0.980676 × 1.603401 = 1.572418` となる。

### aha-mont64の動的命令ミックス

| Category | RV32 count | RV64 count | Difference | RV32 share | RV64 share |
|---|---:|---:|---:|---:|---:|
| ALU | 2,420,439 | 788,064 | -1,632,375 | 54.078% | 41.244% |
| branch | 458,110 | 379,432 | -78,678 | 10.235% | 19.858% |
| jump/call | 5,504 | 5 | -5,499 | 0.123% | 0.000% |
| load | 7,212 | 2,545 | -4,667 | 0.161% | 0.133% |
| store | 2,558 | 852 | -1,706 | 0.057% | 0.045% |
| shift | 1,548,180 | 730,945 | -817,235 | 34.590% | 38.255% |
| multiply | 33,852 | 8,886 | -24,966 | 0.756% | 0.465% |
| divide | 0 | 0 | 0 | 0% | 0% |
| other | 0 | 0 | 0 | 0% | 0% |

RV64のW命令は27,495回ですべて `addiw`。RV32の `lw/sw` 7,212/2,557回は、RV64では `ld/sd` 2,545/850回へ変化した。`benchmark_body` 内のRV32 `montmul` callは3回/iteration × 423 iterations = 1,269回で、RV64では完全inlineされる。ただしcall削減5,499命令よりも、ALU・shiftの削減合計約245万命令の方が圧倒的に大きい。

### ednの動的命令ミックス

| Category | RV32 count | RV64 count | Difference | RV32 share | RV64 share |
|---|---:|---:|---:|---:|---:|
| ALU | 1,432,311 | 1,407,081 | -25,230 | 41.316% | 41.388% |
| branch | 355,135 | 348,175 | -6,960 | 10.244% | 10.241% |
| jump/call | 789 | 789 | 0 | 0.023% | 0.023% |
| load | 892,372 | 874,972 | -17,400 | 25.741% | 25.736% |
| store | 108,681 | 91,281 | -17,400 | 3.135% | 2.685% |
| shift | 104,052 | 104,052 | 0 | 3.001% | 3.061% |
| multiply | 573,417 | 573,417 | 0 | 16.540% | 16.866% |
| divide | 0 | 0 | 0 | 0% | 0% |
| other | 0 | 0 | 0 | 0% | 0% |

RV64のW命令は668,508回で、内訳は `mulw` 544,620、`addw` 59,769、`slliw` 25,578、`sraiw` 25,578、`subw` 5,568、`sraw` 5,568、`addiw` 1,827である。RV32の乗算573,417回はすべて `mul`、RV64は `mulw` 544,620回と `mul` 28,797回で、総数は全く同じである。

LP64化でdynamic load/store命令数は各17,400回減った。64 bit load/storeがコピーをまとめるためであり、命令数の面ではわずかに有利である。一方、アクセスbyte数はloadが1,904,134→2,003,714 bytes（+5.23%）、storeが368,775→532,051 bytes（+44.28%）となる。

## libgcc helperと64 bit演算

4個のELFすべてについて、`__muldi3`, `__divdi3`, `__udivdi3`, `__ashldi3`, `__lshrdi3`, `__ashrdi3` は存在しなかった。

`aha-mont64` のRV32コードはhelper callではなく、32 bit `mul/mulhu/add/sltu/shift` をinlineして64 bit処理を構成する。RV64は64 bit `mul/mulhu/shift/compare` を直接使う。このため効果は「libgcc callをなくした」ことではなく、「同じC演算に必要な基本命令数を減らした」ことにある。

`edn` には動的divideはなく、明示的64 bit算術を要求するコードも中心ではない。LP64で64 bitになった `long` accumulatorに対し、32 bit積をsign-extendするW命令が多用される。

## ABIによるサイズ変化

`nm -S` と関数prologueから次を確認した。

| edn object/frame | RV32 | RV64 | Change |
|---|---:|---:|---:|
| global `output[200]` | 800 B | 1,600 B | +800 B |
| global `d` | 4 B | 8 B | +4 B |
| ELF `.bss` | 1,610 B | 2,414 B | +804 B |
| `jpegdct` frame | 128 B | 240 B | +112 B |
| `benchmark_body` frame | 880 B | 944 B | +64 B |
| `verify_benchmark` frame | 816 B | 1,616 B | +800 B |

したがって「LP64でlong・pointer・stackが大きくなる」は実際に成立する。ただしこのCPUのDMEMはXLEN幅で、`ld/sd` も1回のmemory operationとして処理される。測定区間のload/store命令数は増えず、むしろ合計34,800命令減っている。よってサイズ増加はメモリ容量・転送byte数上のオーバーヘッドではあるが、今回のcycle悪化の主因ではない。

## RTL実装との対応

### Pipeline、forwarding、load/store

- forwardingはXLEN parameterの同一経路で、RV32/RV64分岐はない（`proc.v` 242--254行）。
- load/multiply/divide直後の依存には共通の1 bubble検出がある（167--183行）。
- load/store address generationとload formattingは組合せ回路で、RV64の`LD/SD`専用追加stateはない（326--340行、419--428行、881--959行）。
- DMEMはRV32なら32 bit、RV64なら64 bit幅の同期RAMで、いずれも単一のread processである（`main.v` 140--168行）。
- ALU、compare、branch、W shift/sign-extensionも組合せ回路であり、RV64だけmulti-cycleになる実装ではない（`proc.v` 544--626行）。

### Multiplier

RV32 multiplierは `IDLE → EXEC → RET → IDLE` で、`stall_o` が有効なのは2 cycleである（`proc.v` 844--876行）。

RV64 multiplierは `IDLE → PARTIAL → PAIR → ROW → SUM → PRODUCT → FORMAT → RET → IDLE` で、`stall_o` が有効なのは7 cycleである（735--843行）。16個の16×16部分積を段階的に加算して128 bit積を作る。

さらに `is_w` は最後のFORMAT段で下位32 bitをsign-extendするだけであり、`mulw`にも短縮経路がない（831--837行）。したがってednの32 bit乗算もRV64では毎回7-cycle stallになる。

ednでは、

```text
RV32 non-retirement cycles = 4,891,697 - 3,466,757 = 1,424,940
RV64 non-retirement cycles = 7,691,792 - 3,399,767 = 4,292,025
difference                  = 2,867,085
573,417 multiplies × (7 - 2) cycles = 2,867,085
```

と1 cycleも違わず一致する。全runのbranch misprediction counterもRV32/RV64とも11,366であり、branch予測差では説明できない。

### Divider

dividerは`cntr`を `XLEN - 1` で初期化するため、RV64は基本的にRV32より32 iteration長い。W divideにも短縮経路がない（`proc.v` 646--718行）。ただし今回の2ベンチマークは動的divide 0回なので、結果へ寄与しない。

## 最大改善: aha-mont64

### RV64で最も性能が向上したベンチマーク

```text
Benchmark:       aha-mont64
RV32 score/MHz:  0.833444
RV64 score/MHz:  1.794043
Improvement:     +115.257% (2.152566×)
```

### 主因

1. 明示的な64 bit shift/compare/addを、RV32のregister pair操作からRV64の単一命令へ変換でき、動的命令数が4,475,855→1,910,729（-57.31%）になった。
2. RV64だけが`__int128`を利用でき、64×64→128 bit積を`mul`+`mulhu`で生成する。dynamic multiplyは33,852→8,886、ALUは約163万、shiftは約82万命令減った。
3. 小さくなったnative 64 bitコードをGCCがより積極的にinlineし、jump/callも5,504→5になった。

### 実行命令数

```text
RV32:       4,475,855
RV64:       1,910,729
Difference: -2,565,126 (-57.31%)
```

### CPI

```text
RV32:       1.073351
RV64:       1.168052
Difference: +0.094701 (+8.82%)
```

RV64 multiplier自体は遅いのでCPIは改善していない。それでも乗算回数を24,966回減らし、全命令数を半分以下にした効果が圧倒的に大きい。

### 64 bit ISAによる直接的な効果

あり。これが主効果である。特に64 bit shift/compareと64×64→128 bit積が直接短縮される。

### ABIやコンパイラによる効果

ABIのpointer拡大による負担は小さい。コンパイラの `__int128` path選択とinliningには追加効果があるが、その根本はRV64 ISAで64 bit演算を直接表現できることである。

### RTLによる効果

RV64 multiplierはRV32より5 stall cycle長く、むしろ不利である。RTLが高速化したのではなく、その不利を動的命令削減が上回った。

### 最終的な説明

ahaだけが特に速い理由は、benchmarkの中心データ型が最初から明示的64 bitで、shift・carry・比較・128 bit積のほぼ全てがRV32では複数命令を必要とする一方、RV64ではnative命令になるためである。cycle比は命令数比0.426897とCPI比1.088229の積0.464562で、性能向上が命令数由来であることを定量的に確認できる。

## 最大悪化: edn

### RV64で最も性能が低下したベンチマーク

```text
Benchmark:       edn
RV32 score/MHz:  0.819756
RV64 score/MHz:  0.521335
Change:          -36.404% (0.635964×)
```

### 主因

1. DSP loopが動的に573,417回の乗算を行い、その95.0%に当たる544,620回がRV64では`mulw`になる。
2. RV64 RTLは`mulw`にも7-cycle multiplierを使い、RV32の2 cycleより1回あたり5 cycle長い。この差だけで2,867,085 cycle増える。
3. LP64でlong、pointer、stack、global outputは大きくなるが、load/store命令数はむしろ減るため、cycle悪化の一次原因ではない。

### 実行命令数

```text
RV32:       3,466,757
RV64:       3,399,767
Difference: -66,990 (-1.93%)
```

### CPI

```text
RV32:       1.411030
RV64:       2.262447
Difference: +0.851417 (+60.34%)
```

### RV64化によるオーバーヘッド

- 544,620回の`mulw`に専用の短い32 bit経路がない。
- `output[200]` とDCTの`long t[12]`、保存register、pointerが拡大する。
- 668,508回のW命令が現れるが、ALUのW命令は組合せ回路なので追加cycleを持たない。問題はW命令一般ではなく`mulw`である。

### ABIやコンパイラによる影響

LP64がCの `short × short` の意味を64 bit積へ変えたわけではない。積は32 bit `int`で、GCCは正しく`mulw`を選ぶ。pointer incrementは4→8、storeは`sw`→`sd`となる。メモリfootprintは増えるが、64 bit busによるwide copyで退役命令数はわずかに減っている。

### RTLによる影響

決定的である。もしRV64の全乗算にRV32と同じ2-cycle経路があれば、実測RV64 cycleから2,867,085を引いた4,824,707 cycle相当となり、RV32の4,891,697 cycleより約1.37%速い計算になる。つまり今回の`edn`低下は「RV64 ISAだから」ではなく、このRV64 multiplier microarchitectureに依存する。

### 最終的な説明

ednはnative 64 bit算術で命令列を大きく短縮できる処理ではなく、非常に高密度な32 bit乗算DSPである。RV64化後も乗算回数は1回も減らず、それらが全て5 cycle余分にstallする。一方、ABI拡大による命令数ペナルティはなく、総命令数はむしろ1.93%減る。したがって57.24%のcycle増はRTL multiplier latencyで説明できる。

## 最大改善と最大悪化の比較

| 指標 | 最大改善 | 最大悪化 |
|---|---|---|
| benchmark | aha-mont64 | edn |
| score/MHz変化 | +115.257% | -36.404% |
| 命令数変化 | -57.31% | -1.93% |
| CPI変化 | +8.82% | +60.34% |
| 64 bit演算量 | 明示的uint64/int64が中心 | 元はshort/int積、longがLP64で拡大 |
| load/store命令 | 9,770→3,397 | 1,001,053→966,253 |
| load/store byte量 | 39,077→27,165 B | 2,272,909→2,535,765 B |
| branch量 | 458,110→379,432 | 355,135→348,175 |
| pointer使用 | 少ない | 多い |
| multiply回数 | 33,852→8,886 | 573,417→573,417 |
| 主因 | native 64 bit ISAによる命令削減 | RV64/MULWの5-cycle追加stall |

この実装でRV64化の恩恵を得やすいのは、明示的な64 bit整数、64 bit shift/compare/carry、wide multiplyを多用し、RV32ではregister pair操作になるプログラムである。逆に、32 bit整数乗算が高密度で、RV64でも乗算回数が減らないDSP・行列・filter系は、現状の遅いRV64 multiplier、とりわけ短縮されない`MULW`のため性能低下しやすい。LP64のlong/pointer肥大は容量とmemory byte数には影響するが、このon-chip XLEN幅DMEMでは必ずしも命令数やcycle増に直結しない。

## 再現用ファイル

- 命令mix解析: `scripts/analyze_embench_trace.py`
- 元スコア: `build/embench/rv32/results.csv`, `build/embench/rv64/results.csv`
- 再実行ログ・ELF・disassembly・trace・JSON: `build/embench-analysis/{aha-mont64,edn}/{rv32,rv64}/`

解析スクリプトは `objdump -d -M no-aliases` のPCと、測定区間traceのPCを対応させ、静的命令数、動的退役命令数、関数別回数、命令カテゴリ、W命令overlay、CPIをJSONへ出力する。
