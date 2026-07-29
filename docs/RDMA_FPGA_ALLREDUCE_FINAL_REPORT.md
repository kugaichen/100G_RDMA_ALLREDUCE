# RDMA-FPGA AllReduce 最终实现与测试报告

日期：2026-07-27  
工程：`/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj`  
服务器连接：Tailscale `100.67.118.50`，用户 `ubuntu`  
FPGA：Xilinx `xcvu13p`，hw_server `TCP:127.0.0.1:3121`

## 1. 本次目标与停止条件

本阶段目标是完成一次最小闭环硬件验证：

1. Worker0/Worker1 各 `post_recv(1024B)`；
2. 各通过 RC QP `ibv_post_send()` 发送一次 1024B `SEND_ONLY`；
3. FPGA 两个物理端口分别接收、解析、聚合并广播；
4. Worker 收到聚合报文并产生 Receive CQE；
5. Worker 自动返回 ACK，FPGA 反射 ACK；
6. 原始 Send WQE 产生 Send CQE。

按用户要求，本报告对应**唯一一轮**最终上板测试；无论成功或失败，测试后停止，不继续重试，不再进行 RTL 时序/布局手动优化。

## 2. 固定网络与协议配置

| 节点 | MAC | IP | 端口/QPN |
|---|---|---|---|
| FPGA | `02:00:00:00:03:07` | `192.168.3.7` | UDP `4791`，固定 QPN `0x000100` |
| Worker0 / P0 | `6c:b3:11:88:ab:3e` | `192.168.3.5/24` | `mlx5_0` / `enp193s0f0np0` |
| Worker1 / P1 | `6c:b3:11:88:a9:4e` | `192.168.3.6/24` | `mlx5_2` / `enp129s0f0np0` |

最终测试动态 QPN：

- Worker0：十进制 `171`，十六进制 `0x0000ab`；
- Worker1：十进制 `165`，十六进制 `0x0000a5`。

## 3. RTL 与软件修改

### 3.1 已完成 RTL 修改

1. `parser.v`
   - 在 PB_IDLE→PB_PROCESS 路径保存 `shifter_fifo_lout <= fifo_lout`；
   - 目的：保留单拍 ACK 的最后一拍/tlast，避免 ACK 解析丢失。

2. `deparser.v`
   - 单拍 ACK 在 `GEN_HEADER` 状态产生 `in_agg_ready`；
   - 目的：允许 ACK 构造路径正确完成握手。

3. `aggregator_core_top.v`
   - 修改 `grant_buffer` 与 `grant_up_broadcast` 仲裁；
   - root 聚合完成后的上行广播优先于同 PSN 的 per-port 重传请求，避免 RNIC 重发 SEND_ONLY 持续占用仲裁而饿死 root 广播。
   - 修改位置约为 1642–1653 行，核心逻辑：

```systemverilog
wire grant_buffer = !(req_ack_up || req_ack_down) &&
    (req_down_down_broadcast ||
     (!req_up_root_down_broadcast && req_up_port_retrans));

wire grant_up_broadcast = !(req_ack_up || req_ack_down) && !req_down_down_broadcast &&
    (req_up_root_down_broadcast ||
     (!req_up_port_retrans &&
      (req_up_noroot_FAN_retrans || req_up_noroot_FAN_trans)));
```

该修改没有改变外围 MAC/IP/UDP 配置，也没有进行时序、布局或 RTL 结构重构。

### 3.2 Worker 软件测试程序

`/home/ubuntu/cyf/NSDI27/worker_rdma_qp/worker_rdma_qp.c` 已支持：

- 动态创建 RC QP 并打印 local QPN；
- `-W` 门控等待；
- `-N 1` 单次发送；
- `-B 0xff/0x00` 固定 payload；
- 记录 Send/Receive CQE、状态码、payload 首字节和统计信息。

最终测试脚本：

- `scripts/run_final_one_round_codex27.sh`
- `scripts/hw_ila_final_one_round_codex27.tcl`

## 4. 仿真与实现阶段证据

### 4.1 行为级仿真

- `logs/codex26_phase7.log`：`PHASE7_TEST_PASS`；
- `logs/codex26_icrc.log`：`2 PASS, 0 FAIL`，`ALL TESTS PASSED`；
- 覆盖 1024B、Worker0 全 `0xff`、Worker1 全 `0x00`、ACK 处理及 ICRC 相关检查。

### 4.2 Vivado 构建

- 曾尝试的 `RuntimeOptimized` 策略不被 Vivado 2025.2 支持，已停止使用；
- 曾有一轮实现进程被系统 `Killed`，属于资源/系统压力，不是 RTL 语法错误；
- 最终采用 Vivado 内置 `Flow_Quick`，路由 directive 为 `Quick`，未进行手动时序/布局调优；
- 综合完成；布局完成；DRC：`0 Errors`；
- `write_bitstream` 成功。

最终产物：

```text
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx
```

