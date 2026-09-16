# CFU-PG向けμT-Kernel段階的テスト計画

## 目的

CFU-PG上でμT-Kernelを一度に起動しようとせず、CPU、メモリ、CSR、
トラップ、タイマ、カーネルの順に小さく確認する。

各テストは、直前のテストがPASSしてから着手する。失敗時はμT-Kernel全体を
デバッグせず、そのテストで新しく追加した機能だけを調査する。

## 共通方針

- 最初はVerilatorシミュレーションだけを対象とする。
- CPUはRV32としてビルドする。
- ABIは`ilp32`を使用する。
- 圧縮命令は生成しないため、`-march`に`c`を付けない。
- CSRを使わないテストは`-march=rv32im`とする。
- CSRを使うテストから`-march=rv32im_zicsr`とする。
- 各テストでは、DMEMへのシグネチャ書き込みで結果を判定する。
- ELFを実行する前に、`objdump`とMapファイルで命令と配置を確認する。
- 通常のCFU-PGアプリとテスト用コードを混ぜず、専用Makeターゲットを使う。

現在のシグネチャ領域は次のとおりとする。

| アドレス | 用途 |
|---|---|
| `0x10000000` | テスト結果またはPASS値 |
| `0x10000004` | 実測値、エラー原因などの補助情報 |
| `0x10000008`以降 | 複数の途中結果が必要な場合に使用 |

## 通常のμT-Kernelアプリケーション

Test 12で確認したコンソール出力は、テスト専用ではなくCFU-PG向け
μT-Kernelの共通機能として組み込む。通常のアプリケーションは次の1コマンドで
コンパイル、Verilatorビルド、実行まで行う。

```bash
make mtkernel-run
```

この実行経路はμT-Kernel本体、`libtm.c`、`libtm_printf.c`、RISC-V用
`tm_com.c`、アプリケーションの`usermain()`を同じ共通コンパイル設定で
まとめてビルドする。
既定のアプリケーションはmtkernel_cfu側の標準`usermain.c`である。
別のアプリケーションを使用する場合は次のように指定する。

```bash
make mtkernel-run MTKERNEL_APP_SRCS=app/my_usermain.c
```

ELFとメモリ初期値だけを生成する場合は`make mtkernel`、Verilator実行ファイル
まで生成して実行しない場合は`make mtkernel-build`を使用する。

アプリケーションでは追加のTest 12用ヘッダや通信ソースを指定せず、通常どおり
`<tm/tmonitor.h>`をインクルードして`tm_printf()`を呼び出せる。

```c
#include <tk/tkernel.h>
#include <tm/tmonitor.h>

EXPORT INT usermain(void)
{
    tm_printf((UB *)"Hello, micro T-Kernel\n");
    return 0;
}
```

`make mtkernel-run`では`CFU_MTKERNEL_SIM`構成を使用する。`usermain()`がreturn
するとμT-Kernelのシャットダウン経路からテストベンチへ終了値を書き込み、
シミュレータも終了コード0で自動終了する。

関連ファイルの役割は次のとおり。

| ファイル | 役割 |
|---|---|
| `Makefile` | 共通カーネル、コンソール、アプリケーションをリンク |
| `app/mtkernel.ld` | CFU-PG向けIMEM/DMEM配置 |
| `mtkernel_cfu/config/config.h` | `CFU_MTKERNEL`構成でT-Monitor APIを有効化 |
| `mtkernel_cfu/lib/libtm/libtm.c` | `tm_putchar()`などの共通API |
| `mtkernel_cfu/lib/libtm/libtm_printf.c` | `tm_printf()`の書式処理 |
| `mtkernel_cfu/lib/libtm/sysdepend/iote_riscv/tm_com.c` | CFU-PGの文字出力MMIO |
| `top.v` | `0x80000000`への書込みをシミュレータ端末へ表示 |

現在の`tm_com.c`はVerilator向けの出力トランスポートである。FPGAへ移行するときは
同じ`tm_snd_dat()`の下位実装を実機UARTへ切り替える。`tm_printf()`を使用する
アプリケーションや共通ビルド構成は変更しない。

### 回帰テストとの分離

通常のアプリケーション実行は`make mtkernel-run`だけを使用する。`smoke`、
Test 9、Test 11、Test 12はアプリケーションの別ビルド方式ではなく、移植層を
段階別に診断する回帰テストとして残す。

| テスト | 残す目的 |
|---|---|
| `mtkernel-smoke-run` | カーネルを介さず、起動・CSR・例外・タイマを検査 |
| `mtkernel-test9-run` | μT-Kernel全体の初期化と初期タスク到達を検査 |
| `mtkernel-test11-run` | タイマ待ちと複数タスク切替を検査 |
| `mtkernel-test12-run` | 共通コンソールを含む実行経路を検査 |

すべての回帰テストは次の1コマンドで順番に実行できる。

```bash
make mtkernel-check
```

Test 9、Test 11、Test 12は通常アプリと同じ`MTKERNEL_CFLAGS`、
`MTKERNEL_CPPFLAGS`、`MTKERNEL_LDFLAGS`および共通リンク処理を使用する。
`smoke`だけはμT-Kernel本体をリンクしないCPU移植層単体テストなので、専用の
最小コンパイルを使用する。

## スモークテストのビルドと実行

CFU-PGディレクトリで次を実行する。

```bash
make mtkernel-smoke-run
```

このターゲットは、次の処理を順番に行う。

```text
startup.Sとreset_hdl_test.cをコンパイル・リンク
    ↓
main.elfからmemi.txtとmemd.txtを生成
    ↓
Verilatorシミュレータをビルド
    ↓
obj_dir_mtkernel_smoke/topを実行
    ↓
DMEMへの書き込みを検査
```

## テスト1: `_start`からC関数を呼ぶ（完了）

### 確認対象

- リセットベクタ`0x00000000`
- `.text.startup`の配置
- `la sp, _stack_top`
- `la gp, __global_pointer$`
- `call Reset_Handler`
- Cコードの実行
- `sw`によるDMEM書き込み

### 合格条件

次が表示されること。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

### 確認済み配置

```text
_start         = 0x00000000
Reset_Handler  = 0x0000001c
_stack_top     = 0x10004000
```

## テスト2: スタックを使ったC関数呼び出し（完了）

### 目的

テスト1では`sp`へ値を設定したが、最適化後の`Reset_Handler`はスタックを
ほぼ使用していない。実際にDMEM上のスタックへ保存・復元できることを確認する。

### 実装内容

- `noinline`関数を1つ作る。
- 関数内に`volatile`なローカル配列を置く。
- ローカル配列へ値を書き、読み戻した計算結果を返す。
- 結果を`0x10000000`へ書く。

例:

```c
__attribute__((noinline))
static uint32_t stack_test(uint32_t a, uint32_t b)
{
    volatile uint32_t local[4];
    local[0] = a;
    local[1] = b;
    local[2] = local[0] + local[1];
    return local[2];
}
```

