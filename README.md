# 100G RDMA AllReduce FPGA

本仓库保存 4×100G FPGA RoCEv2/RDMA AllReduce 工程中需要长期管理和回溯的源码、IP 配置、约束、VIO/Hardware Manager 脚本、Worker 测试程序和实验报告。

当前已验证基线：

- FPGA：Xilinx `xcvu13p-fhgb2104-2-i`
- Vivado：2025.2
- 两个 100G RoCEv2 Worker
- RC QP
- 1024B `SEND_ONLY`
- FPGA 为 root
- Worker0/Worker1 fan-in 聚合后广播
- Worker Receive CQE 成功
- Worker Send CQE 成功

当前结论是“双 Worker、单轮、1024B RDMA AllReduce 硬件闭环已成功”。多轮持续运行仍需要继续验证，不应把该版本描述为生产级稳定实现。

## 1. 仓库结构

```text
100G_RDMA_ALLREDUCE/
├─ imports/src/                 # 当前 RTL、顶层、CMAC、交换与 AllReduce 模块
├─ new/                         # AllReduce wrapper、动态配置、per-port rewriter
├─ ip/                          # Vivado IP 的 XCI 配置
├─ constraints/                 # FPGA 时序与引脚约束
├─ configs/                     # 实验室两 Worker VIO 固定配置
├─ scripts/                     # 仿真、构建、烧录、VIO 配置与读回脚本
├─ worker_rdma_qp/              # libibverbs RC QP 测试程序
├─ docs/                        # 工程演进和硬件调试报告
├─ .gitattributes
├─ .gitignore
└─ README.md
```

Vivado 的 `.runs`、`.cache`、`.Xil`、DCP、bitstream、ILA 抓取、Wireshark 抓包和运行日志不进入 Git。它们是机器或单次实验产物，不是代码真值。

### 1.1 旧仓库中保留但未被当前 XPR 引用的文件

以下文件来自目标仓库原有 `master` 提交。为保留历史，本次没有删除或移动它们，但服务器当前 `100G_4port_allreduce_proj.xpr` 没有引用这些文件：

```text
imports/src/allreduce/down_broadcast_bram_arbiter_top.v
imports/src/allreduce/retrans_bram_arbiter_top.v
imports/src/allreduce/sloter_bram_arbiter_top.v
imports/src/allreduce/up_broadcast_bram_arbiter_top.v
imports/src/allreduce/tb_aggregate_buffer_controller.v
imports/src/allreduce/tb_bram_write_demux.v
imports/src/allreduce/tb_broadcast_checkor_arrival_updater.v
imports/src/allreduce/tb_down_broadcast_checkor_arrival_updater.v
imports/src/allreduce/tb_downbroadcast_bram_arbiter_top.v
imports/src/allreduce/tb_parser.v
imports/src/allreduce/tb_parser_aeth.v
imports/src/allreduce/tb_retrans_bram_arbiter_top.v
imports/src/allreduce/tb_retrans_checkor_arrival_updater.v
imports/src/allreduce/tb_sloter_bram_arbiter_top.v
imports/src/allreduce/tb_Typer.v
imports/src/allreduce/tb_upbroadcast_bram_arbiter_top.v
new/tb_allreduce_switch_datapath.v
```

后续综合和行为仿真应以 XPR 中的 fileset/compile order 为准，不要仅因为文件存在于仓库就把它加入当前设计。

## 2. 当前实验连接

| 角色 | RDMA 设备 | Linux netdev | MAC | IPv4 | 逻辑 ingress |
|---|---|---|---|---|---:|
| FPGA | — | — | `02:00:00:00:03:07` | `192.168.3.7` | — |
| Worker0 | `mlx5_0` | `enp193s0f0np0` | `6c:b3:11:88:ab:3e` | `192.168.3.5/24` | 0 |
| Worker1 | `mlx5_2` | `enp129s0f0np0` | `6c:b3:11:88:a9:4e` | `192.168.3.6/24` | 1 |

固定实验配置：

```text
RoCEv2 UDP port = 4791 (0x12B7)
FPGA QPN         = 0x000100
root             = 1
child_port_mask  = 0x3
```

Worker QPN 由 Linux 每次创建 QP 时动态分配，不能写死在仓库中。

## 3. 仓库与服务器 Vivado 工程的目录映射

当前服务器工程：

```text
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
```

当前 Worker：

```text
/home/ubuntu/cyf/NSDI27/worker_rdma_qp
```

仓库路径与工程路径映射：

