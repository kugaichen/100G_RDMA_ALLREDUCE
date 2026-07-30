# 双 Worker RDMA AllReduce 多轮硬件测试记录

日期：2026-07-30

## 1. 测试目标

验证当前 bitstream 在真实 RoCEv2 RC QP 下能否连续完成多轮：

```text
Worker0/1 post_recv
→ 两侧 1024B SEND_ONLY
→ FPGA logical ingress 0/1
→ 同 PSN fan-in 聚合
→ root 广播
→ per-port rewrite + checksum/ICRC
→ Worker Receive CQE
→ RNIC ACK
→ FPGA ACK 处理与反射
→ Worker Send CQE
→ 下一轮
```

先用原 bitstream 做 2/5 轮逐 gate 测试建立最小复现；在确认 ACK
backpressure 缺陷后，只修改一行握手逻辑，重新完成行为仿真、综合、实现、
bitstream 烧录和 10 轮硬件闭环测试。

## 2. 固定配置

```text
FPGA MAC = 02:00:00:00:03:07
FPGA IP  = 192.168.3.7
FPGA QPN = 0x000100
UDP      = 4791
root     = 1
child mask = 0x3

Worker0 = mlx5_0 / enp193s0f0np0 / 192.168.3.5 / ingress 0
Worker1 = mlx5_2 / enp129s0f0np0 / 192.168.3.6 / ingress 1
```

测试数据：

```text
Worker0 payload = 1024B × 0x02
Worker1 payload = 1024B × 0x03
期望聚合结果    = 1024B × 0x05
初始 SQ/RQ PSN = 100
```

## 3. bitstream 与测试前基线

```text
bit:
2026-07-29 14:19:12 +0800
size = 65123547

ltx:
2026-07-29 14:19:13 +0800
size = 209830
```

RDMA 链路：

```text
mlx5_0/1 ACTIVE LINK_UP → enp193s0f0np0
mlx5_2/1 ACTIVE LINK_UP → enp129s0f0np0
```

静态邻居：

```text
192.168.3.7 dev enp193s0f0np0 lladdr 02:00:00:00:03:07 PERMANENT
192.168.3.7 dev enp129s0f0np0 lladdr 02:00:00:00:03:07 PERMANENT
```

VIO 读回：

```text
root=1
child_mask=3
FPGA MAC/IP/QPN/UDP 正确
Worker0 MAC/IP/UDP 正确，旧 QPN=0x00009f
Worker1 MAC/IP/UDP 正确，旧 QPN=0x00009f
```

旧 QPN 只属于上一轮已经退出的 Worker。本次创建新 QP 后必须重新写入动态 QPN。

测试前端口计数：

| 计数 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | 28 | 29 |
| `tx_vport_rdma_unicast_packets` | 260 | 254 |
| `tx_packets_phy` | 62846 | 2578 |
| `rx_packets_phy` | 18589 | 42720 |
| `rx_crc_errors_phy` | 144 | 6060 |
| `rx_bytes_phy` | 3102698 | 3474626 |
| `rx_1024_to_1518_bytes_phy` | 121 | 105 |

### 基线判断

P1 的累计 CRC 错误明显高于 P0，但累计值不能直接归因于本轮测试。后续使用测试前后差值判断是否在发送期间继续增长。

## 4. 第一次受控测试：2 轮

状态：第 0 轮失败，未进入第 1 轮。

### 4.1 本轮运行参数

```text
iterations = 2
PSN        = 100
Worker0    = 0x02
Worker1    = 0x03
gate       = 每轮独立文件
```

### 4.2 动态 QPN

```text
Worker0 local QPN = 0x0000a0
Worker1 local QPN = 0x0000a0
两侧 QP state     = RTS
两侧 SQ/RQ PSN    = 100
```

完整 VIO 配置已通过脚本写入并逐字段读回：

```text
VIO_APPLY_PASS worker0_qpn=0x0000a0 worker1_qpn=0x0000a0
```

### 4.3 第 0 轮

释放：

```text
/tmp/codex_mr0_20260730.0
/tmp/codex_mr1_20260730.0
```

结果：

```text
Worker0:
send_posted=1 iter=0
status=transport retry counter exceeded
send_success=0 recv_success=0 iterations_done=0

Worker1:
send_posted=1 iter=0
status=transport retry counter exceeded
send_success=0 recv_success=0 iterations_done=0
```

两侧均没有 Receive CQE，也没有成功的 Send CQE。

### 4.4 第 1 轮

