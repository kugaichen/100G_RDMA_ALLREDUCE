# 100G RDMA AllReduce FPGA

<img width="5044" height="1960" alt="image" src="https://github.com/user-attachments/assets/0a2c1f8a-e556-43dd-a63b-26cda415e7e0" />



本仓库保存 4×100G FPGA RoCEv2/RDMA AllReduce 工程的 RTL、Vivado IP
配置、约束、VIO/Hardware Manager 脚本、Worker 测试程序和实验报告。

当前硬件基线已经在两个真实 RoCEv2 RC QP 下完成连续 10 轮 1024B
AllReduce 闭环：

```text
Worker0/1 post_recv
→ Worker0/1 post_send(SEND_ONLY)
→ FPGA ingress 0/1
→ parser + connection table
→ 同 PSN、双端 fan-in 聚合
→ root 向 P0/P1 广播
→ per-port MAC/IP/QPN rewrite
→ IPv4 checksum + RoCEv2 ICRC
→ Worker0/1 Receive CQE
→ RNIC ACK
→ FPGA ACK 识别和反射
→ Worker0/1 Send CQE
→ PSN + 1
```

修复后验证结果：

```text
PSN 0～9 全部通过
每侧 recv_success=10
每侧 send_success=10
每侧 iterations_done=10
每轮接收 1024B × 0x05
测试期间 P0/P1 rx_crc_errors_phy 增量均为 0
```

## 1. 实验拓扑

```text
                    FPGA xcvu13p
              MAC 02:00:00:00:03:07
                   192.168.3.7
                  QPN 0x000100
                 UDP dst 4791
                       │
            ┌──────────┴──────────┐
            │                     │
       FPGA Port0            FPGA Port1
       ingress=0             ingress=1
            │                     │
            │ 100G 直连           │ 100G 直连
            │                     │
     Worker0 / mlx5_0       Worker1 / mlx5_2
     enp193s0f0np0          enp129s0f0np0
     192.168.3.5/24         192.168.3.6/24
```

| 角色 | RDMA 设备 | Linux netdev | MAC | IPv4 | FPGA逻辑入口 |
|---|---|---|---|---|---:|
| FPGA | — | — | `02:00:00:00:03:07` | `192.168.3.7` | — |
| Worker0 | `mlx5_0` | `enp193s0f0np0` | `6c:b3:11:88:ab:3e` | `192.168.3.5/24` | 0 |
| Worker1 | `mlx5_2` | `enp129s0f0np0` | `6c:b3:11:88:a9:4e` | `192.168.3.6/24` | 1 |

两个 RNIC 端口分别与 FPGA Port0、Port1 直接连接，不经过交换机。

## 2. 配置模型

### 2.1 固定实验配置

```text
FPGA MAC        = 02:00:00:00:03:07
FPGA IP         = 192.168.3.7
FPGA QPN        = 0x000100
RoCEv2 UDP port = 4791 (0x12B7)
root            = 1
child_port_mask = 0x3

Worker0 MAC     = 6c:b3:11:88:ab:3e
Worker0 IP      = 192.168.3.5
Worker0 ingress = 0

Worker1 MAC     = 6c:b3:11:88:a9:4e
Worker1 IP      = 192.168.3.6
Worker1 ingress = 1
```

固定字段保存在：

```text
configs/lab_2worker_vio.tcl
```

### 2.2 动态配置

Worker QPN 由 Linux RNIC 每次创建 QP 时动态分配。每次重新启动 Worker 后，
必须读取新的 Worker0/Worker1 QPN，再写入 FPGA VIO。

以下值不能沿用上一轮：

```text
ar_cfg_worker0_qp
ar_cfg_worker1_qp
```

即使两个 RNIC 本轮得到相同 QPN，也必须分别读取，不能假设它们始终相同。

### 2.3 当前报文准入条件

进入 AllReduce 路径的最小条件为：

```text
IPv4 protocol    = UDP
dst MAC          = FPGA MAC
dst IP           = FPGA IP
UDP dst port     = 4791
BTH dst QPN      = 0x000100
opcode           = SEND_ONLY (0x04)
connection table = hit
```

connection table 的 value 携带 root 信息和逻辑 ingress，Worker0/Worker1
分别映射为 ingress 0/1。

## 3. 当前服务器环境

服务器工程：

```text
/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
```

Worker 程序：

```text
/home/ubuntu/cyf/NSDI27/worker_rdma_qp
```