| 仓库 | 服务器工程 |
|---|---|
| `imports/` | `100G_4port_allreduce_proj.srcs/sources_1/imports/` |
| `new/` | `100G_4port_allreduce_proj.srcs/sources_1/new/` |
| `ip/` | `100G_4port_allreduce_proj.srcs/sources_1/ip/` |
| `constraints/timing_4port.xdc` | `100G_4port_allreduce_proj.srcs/constrs_1/imports/constrs/timing_4port.xdc` |
| `configs/` | `configs/` |
| `scripts/` | `scripts/` |
| `worker_rdma_qp/` | `/home/ubuntu/cyf/NSDI27/worker_rdma_qp/` |

仓库不保存完整 `.xpr`，因为服务器当前 `.xpr` 包含本机 run、DCP 和生成目录引用。仓库以 RTL、XCI、约束和可执行脚本作为代码真值。

## 4. 从仓库同步到现有服务器工程

该仓库是私有仓库。首次使用前必须在当前机器配置 GitHub SSH key，或使用 GitHub CLI 完成交互式授权。不要把 Personal Access Token 写入脚本、README 或 Git 配置文件。

使用 GitHub CLI：

```bash
gh auth login
gh auth setup-git
gh repo clone kugaichen/100G_RDMA_ALLREDUCE \
  /home/ubuntu/cyf/NSDI27/100G_RDMA_ALLREDUCE
```

已经配置 GitHub SSH key 时：

```bash
cd /home/ubuntu/cyf/NSDI27
git clone git@github.com:kugaichen/100G_RDMA_ALLREDUCE.git
```

设置明确路径：

```bash
export REPO_DIR=/home/ubuntu/cyf/NSDI27/100G_RDMA_ALLREDUCE
export PROJECT_DIR=/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
```

预览同步内容：

```bash
rsync -avn "$REPO_DIR/imports/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/imports/"

rsync -avn "$REPO_DIR/new/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/new/"

rsync -avn "$REPO_DIR/ip/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/ip/"
```

确认预览后执行同步：

```bash
rsync -av "$REPO_DIR/imports/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/imports/"

rsync -av "$REPO_DIR/new/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/new/"

rsync -av "$REPO_DIR/ip/" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/sources_1/ip/"

install -m 0644 "$REPO_DIR/constraints/timing_4port.xdc" \
  "$PROJECT_DIR/100G_4port_allreduce_proj.srcs/constrs_1/imports/constrs/timing_4port.xdc"

rsync -av "$REPO_DIR/configs/" "$PROJECT_DIR/configs/"
rsync -av "$REPO_DIR/scripts/" "$PROJECT_DIR/scripts/"
```

Worker 同步：

```bash
rsync -av "$REPO_DIR/worker_rdma_qp/" \
  /home/ubuntu/cyf/NSDI27/worker_rdma_qp/
```

这些命令没有使用 `--delete`，不会自动删除工程中额外存在的文件。同步前先执行 `-n` 预览。

## 5. Vivado 环境

服务器当前 Vivado 初始化脚本：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
vivado -version
```

若迁移到其他服务器，先查找真实路径：

```bash
find /opt /tools /home -name settings64.sh 2>/dev/null
```

不要把未经确认的 Vivado 路径写入 shell profile 或脚本。

## 6. 行为级仿真

进入工程：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
mkdir -p logs
```

ICRC 行为仿真：

```bash
vivado -mode batch \
  -source scripts/run_icrc_behavioral.tcl \
  -log logs/icrc_behavioral.log \
  -journal logs/icrc_behavioral.jou
```

完整数据通路行为仿真：

```bash
vivado -mode batch \
  -source scripts/run_phase7_behavioral.tcl \
  -log logs/phase7_behavioral.log \
  -journal logs/phase7_behavioral.jou
```

查看结果：

```bash
grep -E "PASS|FAIL|ERROR|FATAL" \
  logs/icrc_behavioral.log \
  logs/phase7_behavioral.log
```

## 7. 综合、实现和 bitstream

当前最小构建脚本使用 Vivado `Flow_RuntimeOptimized`，完成综合、实现和 bitstream：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

vivado -mode batch \
  -source scripts/run_minimal_build.tcl \
  -log logs/minimal_build.log \
  -journal logs/minimal_build.jou
```

预期产物：

```text
100G_4port_allreduce_proj.runs/impl_1/
├─ qsfp28_100g_switch_4port_top.bit
└─ qsfp28_100g_switch_4port_top.ltx
```

构建后检查：

```bash
stat \
  100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit \
  100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx

grep -E "MINIMAL_BUILD_PASS|ERROR|CRITICAL WARNING" \
  logs/minimal_build.log
