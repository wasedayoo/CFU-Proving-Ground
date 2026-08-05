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

## テスト2: スタックを使ったC関数呼び出し

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

## テスト3: `.data`、`.bss`、`gp`の確認

### 目的

初期値付きグローバル変数、ゼロ初期化変数、グローバルポインタ相対アクセスを
確認する。

### 実装内容

次のような変数を用意する。

```c
volatile uint32_t initialized_data = 0xa5a55a5a;
volatile uint32_t zero_initialized_data;
```

確認する値を別々のDMEMアドレスへ書く。

```text
0x10000000 <- initialized_data
0x10000004 <- zero_initialized_data
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
- `memd.txt`に`0xa5a55a5a`が含まれる。
- `initialized_data`の読み出し結果が`0xa5a55a5a`になる。
- `.bss`を意図的にゼロクリアし、読み出し結果が`0`になる。
- 必要に応じて`gp`相対命令の有無を`objdump`で確認する。

### 合格条件

```text
0x10000000の値 = 0xa5a55a5a
0x10000004の値 = 0x00000000
```

## テスト4: 最小CSR読み書き

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

## テスト5: 実物の`startup.S`をそのまま実行

### 目的

コメントアウトしている次の命令を元に戻す。

```asm
csrw mstatus, zero
csrw mie, zero
```

テスト1からテスト3までの処理と組み合わせ、実物の`startup.S`を変更せずに
`Reset_Handler`へ到達できることを確認する。

### 合格条件

- `startup.S`のCSR命令をコメントアウトしていない。
- `mstatus == 0`かつ`mie == 0`になっている。
- `sp`と`gp`が正しい。
- `Reset_Handler`がPASSシグネチャを書く。

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

次に着手するのはテスト2とする。

1. `reset_hdl.c`へ`noinline`のスタックテスト関数を追加する。
2. `objdump`で`sp`相対の`sw`/`lw`を確認する。
3. テストベンチの期待値をスタックテスト結果へ変更する。
4. `make mtkernel-smoke-run`でPASSを確認する。
5. PASS後、テスト3の`.data`/`.bss`確認へ進む。