単純なローカル変数だけではレジスタへ最適化される可能性があるため、
`objdump`で次のような命令があることを確認する。

```asm
addi sp, sp, -N
sw   ..., offset(sp)
lw   ..., offset(sp)
addi sp, sp, N
```

### 合格条件

- `sp`が`0x10000000`以上`0x10004000`以下の範囲にある。
- スタックへの`sw`と`lw`が発生する。
- 期待する計算結果が`0x10000000`へ書かれる。
- テストベンチがPASSを表示して終了する。

### 確認結果

`stack_test()`でスタックを16バイト確保し、ローカル配列へ書き込んだ値を
読み戻していることを確認した。

```asm
addi sp, sp, -16
sw   a5, 0(sp)
sw   a5, 4(sp)
lw   a5, 0(sp)
lw   a4, 4(sp)
sw   a5, 8(sp)
lw   a5, 8(sp)
sw   a5, 12(sp)
lw   a0, 12(sp)
addi sp, sp, 16
ret
```

`Reset_Handler()`自身も戻りアドレスをスタックへ保存している。

```asm
addi sp, sp, -16
sw   ra, 12(sp)
call stack_test
```

シミュレーションでは、スタック最上部付近に次の書き込みが発生した。

```text
WE: addr=10003ffc data=00000018
WE: addr=10003fe0 data=12340000
WE: addr=10003fe4 data=00005678
WE: addr=10003fe8 data=12345678
WE: addr=10003fec data=12345678
```

最後に計算結果がシグネチャ領域へ書かれ、PASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

## テスト3: `.data`、`.bss`、`gp`の確認（完了）

### 目的

初期値付きグローバル変数、ゼロ初期化変数、グローバルポインタ相対アクセスを
確認する。

### 実装内容

次の変数を用意する。

```c
volatile const uint32_t rodata_value = 0xa5a55a5a;
volatile uint32_t initialized_data = 0x13579bdf;
volatile uint32_t zero_initialized_data;
```

各値を実行時に読み出して検査し、結果を`test_status`へ書く。

```text
0x10000000 <- 最終結果
```

### 重要事項

CFU-PGはIMEMとDMEMが分離されたHarvard構成である。通常の組込み環境で使う
「IMEM上の`.data`初期値を起動時にDMEMへコピーする」方式は、そのままでは
使用できない。

この段階では次の方式を採用する。

- `.data`は`memd.txt`によってDMEMへ直接初期配置する。
- `.bss`は`Reset_Handler`でゼロクリアする。
- `.data`をIMEMからコピーしない。

### 確認項目

- Mapファイル上で`.data`と`.bss`がDMEM内にある。
- `memd.txt`に`0xa5a55a5a`と`0x13579bdf`が含まれる。
- `rodata_value`の読み出し結果が`0xa5a55a5a`になる。
- `initialized_data`の読み出し結果が`0x13579bdf`になる。
- `.bss`を意図的にゼロクリアし、読み出し結果が`0`になる。
- `__global_pointer$`がDMEM内に配置され、`startup.S`がその値を設定する。
- `gp`相対ロード自体は、必要になった段階で別途確認する。

### 合格条件

```text
0x10000000の最終値 = 0x12345678
テストベンチ出力     = MTKERNEL_SMOKE: PASS
```

### 採用した方式

IMEMをDBUSから読まない方式（方法4）を採用した。

```text
.text        → memi.txtでIMEMへ初期配置
.test_status → memd.txtでDMEMへ初期配置
.rodata      → memd.txtでDMEMへ初期配置
.data        → memd.txtでDMEMへ初期配置
.bss         → Reset_Handlerでゼロクリア
```

`.data`のIMEMからDMEMへのコピーは行わない。

### 確認結果

ELFとMapファイルで次の配置を確認した。

```text
.text        0x00000000  size 0x00f4  IMEM
.test_status 0x10000000  size 0x0004  DMEM
.rodata      0x10000004  size 0x0004  DMEM
.data        0x10000008  size 0x0004  DMEM
.bss         0x1000000c  size 0x0004  DMEM
```

`memd.txt`の先頭は次の内容になった。

```verilog
dmem[0] = 32'hc001d00d;  // test_statusの初期値
dmem[1] = 32'ha5a55a5a;  // .rodata
dmem[2] = 32'h13579bdf;  // .data
dmem[3] = 32'h00000000;  // .bss領域
```

`.bss`のゼロクリアが実際に動作していることを確認するため、
`zero_initialized_data`へ一度`0xffffffff`を書き、その後
`__bss_start`から`__bss_end`までをゼロクリアした。

```text
WE: addr=1000000c data=ffffffff
WE: addr=1000000c data=00000000
```

実行時には次をそれぞれ`lw`で読み出して検査した。

```text
rodata_value          = 0xa5a55a5a
initialized_data      = 0x13579bdf
zero_initialized_data = 0x00000000
```

さらにテスト2のスタックテストも実行し、最終結果がPASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

不一致時のシグネチャは次のとおり。

```text
0xdead0001 = .rodata不一致
0xdead0002 = .data不一致
0xdead0003 = .bss不一致
```

## テスト4: 最小CSR読み書き（完了）

### 目的

μT-Kernelの`startup.S`が使用するCSR命令をCPUへ追加する。

最初に対象とするCSRは次の2つとする。

| CSR | アドレス | 用途 |
|---|---:|---|
| `mstatus` | `0x300` | Machine-mode状態と割込み許可 |
| `mie` | `0x304` | 個別割込み許可 |

最初に対象とする命令は次の2種類とする。

- `CSRRW`
- `CSRRS`

疑似命令との対応は次のとおり。

```asm
csrw mstatus, t0     # csrrw x0, mstatus, t0
csrr t1, mstatus     # csrrs t1, mstatus, x0
```

### テスト方法

最初からゼロを書くだけでは、CSR命令がNOPとして処理されてもテストが通る
可能性がある。必ず非ゼロ値を書き、読み戻してからゼロクリアする。

```asm
li   t0, 8
csrw mstatus, t0
csrr t1, mstatus
bne  t0, t1, fail

csrw mstatus, zero
csrr t1, mstatus
bne  t1, zero, fail
```

`mie`についても同様に、例えばMTIEビット`0x80`を書いて読み戻す。

### 合格条件

- `mstatus`へ`8`を書いて`8`を読み戻せる。
- `mstatus`をゼロクリアして`0`を読み戻せる。
- `mie`へ`0x80`を書いて`0x80`を読み戻せる。
- 不一致時にはFAIL値と実測値をDMEMへ書ける。

### 実装内容

CSRは`main.v`ではなく、`proc.v`の`cpu`モジュール内に`csr_file`として
実装した。今回保持するCSRは`mstatus`と`mie`の2つで、リセット値はいずれも
ゼロとした。