Vivado 2025.2：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
vivado -version
```

仓库与工程目录的主要映射：

| 仓库路径 | 服务器 Vivado工程路径 |
|---|---|
| `imports/` | `100G_4port_allreduce_proj.srcs/sources_1/imports/` |
| `new/` | `100G_4port_allreduce_proj.srcs/sources_1/new/` |
| `ip/` | `100G_4port_allreduce_proj.srcs/sources_1/ip/` |
| `constraints/timing_4port.xdc` | `100G_4port_allreduce_proj.srcs/constrs_1/imports/constrs/timing_4port.xdc` |
| `configs/` | `configs/` |
| `scripts/` | `scripts/` |
| `worker_rdma_qp/` | `/home/ubuntu/cyf/NSDI27/worker_rdma_qp/` |

仓库管理 RTL、XCI、约束、脚本和文档；Vivado生成的 `.runs`、`.cache`、
`.Xil`、DCP、bitstream、ILA数据和运行日志不提交到 Git。

## 4. 测试前网络配置

### 4.1 检查 IP、路由和 RDMA链路

```bash
ip -4 addr show dev enp193s0f0np0
ip -4 addr show dev enp129s0f0np0

ip route get 192.168.3.7 from 192.168.3.5
ip route get 192.168.3.7 from 192.168.3.6

rdma link
```

期望：

```text
mlx5_0/1 ACTIVE LINK_UP → enp193s0f0np0
mlx5_2/1 ACTIVE LINK_UP → enp129s0f0np0
```

### 4.2 配置 FPGA静态邻居

当前实验依赖静态邻居项：

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

两项均应显示 `PERMANENT`。服务器重启后通常需要重新配置。

## 5. 行为仿真

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
mkdir -p logs
```

ICRC 仿真：

```bash
vivado -mode batch \
  -log logs/icrc_behavioral.log \
  -journal logs/icrc_behavioral.jou \
  -source scripts/run_icrc_behavioral.tcl
```

完整数据通路仿真：

```bash
vivado -mode batch \
  -log logs/phase7_behavioral.log \
  -journal logs/phase7_behavioral.jou \
  -source scripts/run_phase7_behavioral.tcl
```

检查：

```bash
grep -E "PASS|FAIL|ERROR|FATAL" \
  logs/icrc_behavioral.log \
  logs/phase7_behavioral.log
```

当前完整回归结果：

```text
PHASE7_TEST_PASS
```

## 6. 综合、实现和 bitstream

当前功能验证构建使用 Vivado内置 `Flow_RuntimeOptimized`，完整执行综合、实现
和 bitstream生成：

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

vivado -mode batch \
  -log logs/minimal_build.log \
  -journal logs/minimal_build.jou \
  -source scripts/run_minimal_build.tcl
```

期望：

```text
MINIMAL_BUILD_PASS
route_design completed successfully
write_bitstream completed successfully
```

产物：

```text
100G_4port_allreduce_proj.runs/impl_1/
├─ qsfp28_100g_switch_4port_top.bit
└─ qsfp28_100g_switch_4port_top.ltx
```

检查生成时间：

```bash
stat \
  100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit \
  100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx
```

注意：

- 不要同时运行 GUI implementation 和 batch implementation；
- `.bit` 与 `.ltx` 必须来自同一次 run；
- 当前实现存在 setup时序违例，功能验证通过不等价于完成时序收敛。

## 7. 烧录 FPGA

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

BIT_FILE="$PWD/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.bit"
LTX_FILE="$PWD/100G_4port_allreduce_proj.runs/impl_1/qsfp28_100g_switch_4port_top.ltx"

vivado -mode batch \
  -log logs/program_hw.log \
  -journal logs/program_hw.jou \
  -source scripts/hw_program_pair_codex22.tcl \
  -tclargs "$BIT_FILE" "$LTX_FILE"
```

期望：

```text
CODEX22_PROGRAM_PAIR_PASS
VIO_PORT_ENABLE=b
```

重新烧录会清除 FPGA 内部运行状态，同时 VIO回到默认输出。烧录后必须重新
写入完整 VIO配置。

## 8. 编译 Worker

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

## 9. 双 Worker 10轮测试

使用两个 Worker终端和一个控制终端。下面的 gate前缀必须是本轮新名称，避免
旧 gate文件导致程序提前发送。

### 9.1 启动 Worker0

终端 1：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp
mkdir -p logs/manual_10round

