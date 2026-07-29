# Best Version 实现与测试报告

更新时间：2026-07-29  
服务器工程：`/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj`

## 1. 目标

以 `pre_codex23_clean_impl` 已验证的稳定物理收发为参考，保留当前必要的 parser、ingress、ICRC 和 ACK 修复，仅将固定双 Worker 的 connection table 改为确定性匹配，验证以下 1024B 双 Worker RDMA AllReduce 闭环：

```text
Worker0/1 post_recv
→ Worker0/1 post_send 1024B SEND_ONLY
→ FPGA parser connection hit
→ metadata(root=1, ingress=0/1, PSN=N)
→ 双输入聚合并广播到 P0/P1
→ Worker Receive CQE
→ Worker RNIC ACK
→ FPGA ACK 反射
→ Worker Send CQE
```

本轮遵循最小改动原则：不做额外时序优化、不改外围逻辑、不重构聚合器。

## 2. 修改前基线

### 2.1 修改前最新 bitstream

- P0/P1 link up；
- `port_error_status=0xD`；
- RNIC 物理 TX 增长，但 parser `s3_valid` 未触发；
- 两个 Worker 均为 `transport retry counter exceeded`。

### 2.2 `pre_codex23_clean_impl`

- P0/P1 link up；
- 初始 `port_error_status=0`，测试后仅未使用 P2 为 `0x4`；
- FPGA ILA 捕获 `m_axis_tvalid=1`；
- Worker1 物理 RX 增加 1 packet / 1086 bytes；
- ILA 显示：

```text
ingress_port=1
route_type=0
agg_fire_payload_en=0
dep_agg_req_valid=0
```

结论：外围接收和输出通路工作，但报文未命中 AllReduce connection，仅按 passthrough 输出，RNIC 没有产生 Receive/Send CQE。

## 3. 本轮代码修改

### 3.1 修改文件

```text
100G_4port_allreduce_proj.srcs/sources_1/imports/src/allreduce/hash_connection_table.v
```

### 3.2 修改内容

- 保持模块接口不变；
- 保持原两级 lookup 时序；
- 用两个确定键直接匹配 Worker0、Worker1；
- Worker0 返回 `{root=1, ingress_port=0}`；
- Worker1 返回 `{root=1, ingress_port=1}`；
- 其他 key 返回 `lookup_hit=0`；
- 保留写接口以兼容现有实例，但固定实验版本不使用运行时写表。

固定连接：

| 节点 | MAC | IP | table value |
|---|---|---|---|
| FPGA | `02:00:00:00:03:07` | `192.168.3.7` | 目的端 |
| Worker0 | `6c:b3:11:88:ab:3e` | `192.168.3.5` | `root=1, ingress=0` |
| Worker1 | `6c:b3:11:88:a9:4e` | `192.168.3.6` | `root=1, ingress=1` |

服务器备份：

```text
hash_connection_table.v.pre_best_cam_20260729
```

### 3.3 明确未修改

- `aggregator_core_top.v`
- `parser.v`
- `allreduce_offload_top.v`
- `deparser.v`
- `icrc_calc.v`
- CMAC、adapter、CDC、input/output arbiter
- VIO 字段和 Worker 软件协议

## 4. 测试记录

### 4.1 Phase 7 完整行为仿真

命令入口：

```text
scripts/run_phase7_behavioral.tcl
```

日志：

```text
logs/best_cam_phase7.log
```

结果：

```text
PHASE7_TEST_PASS
```

关键证据：

- Worker0：`hit=1 root=1 ingress=0`；
- Worker1：`hit=1 root=1 ingress=1`；
- 两个 fan-in 到齐后触发聚合广播；
- P0、P1 均输出 17 beat 的 1024B payload 报文；
- P0/P1 ACK 用例均触发 `ack_build_en` 并返回对应端口；
- 六项负向过滤用例全部通过。

说明：仿真中内部 `route_type=4`，实际端口掩码为 P0+P1；本轮以两个目标端口均产生完整输出包作为广播判据。

### 4.2 ICRC 行为仿真

命令入口：

```text
scripts/run_icrc_behavioral.tcl
```

日志：

```text
logs/best_cam_icrc.log
```

结果：

```text
ACK ICRC PASS
SEND ICRC PASS
2 PASS, 0 FAIL
ALL TESTS PASSED
```

注意：ICRC 仿真载入了旧波形配置，因此出现“波形对象不存在”警告；它只影响 GUI 波形列表，不影响当前 testbench 的编译、运行和 PASS 判定。

## 5. 当前结论

固定连接表、parser、aggregator、deparser、per-port rewrite 和 ICRC 已在行为级形成双 Worker 数据与 ACK 路径。

当前还不能宣称 RDMA 硬件闭环成功，尚需完成：