CPUには次の処理を追加した。

- `pre_decoder`でSYSTEM opcode（`1110011`）のCSRRW/CSRRSを認識する。
- `decoder`からCSR命令種別をID/EXパイプラインレジスタへ渡す。
- EX段でCSRの旧値と新しい書き込み値を計算する。
- CSRの旧値を通常の整数レジスタ書き戻し経路へ渡す。
- CSRの更新は命令がMA段へ到達してから行う。
- 連続する`csrw`→`csrr`のため、MA段の未反映値をEX段へ転送する。

テストプログラムの`-march`は`rv32im_zicsr`へ変更した。
テストスタブでは`mstatus`と`mie`について非ゼロ値の読み戻しと、
ゼロクリア後の読み戻しを行う。不一致時には次の値を`test_status`へ、
読み戻した実測値を`csr_actual`へ書く。

```text
0xdead0004 = mstatusへ0x00000008を書いた後の不一致
0xdead0005 = mstatusをゼロクリアした後の不一致
0xdead0006 = mieへ0x00000080を書いた後の不一致
0xdead0007 = mieをゼロクリアした後の不一致
```

### 確認結果

逆アセンブルで次のCSR命令が生成された。

```asm
csrw mstatus, a4
csrr a5, mstatus
csrw mstatus, a5
csrr a5, mstatus
csrw mie, a2
csrr a4, mie
csrw mie, a5
csrr a5, mie
```

シミュレーションの命令トレースでも、CSR命令の実行を確認した。

```text
TRACE: pc=0000007c insn=30071073
TRACE: pc=00000080 insn=300027f3
TRACE: pc=000000d8 insn=30461073
TRACE: pc=000000dc insn=30402773
```

CSR検査後もテスト1〜3のBSSゼロクリア、スタック操作、DMEM書き込みまで
実行され、最終結果はPASSした。

```text
WE: addr=10000010 data=ffffffff
WE: addr=10000010 data=00000000
WE: addr=10003ffc data=00000018
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

## テスト5: 実物の`startup.S`をそのまま実行（完了）

### 目的

コメントアウトしている次の命令を元に戻す。

```asm
csrw mstatus, zero
csrw mie, zero
```

テスト1からテスト4までの処理と組み合わせ、実物の`startup.S`を変更せずに
`Reset_Handler`へ到達できることを確認する。

### 合格条件

- `startup.S`のCSR命令をコメントアウトしていない。
- `mstatus == 0`かつ`mie == 0`になっている。
- `sp`と`gp`が正しい。
- `Reset_Handler`がPASSシグネチャを書く。

### 起動コードより前に非ゼロ値を用意する方法

`startup.S`より前にソフトウェア命令を実行することはできないため、
シミュレーション用のハードウェアリセット値を使用する。

`MTKERNEL_SMOKE`を定義したときだけ、`csr_file`のリセット値を次の値にする。

```text
mstatus = 0x00000008
mie     = 0x00000080
```

通常のビルドでは、両CSRのリセット値は従来どおりゼロとする。
このためFPGA用の通常構成にはテスト用の非ゼロ値が残らない。

`Reset_Handler`ではテスト4がCSRを書き換える前に両CSRを読み出す。
`startup.S`のゼロ書き込みが機能しなかった場合は次の値を出力する。

```text
0xdead0008 = startup.S実行後もmstatusが非ゼロ
0xdead0009 = startup.S実行後もmieが非ゼロ
```

### 確認結果

リセットベクタの先頭に、コメントを外した2命令が配置された。

```asm
00000000 <_start>:
   0: 30001073  csrw mstatus,zero
   4: 30401073  csrw mie,zero
   8: 10004117  auipc sp,0x10004
   c: ff810113  addi sp,sp,-8  # 10004000 <_stack_top>