./worker_rdma_qp \
  -d mlx5_0 \
  -i 1 \
  -n enp193s0f0np0 \
  -G 3 \
  -R ::ffff:192.168.3.7 \
  -r 0x000100 \
  -s 0 \
  -q 0 \
  -N 10 \
  -B 0x02 \
  -W /tmp/allreduce_w0_run1 \
  -o logs/manual_10round/worker0.runtime
```

确认：

```text
qp_state=3 (3=RTS)
send_waiting_for_gate=/tmp/allreduce_w0_run1.0
```

### 9.2 启动 Worker1

终端 2：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp
mkdir -p logs/manual_10round

./worker_rdma_qp \
  -d mlx5_2 \
  -i 1 \
  -n enp129s0f0np0 \
  -G 3 \
  -R ::ffff:192.168.3.7 \
  -r 0x000100 \
  -s 0 \
  -q 0 \
  -N 10 \
  -B 0x03 \
  -W /tmp/allreduce_w1_run1 \
  -o logs/manual_10round/worker1.runtime
```

确认：

```text
qp_state=3 (3=RTS)
send_waiting_for_gate=/tmp/allreduce_w1_run1.0
```

### 9.3 读取动态 QPN

终端 3：

```bash
cd /home/ubuntu/cyf/NSDI27/worker_rdma_qp

cat logs/manual_10round/worker0.runtime
cat logs/manual_10round/worker1.runtime
```

重点读取：

```text
LOCAL_QPN=<Worker0 decimal QPN>
LOCAL_QPN=<Worker1 decimal QPN>
QP_STATE=RTS
```

可直接提取：

```bash
W0_QPN=$(awk -F= '/^LOCAL_QPN=/{print $2}' \
  logs/manual_10round/worker0.runtime)

W1_QPN=$(awk -F= '/^LOCAL_QPN=/{print $2}' \
  logs/manual_10round/worker1.runtime)

echo "Worker0 QPN=$W0_QPN"
echo "Worker1 QPN=$W1_QPN"
```

### 9.4 写入并读回 VIO

```bash
source /home/ubuntu/vivado2025.2/2025.2/Vivado/settings64.sh
cd /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj

vivado -mode batch \
  -log logs/apply_vio.log \
  -journal logs/apply_vio.jou \
  -source scripts/apply_allreduce_vio.tcl \
  -tclargs "$W0_QPN" "$W1_QPN"
```

期望：

```text
VIO_APPLY_PASS
```

脚本会逐字段读回。必须确认：

```text
FPGA MAC/IP/QPN/UDP正确
Worker0 MAC/IP/QPN/UDP正确
Worker1 MAC/IP/QPN/UDP正确
root=1
child_port_mask=3
ar_cfg_update_en=0
```

### 9.5 逐轮释放 gate

只有当两个 Worker都等待同一轮 gate时，才同时释放该轮。

第 0 轮：

```bash
touch /tmp/allreduce_w0_run1.0 /tmp/allreduce_w1_run1.0
```

看到两侧都等待 `.1` 后：

```bash
touch /tmp/allreduce_w0_run1.1 /tmp/allreduce_w1_run1.1
```

后续依次释放：

```text
.2
.3
.4
.5
.6
.7
.8
.9
```

不要一次创建全部 gate。任一 Worker失败后，停止后续轮次并保存首个失败现场。

### 9.6 每轮成功判据

Worker0 和 Worker1 每轮都必须出现：

```text
Receive CQE status=success byte_len=1024
recv_payload first16=05050505050505050505050505050505
byte_sum=5120
all_same=1 value=0x05
Send CQE status=success
```

10 轮最终摘要：

```text
cq_summary completions=20
send_success=10
recv_success=10
iterations_done=10
```


## 11. 已实现范围

当前版本已经实现并在硬件上验证：

- 两个固定 Worker的 RoCEv2 RC QP；
- Worker QPN运行时动态配置；
- FPGA固定 QPN `0x000100`；
- 1024B `SEND_ONLY`；
- endpoint匹配和 connection table hit；
- logical ingress 0/1；
- 相同 PSN的两路 fan-in；
- 1024B payload加法聚合；
- FPGA作为 root向两个 child广播；
- 两个端口独立 MAC/IP/QPN rewrite；
- IPv4 checksum和 RoCEv2 ICRC重算；
- Worker Receive WQE/CQE；
- RNIC ACK输入、FPGA ACK反射和 Worker Send CQE；
- 同一 QP内至少连续 10 轮 PSN推进。


当前可复现基线提交以仓库 `master` 最新提交为准。