- [ ] 综合与增量实现；
- [ ] 生成并烧录新的 bit/ltx；
- [ ] P0/P1 CMAC 状态检查；
- [ ] parser ILA 命中验证；
- [ ] 双输入聚合与 P0/P1 广播验证；
- [ ] Worker0/1 Receive CQE；
- [ ] ACK 反射与原始 Send CQE；
- [ ] PSN=N+1 连续推进。

## 6. 后续每轮记录格式

每轮继续记录：

- 使用的 bit/ltx 及时间戳；
- VIO 配置和动态 Worker QPN；
- Worker 启动参数；
- RNIC 端口计数器差值；
- ILA 触发条件与关键值；
- CQE 状态；
- 问题、定位依据、最小修改及复测结果；
- 已解决项和未解决项。

## 7. 综合与实现

### 7.1 构建方式

脚本：

```text
scripts/run_best_incremental_build.tcl
```

策略：

```text
synth_1: Flow_RuntimeOptimized
impl_1:  Flow_RuntimeOptimized
```

脚本设置 `logs/minimal_impl.dcp` 为增量参考，但 Vivado 最终报告：

```text
Incremental flow is disabled.
```

因此本轮实际按 RuntimeOptimized 完整实现，不能声称复用了旧布局。

### 7.2 构建结果

```text
BEST_CAM_BUILD_PASS
Synthesis: 0 errors, 0 critical warnings
Route: Router Completed Successfully
write_bitstream completed successfully
```

最终时序：

```text
WNS = -3.225 ns
TNS = -40576.656 ns
WHS = +0.006 ns
THS = 0 ns
```

说明：

- setup timing 未满足；
- hold timing 满足；
- 按本轮“先做功能上板、不做手工时序或布局调优”的要求继续生成并测试 bitstream；
- 该时序结果是后续稳定性风险，不能作为量产或长期运行签核。

输出：

```text
100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit
100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx
logs/best_cam_impl.dcp
logs/best_cam_timing_summary.rpt
logs/best_cam_utilization.rpt
```

SHA256：

```text
bit  4eb84529b795467c99683992884d663598fc3e27a304166df30882a5f397a9d9
ltx  8dbc21ac985e65b8fc53bcdba7ce8c899e71585972e52e0328a596fa42bd7c54
RTL  e8efcbfc27f5b358b51f41b9e7e9433759e16cf9dc5b9a233f6cae9464ce0e51
```

## 8. 上板测试

### 8.1 烧录和基础状态

烧录结果：

```text
CODEX22_PROGRAM_PAIR_PASS
VIO_PORT_ENABLE=0xb
```

链路与错误状态：

```text
FPGA port_link_status=0xb
FPGA port_error_status=0
FPGA any_error=0
mlx5_0 ACTIVE / LINK_UP
mlx5_2 ACTIVE / LINK_UP
```

服务器网络：

```text
Worker0 enp193s0f0np0 = 192.168.3.5/24
Worker1 enp129s0f0np0 = 192.168.3.6/24
192.168.3.7 -> 02:00:00:00:03:07 为 PERMANENT 邻居
```

### 8.2 第一轮：Worker0 完整闭环，Worker1 失败

动态 QPN：

```text
Worker0 QPN = 0x000092
Worker1 QPN = 0x000092
FPGA QPN    = 0x000100
```

VIO 所有固定字段和两个动态 QPN 均读回一致。

FPGA ILA：

```text
CODEX16_ILA_TRIGGERED round=0
agg_fire_payload_en=1
route_type=4
m_axis_tvalid 共 17 beat
m_axis_tlast 在最后一拍有效
payload=0xff
```

Worker0：

```text
Receive CQE success, byte_len=1024
recv payload 全 0xff
Send CQE success
```

Worker1：

```text
transport retry counter exceeded
没有 Receive CQE
```

结论：双输入已进入真实硬件聚合，聚合结果已成功到达 Worker0；失败范围收敛到 P1 返回路径或 Worker1 对返回帧的接收。

### 8.3 P1 失败定位

带网卡物理计数器的受控复测显示：

```text
Worker0 rx_crc_errors_phy delta = 0
Worker1 rx_crc_errors_phy delta = +8
Worker1 rx_symbol_err_phy delta = +8
```

两张网卡均有物理 RX 增量，因此不是“FPGA 完全没有向 P1 发包”。Worker1 的错误发生在以太网/PCS 层，早于 RoCE QP 和 CQ 处理。

停止 Worker 后错误仍继续增长，是因为 FPGA 中未 ACK 的聚合结果仍处于重传状态；只停止软件进程不能清除 FPGA 内部状态。

重新烧录同一 bitstream 清空 FPGA 状态后，10 秒无 Worker 基线：