未释放。第 0 轮失败后停止继续 gate，避免把缺失 fan-in 引发的连锁错误混入根因。

### 4.5 端口计数增量

| 计数增量 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | 0 | 0 |
| `tx_vport_rdma_unicast_packets` | +12 | +14 |
| `tx_packets_phy` | +441 | +24 |
| `rx_packets_phy` | +177 | +483 |
| `rx_crc_errors_phy` | 0 | +58 |
| `rx_bytes_phy` | +29922 | +61362 |
| `rx_1024_to_1518_bytes_phy` | 0 | +25 |

`tx_vport_rdma_unicast_packets` 的增加与两侧 RC retry 一致。P1 在测试窗口内新增 58 个 CRC 错误，证明它不是单纯的历史累计值。

### 4.6 问题、定位与处理

#### 问题 1：第 0 轮没有产生任何 Receive CQE

已排除：

- 两个 QP 均进入 RTS；
- 静态 neighbor 正确；
- FPGA/Worker MAC、IP、UDP、QPN、root、child mask 的 VIO 读回正确；
- 两侧都执行了 `post_send()`。

尚不能区分：

- FPGA 内部保留了此前失败测试的 arrival/slot/ACK 状态；
- FPGA 没有形成合法聚合输出；
- P1 物理接收错误破坏了 FPGA 返回报文；
- 返回报文的 PSN/ICRC/ACK 状态不符合当前 QP。

#### 定位动作

下一次测试保持 RTL、bitstream、payload 和两 Worker 拓扑不变，只重新烧录同一 bit/ltx 以清空 FPGA 状态。链路恢复后创建新 QP、重新写入动态 QPN，再执行 2 轮。

如果重新烧录后第 0 轮恢复，说明残留 FPGA 状态是重要变量；如果仍失败，则进一步使用 ILA 对 parser hit、logical ingress、fan-in、广播和 ACK 分层定位。

## 5. 后续测试

## 5. 第二次受控测试：重新烧录后 2 轮

状态：两轮完整通过。

### 5.1 与第一次测试的单变量差异

- 使用相同 RTL、bitstream、ltx、MAC/IP/UDP、payload 和两 Worker 拓扑；
- 重新烧录同一 bit/ltx，清空 FPGA 内部状态；
- 新建 QP；
- 初始 PSN 从 100 改为已验证基线 0。

烧录结果：

```text
CODEX22_PROGRAM_PAIR_PASS
VIO_PORT_ENABLE=b
```

动态连接：

```text
Worker0 QPN = 0x0000a1
Worker1 QPN = 0x0000a1
两侧 QP     = RTS
SQ/RQ PSN   = 0
```

VIO：

```text
VIO_APPLY_PASS worker0_qpn=0x0000a1 worker1_qpn=0x0000a1
```

### 5.2 第 0 轮结果

两侧均成功：

```text
Receive CQE status=success byte_len=1024
payload first16=05050505050505050505050505050505
byte_sum=5120
all_same=1 value=0x05
Send CQE status=success
```

完成后两侧都等待 `.1`。

### 5.3 第 1 轮结果

两侧再次成功：

```text
Receive CQE status=success byte_len=1024
payload first16=05050505050505050505050505050505
byte_sum=5120
all_same=1 value=0x05
Send CQE status=success
```

汇总：

```text
Worker0: completions=4 send_success=2 recv_success=2 iterations_done=2
Worker1: completions=4 send_success=2 recv_success=2 iterations_done=2
```

这证明同一个 RC QP 内至少可以完成 PSN 0→1 的连续两轮状态推进。

### 5.4 两轮端口计数增量

| 计数增量 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | +4 | +4 |
| `tx_vport_rdma_unicast_packets` | +4 | +4 |
| `tx_packets_phy` | +230 | +4 |
| `rx_packets_phy` | +94 | +245 |
| `rx_crc_errors_phy` | 0 | +30 |
| `rx_bytes_phy` | +17058 | +21492 |
| `rx_1024_to_1518_bytes_phy` | +2 | +2 |

P1 在成功完成两轮期间仍新增 30 个 CRC 错误。说明功能路径可以工作，但 P1 物理接收质量存在独立风险。

### 5.5 阶段结论

第一次测试失败、重新烧录后两轮成功，说明 FPGA 内部残留状态是实验可重复性的关键变量。当前测试流程应在新的独立基线实验前重新烧录或提供等价的、已验证能清空 arrival/slot/ACK 状态的全局复位。

## 6. 第三次受控测试：重新烧录后 5 轮