```

シミュレーションでは、テスト用の非ゼロリセット値に対して、
`startup.S`がゼロを書き込んだことを確認した。

```text
CSR_WE: addr=300 data=00000000
CSR_WE: addr=304 data=00000000
TRACE: pc=00000000 insn=30001073
TRACE: pc=00000004 insn=30401073
```

その後、`Reset_Handler`内で両CSRを読み出し、ゼロ判定を通過した。

```asm
80: 300027f3  csrr a5,mstatus
84: 02078663  beqz a5,b0
b0: 304027f3  csrr a5,mie
b4: 00078c63  beqz a5,cc
```

`sp`と`gp`の設定、テスト4の非ゼロCSR読み書き、テスト1〜3の処理も
引き続き実行され、最終結果はPASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

## テスト6: `mtvec`と`mret`（完了）

### 目的

トラップ処理に必要なCSRと`mret`命令を、割込みなしで個別に確認する。

追加するCSRは次のとおり。

| CSR | アドレス | 用途 |
|---|---:|---|
| `mtvec` | `0x305` | トラップハンドラのアドレス |
| `mepc` | `0x341` | トラップから戻るPC |
| `mcause` | `0x342` | トラップ原因 |

### `mtvec`テスト

- 4バイト境界に整列したハンドラアドレスを`mtvec`へ書く。
- CSRから読み戻して一致を確認する。
- 最初はDirect modeだけを対象とする。

### `mret`テスト

- `mepc`へテスト用ラベルのアドレスを書く。
- 必要な`mstatus.MPP`と`mstatus.MPIE`を設定する。
- `mret`を実行する。
- 指定したラベルへ到達したらPASSシグネチャを書く。

### 合格条件

- `mtvec`を書いて読み戻せる。
- `mepc`を書いて読み戻せる。
- `mret`後のPCが`mepc`と一致する。
- `mret`時の`mstatus`更新が実装方針どおりである。

### 実装内容

CSR制御を個別の判定ビットではなく、SYSTEM命令の`funct3`をそのまま
パイプラインへ渡す方式に変更した。これにより、レジスタ形式と即値形式を含む
次のCSR命令を扱える。

- `CSRRW` / `CSRRWI`
- `CSRRS` / `CSRRSI`
- `CSRRC` / `CSRRCI`

`csr_file`へ`mtvec`、`mepc`、`mcause`を追加した。CFU-PGでは圧縮命令を
使用しないため、`mtvec`と`mepc`への書き込み時には下位2ビットをゼロにする。

`mret`はMA段で確定するPCリダイレクトとして実装した。確定時にはPCを
`mepc`へ変更し、IF、ID、EX段にある後続命令を破棄する。同時に`mstatus`を
次のように更新する。

```text
MIE  <- MPIE
MPIE <- 1
MPP  <- 3（このCPUがMachine modeのみを実装するため）
```

連続する`csrw mepc`→`mret`を正しく実行するため、MA段にある未反映の
`mepc`書き込み値を`mret`のリダイレクト先へ転送する。

テスト用の`mret_test.S`では、戻り先ラベルを`mepc`へ設定し、
`mstatus=0x00001880`としてから`mret`を実行する。戻り先では`mstatus`を
読み出してCコードへ返す。`mret`直後のフォールスルー側は`1`を返すため、
PCリダイレクトまたはパイプライン破棄が動かなければテストが失敗する。

不一致時のシグネチャは次のとおり。

```text
0xdead000a = mtvec読み戻し不一致
0xdead000b = mepc読み戻し不一致
0xdead000c = mcause読み戻し不一致
0xdead000d = CSRRCによるmstatus更新不一致
0xdead000e = mretの戻り先またはmstatus更新不一致
```

### 確認結果

逆アセンブルでCSRアクセスと`mret`を確認した。

```asm
csrw mtvec,a5
csrr a4,mtvec
csrw mepc,a4
csrr a5,mepc
csrw mcause,a4
csrr a5,mcause
csrc mstatus,a5
csrw mepc,t0
csrw mstatus,t0
mret
```

`mret_test`は`0x00000284`、戻り先は`0x000002a8`に配置された。
シミュレーションでは次のCSR書き込みを確認した。

```text
CSR_WE: addr=305 data=00000284
CSR_WE: addr=341 data=00000100
CSR_WE: addr=342 data=0000000b
CSR_WE: addr=300 data=00000080
CSR_WE: addr=341 data=000002a8
CSR_WE: addr=300 data=00001880
```

`mret`後の`mstatus`は`0x00001888`となり、過去のテスト1からテスト5も
含めて最終結果がPASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

## テスト7: 同期例外によるトラップ往復（完了）

### 目的

実際のトラップ入口からハンドラへ移動し、`mret`で元の処理へ戻る一連の
経路を確認する。

### 推奨する最初の例外

Machine modeの`ecall`を使用する。

```asm
la   t0, trap_handler
csrw mtvec, t0
ecall
```

トラップ発生時にCPUが行うべき処理は次のとおり。

- `mepc`へ`ecall`のPCを保存する。
- `mcause`へMachine-mode ecallの原因番号`11`を設定する。
- `mstatus.MIE`を`mstatus.MPIE`へ保存する。
- `mstatus.MIE`をクリアする。
- PCを`mtvec`へ変更する。
- パイプライン上の後続命令を破棄する。

ハンドラでは`mepc`へ4を加えてから`mret`する。4を加えないと同じ`ecall`を
再実行してしまう。

### 合格条件

- ハンドラで`mcause == 11`を確認できる。
- `mepc`が`ecall`のアドレスと一致する。
- `mret`後に`ecall`の次の命令へ戻る。
- トラップ前後で汎用レジスタが意図せず壊れない。

### 実装内容

Machine modeの`ecall`（命令語`0x00000073`）をデコードし、命令情報を
ID/EX、EX/MAパイプラインレジスタでMA段まで渡す。MA段へ到達した有効な
`ecall`を同期例外として確定し、次を行う。

```text
mepc        <- ecallのPC
mcause      <- 11
mstatus.MPIE <- mstatus.MIE
mstatus.MIE  <- 0
mstatus.MPP  <- 3（Machine mode）
PC          <- mtvec.BASE
```

トラップによるPC変更を既存のリダイレクト経路へ追加し、IF、ID、EX段にある
`ecall`より後の命令を破棄する。例外を発生させた`ecall`自身は通常命令として
リタイアさせない。

`csr_file`にはトラップ専用の更新入力を追加した。更新の優先順位は、リセット、
トラップ入口、`mret`、通常のCSR命令の順とする。`mtvec`はDirect modeのみを
対象とし、保存済みの4バイト境界アドレスをリダイレクト先として使用する。

テスト用の`ecall_test.S`では次を行う。

1. `mtvec`へ`ecall_trap_handler`を設定する。
2. `mstatus.MIE`を1にする。
3. 保存確認用レジスタと、後続ストア用の値を用意する。
4. `ecall`を実行する。
5. ハンドラで`mcause`、`mepc`、`mstatus`をDMEMへ記録する。
6. `mepc`へ4を加えて`mret`する。
7. `ecall`直後の命令から再開し、通常の`ret`でCコードへ戻る。

`ecall`の直後にはDMEMへのストアを配置した。ハンドラ入口でその書き込み先が
まだゼロであることを確認し、トラップ時にEX段の後続命令が破棄されたことを
検査する。`mret`後には同じストアが実行され、値が1になることも確認する。

不一致時のシグネチャは次のとおり。

```text
0xdead000f = トラップハンドラ未到達
0xdead0010 = mcause不一致
0xdead0011 = mepc不一致
0xdead0012 = トラップ入口のmstatus不一致
0xdead0013 = ecall後続命令の破棄失敗
0xdead0014 = mret後にecallの次の命令へ未到達
0xdead0015 = mret後のmstatusまたは汎用レジスタ保持不一致
```

### 確認結果

ELFでは次の配置となった。

```text
ecall_test         = 0x000006bc
ecall_test_site    = 0x00000700
ecall_trap_handler = 0x00000748
```

逆アセンブルで、`ecall`直後に検査用ストアがあり、ハンドラが`mepc`へ4を
加えて`mret`していることを確認した。

```asm
00000700 <ecall_test_site>:
700: 00000073  ecall
704: 01de2023  sw t4,0(t3)