```text
rx_crc_errors_phy delta = 0
rx_symbol_err_phy delta = 0
```

说明链路静止时不持续误码，错误与 FPGA P1 返回流量/重传同时出现。

### 8.4 最终复测：双 Worker 两轮完整闭环成功

重新烧录同一 bitstream 清状态后，不修改 RTL，重新创建 QP并动态配置 VIO。

动态 QPN：

```text
Worker0 QPN = 0x000094
Worker1 QPN = 0x000094
FPGA QPN    = 0x000100
```

ILA：

```text
CODEX16_ILA_TRIGGERED round=0
CODEX16_ILA_TRIGGERED round=1
```

Worker0：

```text
recv_success=2
send_success=2
iterations_done=2
两轮 recv byte_len=1024
两轮 payload 全 0xff
```

Worker1：

```text
recv_success=2
send_success=2
iterations_done=2
两轮 recv byte_len=1024
两轮 payload 全 0xff
```

最终判据：

```text
cq_summary completions=4 send_success=2 recv_success=2 iterations_done=2
CODEX21_RETRY_HARDWARE_PASS
```

成功轮结束后：

```text
FPGA port_error_status=0
FPGA any_error=0
```

## 9. 最终结论

### 9.1 已实现并验证

- 固定双 Worker connection table 在真实 RDMA 报文上命中；
- Worker0/Worker1 分别得到 `ingress=0/1`；
- FPGA 作为 root 完成两个 1024B fan-in；
- `0xff + 0x00` 的聚合 payload 为全 `0xff`；
- 聚合结果广播到两个 Worker；
- 两个 Worker 均产生 Receive CQE；
- 两个 Worker RNIC 均返回 ACK；
- FPGA ACK 路径使两侧原始 post_send 产生 Send CQE；
- PSN/迭代从 round 0 推进到 round 1；
- 双 Worker RDMA AllReduce 两轮硬件闭环已成功。

### 9.2 已知未解决风险

成功轮中 Worker1 仍出现：

```text
rx_crc_errors_phy delta = +6
rx_symbol_err_phy delta = +6
```

但同时有正确返回帧被接收，最终两轮 CQ 全成功。这说明 P1 链路存在间歇性帧损坏风险，可能与以下因素有关：

- P1 FPGA TX 到 RNIC RX 的物理链路/模块/线缆；
- FEC 当前为 Off；
- 当前实现严重 setup timing violation；
- P1 TX adapter/CMAC 边界在该布局下的稳定性。

本轮按要求不做时序、布局布线或外围 RTL 优化，因此该风险记录为未解决项。后续若追求连续稳定运行，应优先做 P1 误码隔离和时序签核，而不是再次改动已通过的 connection table/聚合功能逻辑。

## 10. 关键日志

```text
logs/best_cam_phase7.log
logs/best_cam_icrc.log
logs/best_cam_build.log
logs/best_cam_program.log
logs/best_cam_hw_run.stdout
logs/best_cam_one_round_diag/repeat_run.out
logs/best_cam_one_round_diag/
logs/codex21_retry_round0_ila.csv
logs/codex21_retry_round1_ila.csv
/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/codex_hw16/worker0.log
/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/codex_hw16/worker1.log
```

## 11. 2026-07-29 当前源码重新生成 bitstream 并完成硬件闭环

### 11.1 背景与问题

在 Vivado GUI 中误触并取消 Generate Bitstream 后，`synth_1` 和
`impl_1` 的当前输出被重置，原先位于 `.runs/impl_1` 的 `.bit/.ltx`
不再存在。服务器上仅剩：

```text
artifacts/pre_codex23_clean_impl/
```

该回退版本的硬件测试表明 FPGA 能完成聚合广播，但返回包存在：

```text
UDP src = 4791
UDP dst = Worker 动态 UDP 源端口
ICRC    = 0x00000000
```

例如 QPN `0x98` 测试中，返回包 UDP dst 为 `55298`。两个 Worker
均出现：

```text
transport retry counter exceeded
send_success=0
recv_success=0
```

这说明旧 bitstream 没有形成 RNIC 可消费的合法 RoCEv2 返回报文。

### 11.2 当前版本确认

当前综合明确使用：

```text
100G_4port_allreduce_proj.srcs/sources_1/new/per_port_rewriter.v
```

关键逻辑包括：

```verilog
tdata_out[295:288] = cfg_dst_port[15:8];
tdata_out[303:296] = cfg_dst_port[7:0];
```

以及当前 ICRC 初始化和尾部写入逻辑：

```verilog
localparam [31:0] CRC_INIT = 32'hDEBB20E3;
```

因此本轮重新生成的 bitstream 包含当前 UDP rewrite 和 ICRC 实现，
不是 2026-05-11 的旧 routed checkpoint。