状态：第 0、1 轮两侧成功；第 2 轮 Worker0 成功、Worker1 失败；停止第 3、4 轮。

仅在同一个 QP 内，按 `.0` 到 `.4` 逐轮释放 gate。任一侧失败后立即停止后续轮次。

### 6.1 动态连接

```text
Worker0 QPN = 0x0000a2
Worker1 QPN = 0x0000a2
两侧 QP     = RTS
初始 PSN    = 0
VIO_APPLY_PASS worker0_qpn=0x0000a2 worker1_qpn=0x0000a2
```

### 6.2 第 0 轮

两侧均成功：

```text
Receive CQE success, 1024B × 0x05
Send CQE success
```

### 6.3 第 1 轮

两侧均成功：

```text
Receive CQE success, 1024B × 0x05
Send CQE success
```

### 6.4 第 2 轮首次分叉

Worker0：

```text
send_posted=3 iter=2
Receive CQE status=success byte_len=1024
payload all_same=1 value=0x05
Send CQE status=success
等待 gate .3
QP rq-psn=3 sq-psn=3 state=RTS
```

Worker1：

```text
send_posted=3 iter=2
status=transport retry counter exceeded
send_success=2
recv_success=2
iterations_done=2
进程退出
```

第 3、4 轮未释放。

### 6.5 端口计数增量

从五轮测试启动前到第 2 轮失败：

| 计数增量 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | +6 | +4 |
| `tx_vport_rdma_unicast_packets` | +6 | +17 |
| `tx_packets_phy` | +300 | +26 |
| `rx_packets_phy` | +117 | +330 |
| `rx_crc_errors_phy` | 0 | +40 |
| `rx_bytes_phy` | +21659 | +39604 |
| `rx_1024_to_1518_bytes_phy` | +3 | +14 |

### 6.6 首个分叉点定位

Worker0 在第 2 轮收到正确的 `0x05`，证明：

1. Worker0 第 2 轮 `SEND_ONLY` 到达 FPGA；
2. Worker1 第 2 轮 `SEND_ONLY` 也到达 FPGA，否则无法得到 `0x02 + 0x03 = 0x05`；
3. parser、connection table、logical ingress 0/1、同 PSN fan-in 和聚合核心完成；
4. root 广播至少在 P0 路径生成了合法、可被 RNIC 接收的报文；
5. P0 ACK/CQ 闭环完成。

Worker1 同轮没有 Receive CQE，且 P1 同时出现：

```text
rx_crc_errors_phy +40
rx_1024_to_1518_bytes_phy +14
```

因此当前首要问题收敛为：

```text
FPGA P1 egress / 光模块或线缆 / RNIC P1 receive physical path
```

不是当前主要嫌疑：

```text
Worker1 ingress
parser/table hit
fan-in
1024B 聚合计算
PSN=2 的聚合槽位
```

如果只是 BTH QPN、PSN 或 ICRC 错误，RNIC 可以拒绝 RDMA 报文，但不应持续增加以太网/物理层 CRC 错误。P1 `rx_crc_errors_phy` 在空闲和测试窗口都持续增长，使物理发送/接收质量成为最高优先级。

### 6.7 下一步定位

读取两个网卡的：

```text
FEC mode
lane/symbol/CRC/FEC counters
link mode
```

并读取 FPGA 全局 VIO/CMAC 状态，对比 P0 和 P1。后续检查表明两个 CMAC
均关闭 RS-FEC，两个 RNIC 的 Active FEC 也均为 Off；PCS/lane error 为 0。
因此没有发现 P0/P1 FEC 配置不一致。

## 7. 第四次受控测试：原 RTL 的 5 轮复测

状态：前 4 轮完整闭环；第 5 轮两侧 Receive 成功，但两侧 Send ACK 超时。

### 7.1 配置

```text
重新烧录原 bit/ltx
Worker0/1 QPN = 0x0000a3
SQ/RQ PSN     = 0
iterations    = 5
VIO_APPLY_PASS
```

### 7.2 结果

PSN 0～3 两侧均得到：

```text
Receive CQE success, byte_len=1024
payload all_same=1 value=0x05
Send CQE success
```

PSN 4 两侧均得到正确 Receive CQE 和 `0x05`，但原始 Send WQE 最终为：

```text
status=transport retry counter exceeded
recv_success=5
send_success=4
iterations_done=4
```