00000748 <ecall_trap_handler>:
754: 342022f3  csrr t0,mcause
764: 341022f3  csrr t0,mepc
774: 300022f3  csrr t0,mstatus
7ac: 341022f3  csrr t0,mepc
7b0: 00428293  addi t0,t0,4
7b4: 34129073  csrw mepc,t0
7c4: 30200073  mret
```

シミュレーションでは次を確認した。

```text
CSR_WE: addr=305 data=00000748
CSR_WE: addr=300 data=00000008
TRAP: pc=00000700 cause=0000000b
WE: addr=10000040 data=0000000b  // mcause
WE: addr=1000003c data=00000700  // mepc
WE: addr=10000038 data=00001880  // trap-entry mstatus
WE: addr=10000034 data=00000000  // younger store was squashed
CSR_WE: addr=341 data=00000704
WE: addr=10000030 data=00000001  // store after MRET
```

過去のテスト1からテスト6も含めて最終結果がPASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

## テスト8: タイマMMIOとMachine Timer Interrupt（完了）

### 目的

μT-Kernelの時間管理と遅延処理に必要なタイマ割込みを、カーネルなしで確認する。

### 実装内容

- 64ビットの`mtime`を実装する。
- 64ビットの`mtimecmp`を実装する。
- `mtime >= mtimecmp`でMachine Timer Interrupt要求を発生させる。
- CPUへ割込み入力を追加する。
- `mie.MTIE`と`mstatus.MIE`が有効なときだけトラップを受ける。
- 割込み時の`mcause`を`0x80000007`とする。

MMIOアドレスは、μT-Kernel側の`sys_timer.h`とCFU-PG側のRTLで必ず一致させる。

### 最小テスト手順

1. `mtvec`へタイマハンドラを設定する。
2. `mtimecmp`へ近い将来の値を書く。
3. `mie.MTIE`を有効にする。
4. `mstatus.MIE`を有効にする。
5. ループまたは`wfi`で待つ。
6. ハンドラで`mcause`を確認する。
7. 次回の`mtimecmp`を設定して割込み要因を解除する。
8. PASSシグネチャを書いて`mret`する。

### 合格条件

- 指定した時刻より前に割込みが発生しない。
- `mtime >= mtimecmp`で割込みが発生する。
- `mcause == 0x80000007`になる。
- `mepc`が割り込まれた命令のアドレスを示す。
- `mret`で元の処理へ戻れる。
- `mtimecmp`更新後に割込みが解除される。

`wfi`は最初はNOP相当として実装してもよい。ただし、最終的には割込みまで
実行を待機する動作を別途確認する。

### 実装内容

`main.v`へ64ビットの`mtime`と`mtimecmp`を持つ`machine_timer`を追加した。
リセット時は`mtime=0`、`mtimecmp=0xffffffffffffffff`とし、起動直後の
意図しない割込みを防ぐ。`mtime`は通常サイクルごとに1増加し、次の4つの
32ビットMMIOアドレスからアクセスできる。

```text
0x6000bff8 = mtime[31:0]
0x6000bffc = mtime[63:32]
0x60004000 = mtimecmp[31:0]
0x60004004 = mtimecmp[63:32]
```

アドレスはμT-Kernel側の`sys_timer.h`と一致している。タイマ領域を既存の
VMEMおよび性能カウンタ領域より優先してデコードし、同じ書込みが複数の
周辺回路へ届かないようにした。読出しは既存DMEMと同じ1サイクル同期応答と
する。

`mtime >= mtimecmp`をレベル型のタイマ割込み要求とし、`timer_irq_i`として
CPUへ入力する。CPUでの受付条件は次のとおり。

```text
ExMa_v
&& timer_irq_i
&& mstatus.MIE
&& mie.MTIE
&& !ExMa_stall
&& !w_stall
```

同期例外、`mret`、CSR書込みと同じサイクルでは割込みを遅延させる。特に
CSR書込み中の受付を遅らせることで、完了扱いにしたCSR命令の更新がトラップ
入口の更新優先度によって失われないようにした。

タイマ割込みは命令に起因する同期例外ではないため、MA段の命令は通常どおり
リタイアさせ、その命令の次に実行すべきPCを`mepc`へ保存する。分岐がtaken
なら分岐先、それ以外なら`ExMa_pc+4`を再開PCとする。IF、ID、EX段の若い命令は
破棄し、次をCSRへ保存して`mtvec`へ移動する。

```text
mepc         <- MA段命令の次に実行すべきPC
mcause       <- 0x80000007
mstatus.MPIE <- mstatus.MIE
mstatus.MIE  <- 0
mstatus.MPP  <- 3（Machine mode）
PC           <- mtvec.BASE
```

テスト用の`timer_test.S`とC側検査では次を確認する。

1. 連続した`mtime`読出しで値が増加する。
2. 要求がpendingでも両許可ビットが0なら割込みを受けない。
3. `mstatus.MIE`だけが1でも割込みを受けない。
4. `mie.MTIE`だけが1でも割込みを受けない。
5. `mtimecmp`を128 tick後へ設定し、両許可ビットを1にする。
6. 待機ループ中にMachine Timer Interruptを受ける。
7. ハンドラで`mcause`、`mepc`、`mstatus`をDMEMへ記録する。
8. RV32で安全な順序で`mtimecmp`を最大値へ更新する。
9. `mepc`を変更せず`mret`し、待機ループへ戻る。
10. 割込み有効のまま短時間待ち、同じ割込みが再発しないことを確認する。

`mtimecmp`の更新順序は次のとおり。

```text
mtimecmp[31:0]  <- 0xffffffff
mtimecmp[63:32] <- 新しい上位値
mtimecmp[31:0]  <- 新しい下位値
```

不一致時のシグネチャは次のとおり。

```text
0xdead0016 = mtimeが増加しない
0xdead0017 = 両許可ビットが0なのに割込み発生
0xdead0018 = mstatus.MIEだけで割込み発生
0xdead0019 = mie.MTIEだけで割込み発生
0xdead001a = タイマハンドラ到達回数不一致
0xdead001b = mcause不一致
0xdead001c = mepc不一致または非アライン
0xdead001d = トラップ入口のmstatus不一致
0xdead001e = mret後の処理へ未到達
0xdead001f = mret後のmstatus不一致
0xdead0020 = 割込み受付時刻がmtimecmpより前
```

### 確認結果

ELFでは次の配置となった。

```text
timer_interrupt_test = 0x000007c8
timer_wait_start     = 0x00000830
timer_wait_end       = 0x00000844
timer_trap_handler   = 0x00000884
```

逆アセンブルで、待機ループ、割込み要因解除、`mret`を確認した。

```asm
00000830 <timer_wait_start>:
830: 00140413  addi s0,s0,1
83c: 0002a303  lw   t1,0(t0)
840: fe0308e3  beqz t1,830 <timer_wait_start>