```

注意：

- 不要同时运行 GUI implementation 和 batch implementation；
- `.bit` 与 `.ltx` 必须来自同一次 run；
- 烧录前记录路径和生成时间；
- 当前版本存在时序违例，单轮功能已成功，但多轮稳定性尚未证明。

## 8. 烧录 FPGA

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

BIT_FILE="$PWD/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit"
LTX_FILE="$PWD/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx"

vivado -mode batch \
  -source scripts/hw_program_pair_codex22.tcl \
  -tclargs "$BIT_FILE" "$LTX_FILE" \
  -log logs/program_hw.log \
  -journal logs/program_hw.jou
```

期望：

```text
CODEX22_PROGRAM_PAIR_PASS
VIO_PORT_ENABLE=b
```

重新烧录后，AllReduce VIO 输出会回到默认值。必须重新执行完整 VIO 配置，不能只改 Worker QPN。

## 9. Linux 网络与静态邻居

检查接口和路由：

```bash
ip -4 addr show dev enp193s0f0np0
ip -4 addr show dev enp129s0f0np0

ip route get 192.168.3.7 from 192.168.3.5
ip route get 192.168.3.7 from 192.168.3.6

rdma link
```

FPGA 当前不依赖 ARP 学习，两个 Worker 接口需要静态邻居：

```bash
sudo ip neigh replace 192.168.3.7 \
  lladdr 02:00:00:00:03:07 \
  nud permanent dev enp193s0f0np0

sudo ip neigh replace 192.168.3.7 \
  lladdr 02:00:00:00:03:07 \
  nud permanent dev enp129s0f0np0
```

验证：

```bash
ip neigh show 192.168.3.7 dev enp193s0f0np0
ip neigh show 192.168.3.7 dev enp129s0f0np0
```

两项都应为 `PERMANENT`。该内核配置通常会在重启后丢失。

## 10. 编译 Worker

依赖：

```bash
sudo apt-get install build-essential libibverbs-dev rdma-core
```

编译：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp
make clean
make
```

生成：

```text
worker_rdma_qp
```

不要提交该可执行文件；仓库只管理 `worker_rdma_qp.c`、`Makefile` 和必要脚本。

## 11. 双 Worker 单轮 1024B 测试

### 11.1 清理本轮 gate

```bash
rm -f /tmp/manual_gate0.0 /tmp/manual_gate1.0
```

### 11.2 启动 Worker0

终端 1：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp

./worker_rdma_qp \
  -d mlx5_0 \
  -i 1 \
  -n enp193s0f0np0 \
  -G 3 \
  -R ::ffff:192.168.3.7 \
  -r 0x000100 \
  -s 0 \
  -q 0 \
  -N 1 \
  -B 0xff \
  -W /tmp/manual_gate0 \
  -o logs/manual_worker0.runtime
```

记录输出中的：

```text
local_qpn_hex=0x......
qp_state=3 (3=RTS)
send_waiting_for_gate=/tmp/manual_gate0.0
```

### 11.3 启动 Worker1

终端 2：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp

./worker_rdma_qp \
  -d mlx5_2 \
  -i 1 \
  -n enp129s0f0np0 \
  -G 3 \
  -R ::ffff:192.168.3.7 \
  -r 0x000100 \
  -s 0 \
  -q 0 \
  -N 1 \
  -B 0x00 \
  -W /tmp/manual_gate1 \
  -o logs/manual_worker1.runtime
```

记录 Worker1 的动态 QPN，并确认：

```text
send_waiting_for_gate=/tmp/manual_gate1.0
```

两个设备的 QPN 可能相同，也可能不同。必须分别读取。

### 11.4 将动态 QPN 写入完整 VIO 配置

假设本轮：

```text
Worker0 QPN = 0x000099
Worker1 QPN = 0x000099
```

执行：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

vivado -mode batch \
  -source scripts/apply_allreduce_vio.tcl \
  -tclargs 0x000099 0x000099 \
  -log logs/apply_vio.log \
  -journal logs/apply_vio.jou
```

期望：

```text
VIO_APPLY_PASS
```

读取确认：

```bash
vivado -mode batch \
  -source scripts/read_allreduce_vio_outputs.tcl \
  -log logs/read_vio.log \
  -journal logs/read_vio.jou
```

必须确认：

```text
FPGA QPN       = 0x000100
Worker0 QPN    = 本轮动态值
Worker1 QPN    = 本轮动态值
FPGA UDP       = 4791
Worker0 UDP    = 4791
Worker1 UDP    = 4791
root           = 1
child mask     = 3
MAC/IP         = 本 README 第 2 节配置
```

### 11.5 同时释放两个 Worker

终端 3：

```bash
touch /tmp/manual_gate0.0 /tmp/manual_gate1.0
```

### 11.6 成功判据

两个 Worker 都必须出现：

