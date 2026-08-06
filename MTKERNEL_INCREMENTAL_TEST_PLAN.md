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

## 現在のビルドと実行

CFU-PGディレクトリで次を実行する。

```bash
make mtkernel-smoke-run
```

このターゲットは、次の処理を順番に行う。

```text
startup.Sとreset_hdl.cをコンパイル・リンク
    ↓
main.elfからmemi.txtとmemd.txtを生成
    ↓
Verilatorシミュレータをビルド
    ↓
obj_dir/topを実行
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

## テスト6: `mtvec`と`mret`

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

## テスト7: 同期例外によるトラップ往復

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

## テスト8: タイマMMIOとMachine Timer Interrupt

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

## テスト9: μT-Kernelの初期化完了

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

既存のμT-Kernelビルドは32 KiBのIMEMを超える可能性が高い。Verilatorでの
初期確認ではIMEMを128 KiB、DMEMを64 KiB程度へ一時的に拡張し、機能確認後に
最適化する。

## テスト10: 単一タスクの起動と終了

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

## テスト11: タイマ待ちと2タスク切替

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

## テスト12: コンソール出力

### 目的

シグネチャだけでなく、`tm_printf()`などで実行状況を確認できるようにする。

### 注意事項

現在のRISC-Vポートの`tm_com.c`はUARTを`0x10000000`としているが、ここは
CFU-PGのDMEMと衝突する。そのまま使用しない。

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

## テスト13: FPGA実機

### 目的

Verilatorで確認済みの構成をFPGA上で動作させる。

### 実施前条件

- テスト11までVerilatorでPASSしている。
- FPGA向けクロック周波数とタイマ周期が一致している。
- IMEM/DMEM容量がFPGAのBlock RAMへ収まる。
- タイミング制約を満たしている。
- FPGA上で結果を観測する手段がある。

### 最初の観測方法

- LEDへPASS/FAIL状態を出す。
- UARTへ固定文字列を出す。
- ILAでPC、トラップCSR、DMEM書き込みを観測する。

### 合格条件

- リセット後に`_start`から実行される。
- 単一タスクが起動する。
- タイマ割込みが周期的に発生する。
- 複数タスクが切り替わる。
- UARTまたはLEDで完了状態を確認できる。

## 各テストで必ず保存する情報

各段階で次を残す。

- 使用したソースコード
- コンパイルオプション
- `main.elf`
- `main.dump`
- リンカMapファイル
- `memi.txt`と`memd.txt`
- Verilatorの実行ログ
- PASS/FAILシグネチャ
- 失敗した場合の最後のPC、命令、`mcause`、`mepc`

## 推奨する直近の作業

次に着手するのはテスト6とする。

1. `mtvec`、`mepc`、`mcause`をCSRファイルへ追加する。
2. CSRの制御情報を`funct3`ベースへ整理する。
3. `CSRRC`を含む必要なCSR命令を追加する。
4. `mret`によるPC変更と`mstatus`更新を実装する。
5. 最初は割込みを発生させず、同期的な単体テストで確認する。