00000884 <timer_trap_handler>:
890: 342022f3  csrr t0,mcause
8a0: 341022f3  csrr t0,mepc
8b0: 300022f3  csrr t0,mstatus
8e0: 0062a023  sw   t1,0(t0)  // mtimecmp low = 0xffffffff
8e4: 0062a223  sw   t1,4(t0)  // mtimecmp high = 0xffffffff
8e8: 0062a023  sw   t1,0(t0)
90c: 30200073  mret
```

シミュレーションでは次を確認した。

```text
CSR_WE: addr=305 data=00000884
WE: addr=60004000 data=00000294
CSR_WE: addr=304 data=00000080
CSR_WE: addr=300 data=00000008
TRAP: pc=00000838 cause=80000007
WE: addr=10000028 data=80000007  // mcause
WE: addr=10000024 data=00000838  // mepc
WE: addr=10000020 data=00001880  // trap-entry mstatus
WE: addr=1000000c data=000002a8  // mtime at trap (>= 0x294)
WE: addr=60004000 data=ffffffff
WE: addr=60004004 data=ffffffff
WE: addr=1000002c data=00000001  // interrupt count
WE: addr=1000001c data=00000001  // resumed after MRET
```

命令領域は2324 byte、初期化済みデータは8 byte、BSSは68 byteで、現在の
IMEM 32 KiBおよびDMEM 16 KiBに収まっている。過去のテスト1からテスト7も
含め、904サイクルで最終結果がPASSした。

```text
WE: addr=10000000 data=12345678
MTKERNEL_SMOKE: PASS
```

このテストではポーリングループを使用した。`wfi`の実停止・割込み復帰動作は、
フルカーネルの低消費電力待機経路を確認する段階で別途実装・検証する。

## テスト9: μT-Kernelの初期化完了（完了）

### 目的

μT-Kernel本体をリンクし、最初のユーザー処理へ到達するところまで確認する。
まだ複数タスクの動作確認は行わない。

### 最初に無効化を検討する機能

- 未実装UARTを使用するT-Monitor
- システムメッセージ出力
- ADC、I2C、シリアルなどのデバイスドライバ
- 現段階で不要な物理タイマ機能
- デバッガ支援機能

ハードウェア未実装のMMIOへアクセスしない最小構成にする。

### 実装内容

- CFU-PG向けのフルカーネル用リンカスクリプトを作る。
- `.data`をDMEMへ直接初期配置する。
- `.bss`を`Reset_Handler`でゼロクリアする。
- `INTERNAL_RAM_START`、`INTERNAL_RAM_END`を実際のDMEMに合わせる。
- `-Os -march=rv32im_zicsr -mabi=ilp32`でビルドする。
- MapファイルでIMEM/DMEMからはみ出していないことを確認する。
- `usermain()`の先頭でPASSシグネチャを書く。

### 合格条件

- リンクエラーがない。
- 全セクションが設定したIMEM/DMEM内に収まる。
- 例外ハンドラへ落ちずに`usermain()`へ到達する。
- `usermain()`到達シグネチャを確認できる。

フルカーネルを今後も実行できるよう、Test 9以降はIMEMを128 KiB、DMEMを
64 KiBとする。この容量をCFU-PGの標準構成とし、Test 9専用の条件分岐には
しない。

### 実装内容

CFU-PG側へ`mtkernel-test9`、`mtkernel-test9-build`、`mtkernel-test9-run`を追加し、
μT-Kernel本体を次の条件で直接ビルドできるようにした。

```text
-Os -std=gnu17 -march=rv32im_zicsr -mabi=ilp32
-ffreestanding -fno-builtin -nostdlib -mno-relax
```

`gnu17`は、μT-Kernelが汎用関数ポインタ`FP`に旧形式の空引数リストを使用して
おり、GCC 15の既定C23モードでは引数付き呼出しがエラーになるため明示した。

共通リンカスクリプト`app/mtkernel.ld`を追加した。IMEMを
`0x00000000`から128 KiB、DMEMを`0x10000000`から64 KiBとし、`.rodata`、
`.data`、`.bss`、カーネルヒープ、例外スタック、初期タスクスタックをDMEMへ
配置する。`.data`のロードアドレスと実行アドレスを同じにして`memd.txt`へ
直接初期配置し、`.bss`は本来の`reset_hdl.c`でゼロクリアする。テスト1から
テスト8まで使用した検査用ハンドラは`reset_hdl_test.c`として残す。

CFU-PG構成は`CFU_MTKERNEL`で選択する。T-Monitor APIは共通コンソール機能として
有効にし、システムメッセージ、デバッガ支援、物理タイマAPI、デバイス
マネージャ、シャットダウン処理は未実装のため無効にする。Test 9固有の
`CFU_MTKERNEL_TEST9`はテスト用`usermain()`の選択だけに使用する。システム
タイマ初期化はTest 8で追加したMachine Timer MMIOを使用する。

`usermain()`へ到達するまでの経路は次のとおり。

```text
_start
  -> Reset_Handler
  -> knl_startup_hw（mtvec設定）
  -> .data初期化、.bssゼロクリア、カーネルヒープ範囲設定
  -> main
  -> メモリアロケータ、割込み、カーネルオブジェクト、タイマ初期化
  -> 初期タスク生成・開始
  -> knl_dispatch_to_schedtsk
  -> mretによる初期タスク開始
  -> init_task_main
  -> usermain