这证明第 5 次 parser、connection table、fan-in、聚合、广播、per-port
rewrite、ICRC 和 RNIC Receive WQE 都已成功。失败发生在聚合包被 RNIC
接收之后的 ACK 闭环。

端口计数增量：

| 计数增量 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | +11 | +9 |
| `tx_vport_rdma_unicast_packets` | +21 | +19 |
| `rx_crc_errors_phy` | 0 | +17 |
| `rx_1024_to_1518_bytes_phy` | +16 | +14 |

P1 CRC 仍有增长，但两侧在同一轮同时缺少 Send CQE，因此不能再把主因只归结为
P1 物理链路。

## 8. 第五次受控测试：排除固定 PSN/末轮边界

目的：使用 `N=6`，只释放 PSN 0～4，区分以下两种假设：

1. FPGA 固定在 PSN=4 或第 5 次 ACK 失效；
2. Worker 在最后一次迭代的收尾流程有问题。

配置：

```text
重新烧录同一原 bit/ltx
Worker0/1 QPN = 0x0000a4
SQ/RQ PSN     = 0
iterations    = 6
VIO_APPLY_PASS
```

结果：

```text
PSN 0：两侧 Receive/Send CQE 成功
PSN 1：两侧 Receive CQE 成功，payload=0x05
       Worker1 Send CQE 成功并等待 PSN 2
       Worker0 Send ACK 超时
```

结论：

- ACK 丢失不是固定在 PSN=4；
- 不是 Worker 最后一轮退出引起；
- 可以随机表现为单端失败；
- P0 本轮 CRC 增量为 0，因此 P1 CRC 不是 ACK 丢失的充分解释；
- 聚合和返回数据接收仍成功，首个失败点是 FPGA 收取并反射 RNIC ACK。

## 9. RTL 根因定位

涉及文件：

```text
imports/src/allreduce/Typer.v
imports/src/allreduce/aggregator_core_top.v
imports/src/allreduce/deparser.v
```

### 9.1 正确存在但未闭合的反压链

`Typer.v` 已实现：

```verilog
s2_stalled_by_dep = to_deparser_valid && !to_deparser_ready;
stall             = s2_valid && s2_stalled_by_dep;
in_ready          = !stall;
```

实例中 `in_ready` 接到：

```verilog
typer_to_parser_ready
```

但全工程搜索确认，该信号此前只有声明和端口连接，没有被
`parser_out_ready` 使用。

### 9.2 实际丢 ACK 的条件

aggregator 到 deparser 之间是 1 深度 pipe + 1 深度 skid：

```verilog
pipe_push = !pipe_valid && skid_src_valid;
```

原 `parser_out_ready`：

```verilog
assign parser_out_ready =
    data_up   ? up_ready :
    data_down ? down_ready :
    1'b1;
```

ACK 命中最后的常量 `1'b1`。当第一个 ACK 尚占用 Typer/pipe/skid/deparser
时，第二个 Worker 几乎同时返回的 ACK 仍被 parser 当作已接收；但
`pipe_push=0`，请求无法进入下游，从而丢失。表现正是：

```text
Receive CQE 正确
一个或两个 Worker 的 Send CQE 随机超时
失败端口和失败 PSN不固定
```

现有行为仿真原先只覆盖离散 ACK 和单个 ACK 输出反压，没有覆盖两个端口
ACK 在下游繁忙时连续到达，所以没有暴露该握手断点。

## 10. 最小 RTL 修复

仅修改：

```text
imports/src/allreduce/aggregator_core_top.v
```

补丁：

```diff
-        1'b1;
+        typer_to_parser_ready;
```

作用：

- ACK 下游忙时，parser 正确暂停；
- Typer 保持当前有效 ACK，直到 pipe 可以接收；
- 后续 ACK 不再覆盖或越过被阻塞请求；
- 数据上行、数据下行、聚合、广播、rewrite 和外围 CMAC逻辑均未修改。

修复前后 SHA256：

```text
before = 4a46d585e2cfcda238048163ff18355d7320ff5e32f13ecba52e1ae5a8b64c61
after  = a533434bcc1066736f07734910dfa0807f1363e788075822b77322559a645442
```

服务器原文件备份：

```text
/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/multiround_20260730/
rtl_fix_ack_backpressure/aggregator_core_top.v.before
```

## 11. 修复后行为仿真与构建

### 11.1 行为仿真

执行现有 Phase7 全路径回归：

```text
scripts/run_phase7_behavioral.tcl
```

结果：

```text
PHASE7_TEST_PASS
```

覆盖了：