### 11.3 Vivado 重建过程

构建过程中发现 GUI run 和 Codex batch run 同时执行同一个
`impl_1`，两个实现进程同时写入同一 run 目录。处理方式为：

1. 根据 PID、PPID 和 PGID 区分两棵进程树；
2. 保留更早启动的 GUI run（PGID `5193`）；
3. 终止重复 batch run（PGID `2696913`）；
4. 不修改 RTL、策略、时序约束或布局布线。

GUI run 使用当前综合 DCP继续完成实现。时序仍有违例，但按本阶段
“优先功能上板验证”的要求直接生成并烧录。

生成文件：

```text
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/
100G_4port_allreduce_proj.runs/impl_1/
qsfp28_100g_switch_4port_top.bit

/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/
100G_4port_allreduce_proj.runs/impl_1/
qsfp28_100g_switch_4port_top.ltx
```

生成时间：

```text
2026-07-29 14:19
```

烧录结果：

```text
CODEX22_PROGRAM_PAIR_PASS
VIO_PORT_ENABLE=b
```

### 11.4 本轮网络与 QP 配置

链路状态：

```text
mlx5_0/1 ACTIVE  netdev enp193s0f0np0
mlx5_2/1 ACTIVE  netdev enp129s0f0np0
```

静态邻居：

```text
192.168.3.7 lladdr 02:00:00:00:03:07 PERMANENT
```

新建 QP：

```text
Worker0 local QPN = 153 = 0x000099
Worker1 local QPN = 153 = 0x000099
FPGA remote QPN   = 256 = 0x000100
SQ PSN = 0
RQ PSN = 0
QP state = RTS
```

VIO 回读：

```text
FPGA IP/UDP/QPN    = 192.168.3.7 / 4791 / 0x000100
Worker0 IP/QPN     = 192.168.3.5 / 0x000099
Worker1 IP/QPN     = 192.168.3.6 / 0x000099
Worker0/1 UDP      = 4791
root               = 1
child_port_mask    = 3
VIO_APPLY_PASS
```

### 11.5 双 Worker 1024B RDMA 测试

输入：

```text
Worker0 post_recv(1024B)
Worker1 post_recv(1024B)
Worker0 post_send(1024B, payload=0xff)
Worker1 post_send(1024B, payload=0x00)
```

Worker0 结果：

```text
Receive CQE: status=success, byte_len=1024
payload first16=ffffffffffffffffffffffffffffffff
byte_sum=261120
all_same=1
value=0xff

Send CQE: status=success
cq_summary completions=2 send_success=1 recv_success=1 iterations_done=1
```

Worker1 结果：

```text
Receive CQE: status=success, byte_len=1024
payload first16=ffffffffffffffffffffffffffffffff
byte_sum=261120
all_same=1
value=0xff

Send CQE: status=success
cq_summary completions=2 send_success=1 recv_success=1 iterations_done=1
```

聚合结果符合：

```text
0xff + 0x00 = 0xff
```

### 11.6 闭环结论

本轮成功验证：

```text
Worker0/1 post_recv
→ Worker0/1 RC SEND_ONLY
→ FPGA P0/P1 接收
→ connection table / ingress metadata
→ 1024B 双 fan-in 聚合
→ root 广播到两个 Worker
→ per-port MAC/IP/QPN/UDP rewrite
→ IPv4 checksum 与 ICRC有效
→ 两个 Worker Receive CQE
→ Worker RNIC 自动 ACK
→ FPGA ACK路径
→ 两个原始 Send WQE产生 Send CQE
```

由于两个 RNIC 均成功产生 Receive CQE 和 Send CQE，可以确定返回包
已被 RoCE 硬件正确识别，UDP destination、目标 QPN、PSN 和 ICRC
满足本轮 RC 状态机要求。

### 11.7 Wireshark/dumpcap说明

成功测试的普通 `dumpcap` 文件中未出现 `192.168.3.7` 的 RoCE流量，
只包含 DHCP、mDNS、IPv6和广播包。这是因为合法 RoCE报文被 RNIC
硬件直接消费，通常不会进入 Linux packet socket。

此前错误 UDP destination 的 FPGA返回包未被 RNIC接管，因此反而能
被 Wireshark看到。判断闭环是否成功应优先依据：

```text
Receive CQE
Send CQE
payload内容
RNIC错误计数
FPGA ILA
```

而不能以普通 tcpdump/Wireshark是否能看到合法 RoCE包作为必要条件。

### 11.8 本轮证据路径

```text
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/
logs/current_hw_test_20260729/current_impl_qp99.pcapng

/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/udp_port_verify/
current_impl_worker0.log

/home/ubuntu/cyf/NSDI27/worker_rdma_qp/logs/udp_port_verify/
current_impl_worker1.log
```