```

Test 9用`usermain()`では、非ゼロ初期値を持つ`.data`変数と`.bss`変数を確認して
から`0x12345679`を`0x10000000`へ書く。失敗値は次のとおり。

```text
0xdead0091 = .dataの非ゼロ初期値が不一致
0xdead0092 = .bssがゼロクリアされていない
```

### 確認結果

ELFはRV32、エントリポイント`0x00000000`で生成され、主なシンボルは次の配置と
なった。

```text
_start                    = 0x00000000
knl_dispatch_to_schedtsk  = 0x00000024
Reset_Handler             = 0x000004f8
main                      = 0x00001438
usermain                  = 0x000014d4
cfu_test9_status          = 0x10000000
cfu_test9_data            = 0x1000001c
__bss_start               = 0x10000020
__bss_end                 = 0x100022d0
_stack_top                = 0x10010000
```

セクション使用量は`.text` 5568 byte、`.test_status` 4 byte、`.rodata` 24 byte、
`.data` 4 byte、`.bss` 8880 byteであり、設定したIMEM 128 KiBとDMEM 64 KiBに
収まった。逆アセンブルでは初期タスクの復帰PCが`mepc`へ設定され、`mret`後に
`init_task_main`から`usermain`が呼ばれることを確認した。

Verilatorでは例外ハンドラへ落ちず、Test 9の到達シグネチャを確認した。

```text
MTKERNEL_TEST9: PASS
mcycle   = 13943
minstret = 13262
```

テスト1からテスト8のスモークテストも再実行し、従来どおり904サイクル、
660命令退役でPASSした。

## テスト10: 単一タスクの起動と終了（完了）

### 目的

ディスパッチ処理、タスク用スタック、`mret`によるタスク開始を確認する。

### 実装内容

- `usermain()`からタスクを1個だけ生成する。
- 最初のタスクでは`tk_dly_tsk()`を使わない。
- タスク入口でシグネチャを書く。
- タスクから単純な関数を呼び、タスクスタックも確認する。
- 最後に`tk_ext_tsk()`を呼ぶ。

### 合格条件

- `tk_cre_tsk()`が正常なタスクIDを返す。
- `tk_sta_tsk()`が`E_OK`を返す。
- タスク入口へ到達する。
- タスクのスタックポインタが割り当て範囲内にある。
- タスク終了後に不正命令・不正メモリアクセスが発生しない。

### 実装・検証内容

Test 9用の最小構成を継続して使用し、`usermain()`から優先度1、ユーザー
スタック512 byteのタスクを1個生成した。初期タスクも優先度1であるため、
タイマ待ちは使わず`tk_rot_rdq(TPRI_RUN)`でready queueを明示的に回転して
ユーザータスクへ切り替える。

ユーザータスクでは、開始コード`stacd`、拡張情報`exinf`、8 byte境界に整列した
スタックポインタ、`noinline`関数内のローカル配列を検査してから
`tk_ext_tsk()`を呼ぶ。初期タスクへ戻った後、`tk_ref_tsk()`でユーザータスクが
`TTS_DMT`になったことを確認してPASSシグネチャを書く。

最初の実行では、ユーザータスクの`tk_ext_tsk()`後に初期タスクへ戻る際、
`knl_dispatch()`が`call knl_dispatch_entry`で`ra`を上書きしていたため、復帰先の
`ret`を繰り返してタイムアウトした。`knl_dispatch_entry`への遷移を末尾呼出しへ
変更し、呼出し元の`ra`を保存するよう修正した。

### 確認結果

実測値は次のとおり。

```text
tk_cre_tsk()       = 2
tk_sta_tsk()       = E_OK
tk_rot_rdq()       = E_OK
task SP            = 0x10002b18
heap lower bound   = 0x10002300
heap upper bound   = 0x1000f800
stack call result  = 0xb7910c22
tk_ref_tsk()       = E_OK
task state         = TTS_DMT (0x10)
```

タスクスタックは`tk_cre_tsk()`から`knl_Imalloc()`を通して内部メモリプールに
確保された。指定したユーザースタック512 byteにシステムスタック256 byteが
加算され、確保サイズは768 byteとなる。実際の割当範囲は
`0x10002828`以上`0x10002b28`未満であり、タスク関数プロローグ後のSP
`0x10002b18`がこの範囲内にあることを確認した。

Verilatorでは次の結果となった。

```text
MTKERNEL_TEST9: PASS
mcycle   = 15670
minstret = 14518
```

テスト1からテスト8のスモークテストも再実行し、従来どおり904サイクル、
660命令退役でPASSした。

## テスト11: タイマ待ちと2タスク切替（完了）

### 目的

タイマ割込み、待ちキュー、コンテキスト保存・復元、複数タスクの切替をまとめて
確認する。

### 実装内容

- タスクAとタスクBを生成する。
- 各タスクが異なる値をDMEMへ記録する。
- 各タスクで`tk_dly_tsk()`を呼ぶ。
- タイマ割込みごとに実行順序をログ領域へ記録する。
- 各タスクでcallee-savedレジスタに既知の値を保持し、切替後も保たれるか確認する。

期待する実行例:

```text
Task A start
Task B start
Task A wakeup
Task B wakeup
Task A finish
Task B finish
```

### 合格条件

- Machine Timer Interruptが継続して発生する。
- `tk_dly_tsk()`したタスクが指定時間後に起床する。
- タスクA/Bのスタックが互いに破壊されない。
- 切替前後で保存対象レジスタが保持される。
- 両タスクが最後まで終了する。

### 実装・検証内容

CFU-PG側へ`mtkernel-test11`、`mtkernel-test11-build`、
`mtkernel-test11-run`を追加した。Test 9/10と同じ最小カーネル構成を使用するが、
テスト本体は`app/mtkernel_test11.c`としてCFU-PG側に分離した。

初期タスクを優先度1、タスクA/Bを同じ優先度2として生成する。各タスクには
`TA_USERBUF`で独立した1024 byteのスタックを与え、初期タスクが
`tk_dly_tsk(100)`で待っている間に次の順序で実行するよう遅延時間を設定した。

```text
Task A: start -> tk_dly_tsk(10) -> wake -> tk_dly_tsk(10) -> finish
Task B: start -> tk_dly_tsk(20) -> wake -> tk_dly_tsk(10) -> finish
```

μT-Kernelは指定時間以上の待ちを保証するため内部で1周期分を加算する。このため、
10 ms周期のタイマではAが20 ms後、Bが30 ms後に最初に起床し、Aが40 ms後、
Bが50 ms後に終了する。実行イベントはDMEM上の6ワードのログへ記録し、初期
タスクが期待値と完全一致することを検査する。

各タスクでは、スタック上の8ワードのガード値を2回の待ちの前後で検査する。
さらにRISC-Vのcallee-savedレジスタ`s2`から`s5`へタスクごとに異なる既知値を
保持し、各`tk_dly_tsk()`から復帰した直後に値を比較する。逆アセンブルでも、
これらのレジスタへの定数ロードと待ち復帰後の比較命令が生成されたことを確認
した。

テストベンチはCPUが実際に受理したMachine Timer Interruptを数え、10回以上の
割込みに加えて最終シグネチャ`0x1234567b`が書かれた場合だけPASSとする。

### 確認結果

DMEMのイベントログは期待した順序となった。

```text
0x10002af0 = 0xa1100001  // Task A start
0x10002af4 = 0xb2200001  // Task B start
0x10002af8 = 0xa1100002  // Task A wakeup
0x10002afc = 0xb2200002  // Task B wakeup
0x10002b00 = 0xa1100003  // Task A finish
0x10002b04 = 0xb2200003  // Task B finish
```

タスクスタックと実測SPは次のとおりで、互いに重ならず、それぞれ割当範囲内に
収まっている。

```text
Task B stack = [0x100022f0, 0x100026f0), SP = 0x100026b0
Task A stack = [0x100026f0, 0x10002af0), SP = 0x10002ab0
```

初期タスクの待ち前後でシステム動作時刻は110 ms進み、両タスクは最後に
`TTS_DMT`となった。Verilatorでは11回のタイマ割込みを受理し、次の結果となった。

```text
MTKERNEL_TEST11: PASS (timer_irqs=11)
mcycle   = 127571
minstret = 114630
```

Test 9/10も15670サイクル、14518命令退役でPASSした。テスト1から
テスト8のスモークテストも904サイクル、660命令退役でPASSした。

## テスト12: コンソール出力（完了）

### 目的

シグネチャだけでなく、`tm_printf()`などで実行状況を確認できるようにする。

### 注意事項

変更前のRISC-Vポートの`tm_com.c`はUARTを`0x10000000`としていたが、ここは
CFU-PGのDMEMと衝突していた。この実装は使用せず、現在はCFU-PG共通の
`tm_com.c`がシミュレーション用putchar MMIOの`0x80000000`へ出力する。

### 選択肢

1. シミュレーション専用putchar MMIOを別アドレスに実装する。
2. FPGA用UART MMIOを実装する。
3. T-Monitorを無効のままにして、シグネチャ方式を継続する。

最初は1を推奨する。1文字書き込み用アドレスを決め、`top.v`で文字として
表示する。

### 合格条件

- DMEMアクセスとUARTアクセスが衝突しない。
- `tm_printf()`から既知の文字列を表示できる。
- 文字出力中もタイマ割込みとタスク切替が動作する。

### 実装・検証内容

CFU-PG側へ`mtkernel-test12`、`mtkernel-test12-build`、
`mtkernel-test12-run`を追加した。検証後、コンソールをTest 12専用構成から
通常のCFU-PG向けμT-Kernel構成へ昇格した。`CFU_MTKERNEL`構成では
`USE_TMONITOR`が有効になり、通常の`make mtkernel`もμT-Kernel本体の
`libtm.c`、`libtm_printf.c`およびRISC-V用`tm_com.c`をリンクする。
Test 12専用だった`mtkernel_test12_config.h`と`mtkernel_test12_tm_com.c`は削除した。

シミュレーション専用putchar MMIOを次のアドレスとした。

```text
0x80000000 = 1文字出力（下位8 bit）
```

このアドレスはDMEMの`0x10000000`から始まる領域、タイマMMIO、性能カウンタ、
ビデオメモリのいずれとも重ならない。`tm_snd_dat()`は1文字ごとに32 bit storeを
行い、`top.v`が下位8 bitを`$write()`で表示する。UART状態レジスタのポーリングは
行わない。

Test 12用`usermain()`は優先度2のタスクA/Bを生成する。初期タスクは
`tk_dly_tsk(100)`で待ち、タスクAは10 ms、タスクBは20 msの遅延後に再開する。
各開始・起床時に`tm_printf()`を呼び、`%x`および`%d`の書式変換も確認する。
イベントログは次の順序を検査する。

```text
Task A start
Task B start
Task A wakeup
Task B wakeup
```

文字列が`tm_printf()`から`tm_putchar()`、`tm_snd_dat()`、MMIO書込みまで欠落なく
順序どおり届いたことを確認するため、テストベンチで出力バイト数とFNV-1a
ハッシュを計算する。アプリケーション側は通常の共通コンソールドライバだけを
使用し、テスト用の計測処理を含まない。PASS条件は次のすべてとした。

```text
最終シグネチャ     = 0x1234567c
タイマ割込み受理数 >= 10
コンソール出力     = 157 byte
FNV-1aハッシュ     = 0x7444ff7b
```

### 確認結果

Verilatorでは次の文字列が表示された。

```text
MTKERNEL_TEST12: usermain
Task A: start value=a11a
Task B: start value=b22b
Task A: wake delay=10
Task B: wake delay=20
MTKERNEL_TEST12: PASS events=4
```

テストベンチの最終結果は次のとおり。

```text
MTKERNEL_TEST12: PASS (timer_irqs=11 chars=157 hash=7444ff7b)
mcycle   = 129873
minstret = 107235
```

ELFの使用量は`.text` 10888 byte、`.rodata` 248 byte、`.data` 4 byte、
`.bss` 10992 byteであり、IMEM 128 KiBおよびDMEM 64 KiBに収まっている。
共通コンソールへ移行後もTest 12は同じ157 byteとハッシュでPASSした。
Test 11は127571サイクル、114630命令退役、Test 9/10は15670サイクル、
14518命令退役、テスト1からテスト8のスモークテストは904サイクル、660命令
退役で、いずれも従来どおりPASSした。

## テスト13: FPGA実機（未着手）

### 目的

Verilatorで確認済みの構成をFPGA上で動作させる。

### 実施前条件

- テスト12までVerilatorでPASSしている。
- FPGA向けクロック周波数とタイマ周期が一致している。
- IMEM/DMEM容量がFPGAのBlock RAMへ収まる。
- タイミング制約を満たしている。
- FPGA上で結果を観測する手段がある。

### 最初の観測方法

- LEDへPASS/FAIL状態を出す。
- UARTへ固定文字列を出す。
- ILAでPC、トラップCSR、DMEM書き込みを観測する。

### 実装予定

1. 対象FPGAボードと使用するUART端子、クロック、ボーレートを確定する。
2. 現在のシミュレーション用`0x80000000`出力とは別に、FPGA用UART MMIOを実装する。
3. `tm_snd_dat()`の上位APIを変えず、ビルド対象に応じてシミュレーション用と
   FPGA用の下位トランスポートを選択できるようにする。
4. `make mtkernel-run`で確認済みのアプリケーションをFPGA用にビルドする。
5. 単一タスク、タイマ割込み、複数タスク切替、`tm_printf()`の順に実機確認する。
6. UART出力に加え、必要に応じてLEDまたはILAでPASS/FAILを確認する。

### 合格条件

- リセット後に`_start`から実行される。
- 単一タスクが起動する。
- タイマ割込みが周期的に発生する。
- 複数タスクが切り替わる。
- UARTまたはLEDで完了状態を確認できる。

## テスト13完了後のファイル整理

コンソール出力とTest 13のFPGA実機確認が完了するまでは、UART実装、`tm_com.c`、
テストベンチ、FPGAビルド手順が変わる可能性がある。このため、それまでは現在の
テストターゲットと検査コードを移動しない。

Test 13がPASSした時点で通常アプリケーションと回帰テストの境界を確定し、次の
整理をまとめて実施する。

```text
CFU-Proving-Ground/
├── Makefile                 # 通常アプリ用mtkernel、build、runだけ
├── app/
│   └── mtkernel.ld          # 通常アプリ用リンカスクリプト
└── tests/mtkernel/
    ├── Makefile             # smoke、Test 9、11、12、13
    ├── top_test.v           # PASS/FAIL判定とテスト用監視
    ├── apps/                # 各テストのusermain
    ├── ld/                  # テスト専用リンカスクリプト
    └── scripts/             # トレース解析など