- 两个 Worker SEND_ONLY；
- 1024B fan-in 聚合；
- root 双端广播；
- Port0 ACK；
- Port1 ACK + 输出反压；
- 六字段负向过滤。

### 11.2 综合、实现和 bitstream

使用 Vivado 内置 `Flow_RuntimeOptimized`，完整重跑 synth/impl，不使用增量
checkpoint，不进行手工 RTL、placement 或时序调优。

```text
MINIMAL_BUILD_PASS
route_design completed successfully
write_bitstream completed successfully
DRC: 0 Errors
```

最终时序仅记录，不作为本轮功能测试阻塞条件：

```text
WNS = -5.686 ns
TNS = -101405.891 ns
WHS =  0.009 ns
THS =  0.000 ns
```

最终文件：

```text
bit size = 58549307
bit sha256 = baeb25978b867aacb38f14d91fd0010dc83442b79bf6f692d6773bd09965a817

ltx size = 209830
ltx sha256 = 8dbc21ac985e65b8fc53bcdba7ce8c899e71585972e52e0328a596fa42bd7c54
```

## 12. 第六次受控测试：修复后 10 轮

配置：

```text
新 bit/ltx 已烧录
Worker0/1 QPN = 0x0000a5
SQ/RQ PSN     = 0
iterations    = 10
Worker0       = 1024B × 0x02
Worker1       = 1024B × 0x03
VIO_APPLY_PASS
```

结果：PSN 0～9 全部完整闭环。

每个 Worker：

```text
10 × Receive CQE success
10 × payload first16=05050505050505050505050505050505
10 × byte_sum=5120
10 × all_same=1 value=0x05
10 × Send CQE success
cq_summary completions=20 send_success=10 recv_success=10 iterations_done=10
```

计数器增量：

| 计数增量 | Worker0/P0 | Worker1/P1 |
|---|---:|---:|
| `rx_vport_rdma_unicast_packets` | +20 | +20 |
| `tx_vport_rdma_unicast_packets` | +20 | +20 |
| `tx_packets_phy` | +80 | +20 |
| `rx_packets_phy` | +66 | +126 |
| `rx_crc_errors_phy` | 0 | 0 |
| `rx_bytes_phy` | +19117 | +22957 |
| `rx_1024_to_1518_bytes_phy` | +10 | +10 |

最终状态：

```text
TEST6_STATUS=PASS
无残留 worker_rdma_qp 进程
```

服务器证据目录：

```text
/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/multiround_20260730/
test6_fixed_ack_10round/
```

## 13. 最终结论与后续测试原则

### 已解决

当前工程已在真实两个 RoCEv2 RC QP 下完成连续 10 轮：

```text
post_recv
→ 双 Worker post_send
→ FPGA ingress 0/1
→ parser/table hit
→ 同 PSN 1024B fan-in 聚合
→ root 双端广播
→ per-port rewrite + checksum/ICRC
→ 两侧 Receive CQE
→ 两侧 RNIC ACK
→ FPGA ACK 反射
→ 两侧 Send CQE
→ PSN+1
```

最开始的多轮随机失败不是聚合数学逻辑错误，也不是固定 QPN/PSN边界，而是
ACK ready/valid 反压链未闭合。修复后 10 轮闭环以及对称计数器增量直接验证了
问题定位和修改的正确性。

### 仍需保留的风险

1. 最终实现存在严重 setup 时序违例，当前只能说明本次板卡、温度和运行条件下
   完成了功能验证，不能据此宣称跨板卡/温度/电压稳定。
2. P1 在修复前部分测试中出现 CRC 增长，但修复后 10 轮 CRC 增量为 0。
   后续长流量测试仍应持续监控 P1 CRC。
3. 每次重新创建 QP 后必须把实际动态 QPN重新写入 VIO并读回；旧 QPN只属于
   已退出的进程。
4. 独立基线测试前重新烧录可清除 arrival/slot/ACK 历史状态；当全局复位逻辑
   被单独验证后，才可用复位替代烧录。

### 推荐的回归顺序

```text
1. 检查 RDMA link、静态邻居、MAC/IP/UDP
2. 重新烧录或执行已验证全局复位
3. 启动两个 gate 阻塞的 Worker
4. 获取动态 QPN
5. 完整写入并读回 VIO
6. 每轮同时释放两个 gate
7. 检查 payload、Receive CQE、Send CQE
8. 比较测试前后 RDMA/CRC/包长计数器
9. 任一侧失败立即停止后续轮次，保存首个分叉证据
```