## 5. 最终唯一一轮硬件测试

### 5.1 烧录

使用 `scripts/hw_program_pair_codex22.tcl` 下载 bit/LTX，结果：

```text
CODEX22_PROGRAM_PAIR_PASS
Device xcvu13p programmed with 1 ILA and 2 VIO cores
```

### 5.2 VIO

由 `scripts/apply_allreduce_vio.tcl` 动态写入：

```text
VIO_APPLY_PASS worker0_qpn=0x0000ab worker1_qpn=0x0000a5
VIO_OK ar_cfg_worker0_qp 0xab
VIO_OK ar_cfg_worker1_qp 0xa5
```

其它配置保持实验固定值：root=1、child mask=3、FPGA IP/MAC、Worker IP/MAC、UDP=4791、FPGA QPN=0x100。

### 5.3 Worker 结果

Worker0：

```text
qp_state=3 (3=RTS)
local_qpn=171 (0x0000ab)
send_length=1024
payload_byte=0xff
send_posted=1 iter=0
cq_completion=1 ... status=transport retry counter exceeded(12)
cq_summary completions=0 send_success=0 recv_success=0 iterations_done=0
```

Worker1：

```text
qp_state=3 (3=RTS)
local_qpn=165 (0x0000a5)
send_length=1024
payload_byte=0x00
send_posted=1 iter=0
cq_completion=1 ... status=transport retry counter exceeded(12)
cq_summary completions=0 send_success=0 recv_success=0 iterations_done=0
```

两个 QP 均成功进入 RTS，说明网卡、GID、远端 FPGA QPN 和 VIO QPN 配置过程完成；但发送后未收到合法 ACK/响应，最终触发 RC retry counter exceeded。未产生成功 Send CQE，也未产生成功 Receive CQE。

### 5.4 ILA 结果

ILA 使用 `ila_dep_agg_req_valid` 作为触发条件，已成功布防：

```text
FINAL_ILA_ARMED
```

本轮未出现 `FINAL_ILA_TRIGGERED`，没有生成有效聚合请求 CSV。因此当前硬件证据只能确认：Worker QP 建立、一次 SEND WQE 提交、FPGA 未被 ILA 观测到完整聚合请求/广播闭环。

## 6. 最终结论

### 已解决

- 工程可完成综合、布局、Quick 路由和 bitstream 写出；
- DRC 无错误；
- VIO 可动态写入真实 Worker QPN；
- 两个 Worker RC QP 均能进入 RTS；
- 两个 Worker 均完成一次 1024B `SEND_ONLY` WQE 提交；
- parser/deparser 单拍 ACK 路径和 root 广播仲裁已完成对应 RTL 修复；
- 行为级仿真和 ICRC 测试通过。

### 未解决

- 本轮实际 FPGA 上未形成“两个入口同时聚合→root 广播→Worker Receive CQE→ACK 反射→Send CQE”的闭环；
- 两个 Worker 均以 `transport retry counter exceeded(12)` 失败；
- ILA 未捕获 `ila_dep_agg_req_valid`；
- 因此不能声称当前 bitstream 已完成 RDMA 连接下的 AllReduce 单包聚合。

### 失败定位边界

目前可以排除：

- Worker 网卡链路未建立；
- QP 未进入 RTS；
- QPN 未写入 VIO；
- bitstream 未成功烧录；
- Vivado DRC/生成阶段失败。

当前故障仍位于 FPGA 实际数据通路中的一个或多个环节：报文进入后的 endpoint/connection-table 命中、ingress_port/metadata、双端口 fan-in、root 广播、deparser rewrite/ICRC，或 ACK 生成/反射。由于本次按要求只进行一轮并停止，没有继续增加探针或修改逻辑。

## 7. 本轮生成/保留的关键日志

```text
logs/codex26_phase7.log
logs/codex26_icrc.log
logs/codex27_fast_build.log
logs/final_program.log
logs/final_one_round/qpn.txt
logs/final_one_round/vio.out
logs/final_one_round/ila.out
logs/final_one_round/worker0.log
logs/final_one_round/worker1.log
logs/final_one_round/rdma_qp.txt
```

## 8. 后续工作建议（不属于本次执行）

若继续排查，建议只增加观测，不先做时序优化：

1. 用 ILA 同时观察 `ila_ingress_port`、parser endpoint/hash hit、`ila_agg_fire_payload_en`、`ila_dep_agg_req_valid`、`ila_m_axis_tvalid/tlast`、`ila_m_axis_route_type`；
2. 确认 Worker0→P0、Worker1→P1 的端口映射和 connection-table 命中；
3. 确认双 fan-in 是否在同一 PSN 到齐；
4. 确认 root 广播是否产生 route_type=3 以及两个 per-port 输出；
5. 最后再检查 RNIC ACK 是否进入 FPGA 的 ACK_UP 路径。

本报告完成后不再自动执行新的烧录、发包或 RTL 修改。