```

整理時には次を行う。

- `app/mtkernel_test11.c`と`app/mtkernel_test12.c`を`tests/mtkernel/apps/`へ移す。
- smokeおよびTest 9以降のMakeターゲットを`tests/mtkernel/Makefile`へ移す。
- `top.v`と`main.v`からテスト固有の条件分岐とPASS/FAIL判定を取り除く。
- 通常アプリ用のルートMakefileには`mtkernel`、`mtkernel-build`、
  `mtkernel-run`だけを残す。
- 回帰テストは`make -C tests/mtkernel check`でまとめて実行できるようにする。
- シミュレーション用とFPGA用のコンソール下位層を明確に分離する。

テストをCFU-PGの外側へ完全に分離すると、RTLとテストのコミットがずれる可能性が
あるため、原則として同じリポジトリ内の`tests/mtkernel/`へ配置する。

## 各テストで必ず保存する情報

各段階で次を残す。

- 使用したソースコード
- コンパイルオプション
- `main.elf`
- `main.dump`
- リンカMapファイル
- `memi.txt`と`memd.txt`
- Verilatorの実行ログ
- FPGAのビルドログ、UARTログ、ILA結果（Test 13）
- PASS/FAILシグネチャ
- 失敗した場合の最後のPC、命令、`mcause`、`mepc`

## 推奨する直近の作業

Test 12まで完了しているため、次に着手するのはTest 13のFPGA実機確認とする。

1. 対象ボード、UART端子、クロック周波数、ボーレートを確定する。
2. FPGA用UARTトランスポートを実装し、固定文字列を確認する。
3. μT-Kernelの起動、単一タスク、タイマ割込み、複数タスク切替を順に確認する。
4. 標準`usermain()`から`tm_printf()`の出力を確認する。
5. Test 13をPASSにした後、この計画に従ってテスト一式を`tests/mtkernel/`へ移す。