```text
Receive CQE: status=success, byte_len=1024
Send CQE:    status=success
recv_success=1
send_success=1
iterations_done=1
```

Worker0=`0xff`、Worker1=`0x00` 时，两侧接收数据应全部为 `0xff`。

另一组推荐数据：

```text
Worker0 = 0x02
Worker1 = 0x03
expected aggregate = 0x05
```

使用不同 payload 可以发现单边原样返回、旧缓存或未聚合问题。

## 12. 多轮 gate 与 PSN

若使用：

```text
-N 5
-W /tmp/manual_gate0
```

Worker0 会依次等待：

```text
/tmp/manual_gate0.0
/tmp/manual_gate0.1
/tmp/manual_gate0.2
/tmp/manual_gate0.3
/tmp/manual_gate0.4
```

`touch` 同一个 gate 多次不会触发多轮。正确做法是：

1. 启动前删除全部旧 gate；
2. 两侧都等待 `.0` 后创建两侧 `.0`；
3. 两侧都完成本轮并等待 `.1` 后，再创建两侧 `.1`；
4. 任一 Worker 出错后停止释放后续 gate，保存 ILA、CQ 和网卡计数。

当前单轮成功，多轮仍有 Worker1 较早出现 `transport retry counter exceeded` 的记录。开始多轮前应记录端口错误计数增量：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp
./read_mlx_stats.sh
```

## 13. Wireshark、tcpdump、ILA 与 CQ

普通 Wireshark/tcpdump 不一定能看到 RNIC 正常消费的 RoCEv2 报文。错误 QPN、UDP port、PSN 或 ICRC 的报文反而可能更容易进入主机抓包路径。

判据优先级：

```text
Worker Receive/Send CQE
  > RNIC 端口计数
  > FPGA ILA
  > Wireshark/tcpdump
```

看到 FPGA 返回包但没有 Receive CQE 时，检查：

```text
dst MAC
dst IP
UDP dst port = 4791
BTH destination QPN = 当前 Worker QPN
BTH PSN
payload length = 1024
ICRC
```

大量相同 PSN 的返回包通常表示 RC 重传，不表示吞吐成功。

## 14. 常见故障

| 现象 | 优先检查 |
|---|---|
| `ibv_modify_qp RTR: Invalid argument` | SGID index、remote GID、QPN、QP 参数 |
| `ibv_modify_qp RTR: Connection timed out` | `rdma link`、route、静态 neighbor |
| `ip neigh ... FAILED` | FPGA MAC、接口和静态 neighbor |
| FPGA ILA 有输入但 table miss | MAC/IP 字节序、connection table key |
| table hit但无聚合输出 | logical ingress=0/1、PSN、root、双 fan-in |
| Wireshark 有返回包但无 Receive CQE | UDP dst、QPN、PSN、ICRC |
| Receive CQE 成功但 Send CQE 失败 | Worker ACK、FPGA ACK 识别与反射 |
| 单轮成功、多轮一侧先失败 | PSN、Receive repost、ACK 状态、端口错误增量、时序 |

## 15. Git 提交与回溯

查看变化：

```bash
git status --short
git diff --stat
git diff
```

建议每次只提交一种逻辑变化：

```bash
git add imports new ip constraints configs scripts worker_rdma_qp docs README.md
git commit -m "Describe the verified change"
git push origin master
```

查看历史：

```bash
git log --oneline --decorate --graph --all
```

不破坏当前工作区地复现旧版本：

```bash
git worktree add ../reproduce-old-version <commit-or-tag>
```

删除 worktree 前先确认其中没有未提交改动：

```bash
git -C ../reproduce-old-version status --short
git worktree remove ../reproduce-old-version
```

不要使用 `git reset --hard` 回退正在实验的工程目录。

## 16. 文档索引

- `docs/RDMA_AllReduce_工程演进与测试调试指南.md`：初始失败、当前修改、定位过程和标准测试方法；
- `docs/RDMA_FPGA_ALLREDUCE_FINAL_REPORT.md`：阶段性实现与硬件测试记录；
- `docs/BEST_VERSION_IMPLEMENTATION_TEST_REPORT.md`：最佳版本实现与测试报告。

## 17. 当前代码边界

当前 connection table 是面向两个固定 Worker 的确定性测试版本，用于建立最小硬件闭环。它不是最终的多连接动态控制面。

后续建议按顺序推进：

1. 同一 bitstream 重复单轮测试；
2. 两轮逐 gate 测试；
3. 定位 Worker1/P1 间歇性错误；
4. 再增加连续流量；
5. 最后恢复可写、多表项和碰撞处理的 connection table。

任何扩展都应保留当前单轮成功版本作为 Git tag 和硬件回归基线。
