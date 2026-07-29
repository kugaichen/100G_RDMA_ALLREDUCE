#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <infiniband/verbs.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define BUFFER_SIZE 4096U
#define SEND_SIZE 1024U
#define RECV_OFFSET 2048U
#define CQ_TIMEOUT_MS 10000U
#define DEFAULT_ITERATIONS 1U
#define DEFAULT_REMOTE_QPN 0x000100U
#define DEFAULT_GID_INDEX 3

static volatile sig_atomic_t stop_requested;

static void on_signal(int signo) {
    (void)signo;
    stop_requested = 1;
}

static void fail(const char *what) {
    fprintf(stderr, "%s: %s\n", what, strerror(errno));
    exit(EXIT_FAILURE);
}

static void print_recv_payload_summary(const uint8_t *data,
                                       size_t len,
                                       uint32_t iter) {
    uint64_t byte_sum = 0;
    uint8_t first = len ? data[0] : 0;
    int all_same = 1;

    for (size_t i = 0; i < len; ++i) {
        byte_sum += data[i];
        if (data[i] != first)
            all_same = 0;
    }

    printf("recv_payload iter=%u first16=", iter);
    size_t preview = len < 16 ? len : 16;
    for (size_t i = 0; i < preview; ++i)
        printf("%02x", data[i]);
    printf(" byte_sum=%llu all_same=%d value=0x%02x\n",
           (unsigned long long)byte_sum, all_same, first);
    fflush(stdout);
}

static uint32_t parse_u24(const char *text, const char *name) {
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 0);
    if (errno || !end || *end != '\0' || value > 0x00ffffffUL) {
        fprintf(stderr, "Invalid %s: %s\n", name, text);
        exit(EXIT_FAILURE);
    }
    return (uint32_t)value;
}

static uint8_t parse_u8(const char *text, const char *name) {
    uint32_t value = parse_u24(text, name);
    if (value > 0xffU) {
        fprintf(stderr, "Invalid %s: %s (expected 0..255)\n", name, text);
        exit(EXIT_FAILURE);
    }
    return (uint8_t)value;
}

static void usage(const char *prog) {
    fprintf(stderr,
            "Usage: %s [-d mlx5_0] [-i 1] [-n netdev] [-p 4791] "
            "[-G sgid_index] [-R remote_gid] [-r remote_qpn] "
            "[-s sq_psn] [-q rq_psn] [-N iterations (0=continuous)] "
            "[-B payload_byte] [-o runtime.env] [-w first_send_gate] "
            "[-W per_iteration_gate_prefix]\n",
            prog);
}

static struct ibv_device *find_device(struct ibv_device **devices,
                                      int num_devices,
                                      const char *name) {
    for (int i = 0; i < num_devices; ++i) {
        if (strcmp(ibv_get_device_name(devices[i]), name) == 0)
            return devices[i];
    }
    return NULL;
}

static void gid_to_text(const union ibv_gid *gid, char text[INET6_ADDRSTRLEN]) {
    if (!inet_ntop(AF_INET6, gid->raw, text, INET6_ADDRSTRLEN))
        snprintf(text, INET6_ADDRSTRLEN, "<invalid>");
}

static void qp_to_init(struct ibv_qp *qp, int ib_port) {
    struct ibv_qp_attr attr = {
        .qp_state = IBV_QPS_INIT,
        .pkey_index = 0,
        .port_num = (uint8_t)ib_port,
        .qp_access_flags = 0
    };
    int mask = IBV_QP_STATE | IBV_QP_PKEY_INDEX |
               IBV_QP_PORT | IBV_QP_ACCESS_FLAGS;
    if (ibv_modify_qp(qp, &attr, mask))
        fail("ibv_modify_qp INIT");
}

static void qp_to_rtr(struct ibv_qp *qp,
                      int ib_port,
                      int sgid_index,
                      const union ibv_gid *remote_gid,
                      uint32_t remote_qpn,
                      uint32_t rq_psn) {
    struct ibv_qp_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.qp_state = IBV_QPS_RTR;
    attr.path_mtu = IBV_MTU_1024;
    attr.dest_qp_num = remote_qpn;
    attr.rq_psn = rq_psn;
    attr.max_dest_rd_atomic = 1;
    attr.min_rnr_timer = 12;
    attr.ah_attr.is_global = 1;
    attr.ah_attr.port_num = (uint8_t)ib_port;
    attr.ah_attr.grh.dgid = *remote_gid;
    attr.ah_attr.grh.sgid_index = (uint8_t)sgid_index;
    attr.ah_attr.grh.hop_limit = 64;

    int mask = IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
               IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
               IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER;
    if (ibv_modify_qp(qp, &attr, mask))
        fail("ibv_modify_qp RTR");
}

static void qp_to_rts(struct ibv_qp *qp, uint32_t sq_psn) {
    struct ibv_qp_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.qp_state = IBV_QPS_RTS;
    attr.timeout = 14;
    attr.retry_cnt = 7;
    attr.rnr_retry = 7;
    attr.sq_psn = sq_psn;
    attr.max_rd_atomic = 1;

    int mask = IBV_QP_STATE | IBV_QP_TIMEOUT | IBV_QP_RETRY_CNT |
               IBV_QP_RNR_RETRY | IBV_QP_SQ_PSN | IBV_QP_MAX_QP_RD_ATOMIC;
    if (ibv_modify_qp(qp, &attr, mask))
        fail("ibv_modify_qp RTS");
}

static void write_runtime_file(const char *path,
                               const char *device,
                               const char *netdev,
                               int ib_port,
                               int gid_index,
                               const char *local_gid,
                               const char *remote_gid,
                               uint32_t local_qpn,
                               uint32_t remote_qpn,
                               uint32_t sq_psn,
                               uint32_t rq_psn) {
    if (!path)
        return;
    FILE *fp = fopen(path, "w");
    if (!fp)
        fail("fopen runtime file");
    fprintf(fp, "DEVICE=%s\n", device);
    fprintf(fp, "NETDEV=%s\n", netdev ? netdev : "");
    fprintf(fp, "IB_PORT=%d\n", ib_port);
    fprintf(fp, "SGID_INDEX=%d\n", gid_index);
    fprintf(fp, "LOCAL_GID=%s\n", local_gid);
    fprintf(fp, "REMOTE_GID=%s\n", remote_gid);
    fprintf(fp, "LOCAL_QPN=%u\n", local_qpn);
    fprintf(fp, "REMOTE_QPN=%u\n", remote_qpn);
    fprintf(fp, "SQ_PSN=%u\n", sq_psn);
    fprintf(fp, "RQ_PSN=%u\n", rq_psn);
    fprintf(fp, "QP_STATE=RTS\n");
    if (fclose(fp))
        fail("fclose runtime file");
}

int main(int argc, char **argv) {
    const char *dev_name = "mlx5_0";
    const char *netdev = NULL;
    const char *remote_gid_text = "::ffff:192.168.3.7";
    const char *runtime_path = NULL;
    const char *send_gate_path = NULL;
    const char *iteration_gate_prefix = NULL;
    int ib_port = 1;
    int udp_port = 4791;
    int sgid_index = DEFAULT_GID_INDEX;
    uint32_t remote_qpn = DEFAULT_REMOTE_QPN;
    uint32_t sq_psn = 0;
    uint32_t rq_psn = 0;
    uint32_t iterations = DEFAULT_ITERATIONS;
    uint8_t payload_byte = 0;
    int opt;

    while ((opt = getopt(argc, argv, "d:i:n:p:G:R:r:s:q:N:B:o:w:W:h")) != -1) {
        switch (opt) {
        case 'd': dev_name = optarg; break;
        case 'i': ib_port = atoi(optarg); break;
        case 'n': netdev = optarg; break;
        case 'p': udp_port = atoi(optarg); break;
        case 'G': sgid_index = atoi(optarg); break;
        case 'R': remote_gid_text = optarg; break;
        case 'r': remote_qpn = parse_u24(optarg, "remote QPN"); break;
        case 's': sq_psn = parse_u24(optarg, "SQ PSN"); break;
        case 'q': rq_psn = parse_u24(optarg, "RQ PSN"); break;
        case 'N':
            iterations = parse_u24(optarg, "iterations");
            break;
        case 'B': payload_byte = parse_u8(optarg, "payload byte"); break;
        case 'o': runtime_path = optarg; break;
        case 'w': send_gate_path = optarg; break;
        case 'W': iteration_gate_prefix = optarg; break;
        case 'h': usage(argv[0]); return 0;
        default: usage(argv[0]); return EXIT_FAILURE;
        }
    }

    if (send_gate_path && iteration_gate_prefix) {
        fprintf(stderr, "-w and -W cannot be used together\n");
        return EXIT_FAILURE;
    }

    union ibv_gid remote_gid;
    if (inet_pton(AF_INET6, remote_gid_text, remote_gid.raw) != 1) {
        fprintf(stderr, "Invalid remote GID: %s\n", remote_gid_text);
        return EXIT_FAILURE;
    }

    int num_devices = 0;
    struct ibv_device **devices = ibv_get_device_list(&num_devices);
    if (!devices)
        fail("ibv_get_device_list");
    struct ibv_device *dev = find_device(devices, num_devices, dev_name);
    if (!dev) {
        fprintf(stderr, "RDMA device not found: %s\n", dev_name);
        ibv_free_device_list(devices);
        return EXIT_FAILURE;
    }

    struct ibv_context *ctx = ibv_open_device(dev);
    if (!ctx)
        fail("ibv_open_device");
    struct ibv_device_attr dev_attr;
    if (ibv_query_device(ctx, &dev_attr))
        fail("ibv_query_device");
    if (ib_port < 1 || ib_port > dev_attr.phys_port_cnt) {
        fprintf(stderr, "Invalid IB port %d (physical ports: %d)\n",
                ib_port, dev_attr.phys_port_cnt);
        return EXIT_FAILURE;
    }

    struct ibv_port_attr port_attr;
    if (ibv_query_port(ctx, ib_port, &port_attr))
        fail("ibv_query_port");
    if (sgid_index < 0 || sgid_index >= port_attr.gid_tbl_len) {
        fprintf(stderr, "Invalid SGID index %d (GID table length: %d)\n",
                sgid_index, port_attr.gid_tbl_len);
        return EXIT_FAILURE;
    }

    union ibv_gid local_gid;
    if (ibv_query_gid(ctx, ib_port, sgid_index, &local_gid))
        fail("ibv_query_gid");
    char local_gid_text[INET6_ADDRSTRLEN];
    gid_to_text(&local_gid, local_gid_text);

    struct ibv_pd *pd = ibv_alloc_pd(ctx);
    if (!pd)
        fail("ibv_alloc_pd");
    struct ibv_cq *cq = ibv_create_cq(ctx, 16, NULL, NULL, 0);
    if (!cq)
        fail("ibv_create_cq");

    void *buffer = NULL;
    if (posix_memalign(&buffer, 4096, BUFFER_SIZE))
        fail("posix_memalign");
    memset(buffer, 0, BUFFER_SIZE);
    for (unsigned int i = 0; i < SEND_SIZE; ++i)
        ((uint8_t *)buffer)[i] = payload_byte;
    struct ibv_mr *mr = ibv_reg_mr(pd, buffer, BUFFER_SIZE, IBV_ACCESS_LOCAL_WRITE);
    if (!mr)
        fail("ibv_reg_mr");

    struct ibv_qp_init_attr init = {
        .send_cq = cq,
        .recv_cq = cq,
        .cap = {
            .max_send_wr = 16,
            .max_recv_wr = 16,
            .max_send_sge = 1,
            .max_recv_sge = 1
        },
        .qp_type = IBV_QPT_RC,
        .sq_sig_all = 1
    };
    struct ibv_qp *qp = ibv_create_qp(pd, &init);
    if (!qp)
        fail("ibv_create_qp");

    qp_to_init(qp, ib_port);
    qp_to_rtr(qp, ib_port, sgid_index, &remote_gid,
              remote_qpn, rq_psn);
    qp_to_rts(qp, sq_psn);

    struct ibv_sge recv_sge = {
        .addr = (uintptr_t)((uint8_t *)buffer + RECV_OFFSET),
        .length = BUFFER_SIZE,
        .lkey = mr->lkey
    };
    struct ibv_recv_wr recv_wr = {
        .wr_id = 1,
        .sg_list = &recv_sge,
        .num_sge = 1
    };
    struct ibv_recv_wr *bad_recv_wr = NULL;
    if (ibv_post_recv(qp, &recv_wr, &bad_recv_wr))
        fail("ibv_post_recv");

    struct ibv_sge send_sge = {
        .addr = (uintptr_t)buffer,
        .length = SEND_SIZE,
        .lkey = mr->lkey
    };
    struct ibv_send_wr send_wr = {
        .wr_id = 2,
        .sg_list = &send_sge,
        .num_sge = 1,
        .opcode = IBV_WR_SEND,
        .send_flags = IBV_SEND_SIGNALED
    };
    struct ibv_send_wr *bad_send_wr = NULL;

    struct ibv_qp_attr queried;
    struct ibv_qp_init_attr queried_init;
    if (ibv_query_qp(qp, &queried, IBV_QP_STATE, &queried_init))
        fail("ibv_query_qp");

    printf("device=%s\n", ibv_get_device_name(ctx->device));
    printf("ib_port=%d\n", ib_port);
    printf("netdev=%s\n", netdev ? netdev : "<not specified>");
    printf("udp_port=%d\n", udp_port);
    printf("port_state=%d (4=ACTIVE)\n", port_attr.state);
    printf("link_layer=%d (2=Ethernet)\n", port_attr.link_layer);
    printf("sgid_index=%d\n", sgid_index);
    printf("local_gid=%s\n", local_gid_text);
    printf("remote_gid=%s\n", remote_gid_text);
    printf("qp_type=RC\n");
    printf("local_qpn=%u\n", qp->qp_num);
    printf("local_qpn_hex=0x%06x\n", qp->qp_num);
    printf("remote_qpn=%u\n", remote_qpn);
    printf("remote_qpn_hex=0x%06x\n", remote_qpn);
    printf("sq_psn=%u\n", sq_psn);
    printf("rq_psn=%u\n", rq_psn);
    printf("qp_state=%d (3=RTS)\n", queried.qp_state);
    printf("recv_posted=1\n");
    printf("send_length=%u\n", SEND_SIZE);
    printf("payload_byte=0x%02x\n", payload_byte);
    printf("iterations=%u%s\n", iterations,
           iterations == 0 ? " (continuous)" : "");
    fflush(stdout);

    write_runtime_file(runtime_path, dev_name, netdev, ib_port,
                       sgid_index, local_gid_text, remote_gid_text,
                       qp->qp_num, remote_qpn, sq_psn, rq_psn);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    unsigned int send_completions = 0;
    unsigned int recv_completions = 0;
    unsigned int total_completions = 0;
    for (uint32_t iter = 0;
         (iterations == 0 || iter < iterations) && !stop_requested;
         ++iter) {
        if (iter > 0) {
            recv_wr.wr_id = 1;
            if (ibv_post_recv(qp, &recv_wr, &bad_recv_wr))
                fail("ibv_post_recv");
        }

        char iteration_gate_path[4096];
        const char *active_gate_path = NULL;
        if (iteration_gate_prefix) {
            int gate_len = snprintf(iteration_gate_path,
                                    sizeof(iteration_gate_path),
                                    "%s.%u", iteration_gate_prefix, iter);
            if (gate_len < 0 || (size_t)gate_len >= sizeof(iteration_gate_path)) {
                fprintf(stderr, "iteration gate path is too long\n");
                stop_requested = 1;
                break;
            }
            active_gate_path = iteration_gate_path;
        } else if (iter == 0) {
            active_gate_path = send_gate_path;
        }

        if (active_gate_path) {
            printf("send_waiting_for_gate=%s\n", active_gate_path);
            fflush(stdout);
            while (!stop_requested && access(active_gate_path, F_OK) != 0) {
                const struct timespec gate_sleep = {0, 10000000L};
                nanosleep(&gate_sleep, NULL);
            }
        }
        if (stop_requested)
            break;

        send_wr.wr_id = 2 + iter;
        if (ibv_post_send(qp, &send_wr, &bad_send_wr))
            fail("ibv_post_send");
        printf("send_posted=%u iter=%u\n", iter + 1, iter);
        fflush(stdout);

        struct ibv_wc wc[2];
        unsigned int iter_completions = 0;
        unsigned int elapsed_ms = 0;
        while (!stop_requested && iter_completions < 2 && elapsed_ms < CQ_TIMEOUT_MS) {
            int n = ibv_poll_cq(cq, 2, wc);
            if (n < 0)
                fail("ibv_poll_cq");
            for (int i = 0; i < n; ++i) {
                printf("cq_completion=%u iter=%u wr_id=%llu status=%s(%d) opcode=%d byte_len=%u vendor_err=%u\n",
                       total_completions + 1, iter,
                       (unsigned long long)wc[i].wr_id,
                       ibv_wc_status_str(wc[i].status), wc[i].status,
                       wc[i].opcode, wc[i].byte_len, wc[i].vendor_err);
                fflush(stdout);
                if (wc[i].status != IBV_WC_SUCCESS) {
                    stop_requested = 1;
                    break;
                }
                if (wc[i].opcode == IBV_WC_RECV) {
                    if (wc[i].byte_len != SEND_SIZE) {
                        fprintf(stderr, "RECV_LENGTH_MISMATCH iter=%u expected=%u actual=%u\n",
                                iter, SEND_SIZE, wc[i].byte_len);
                        stop_requested = 1;
                        break;
                    }
                    print_recv_payload_summary(
                        (const uint8_t *)buffer + RECV_OFFSET,
                        wc[i].byte_len, iter);
                    ++recv_completions;
                } else if (wc[i].opcode == IBV_WC_SEND) {
                    ++send_completions;
                }
                ++iter_completions;
                ++total_completions;
            }
            if (iter_completions < 2 && !stop_requested) {
                const struct timespec poll_sleep = {0, 1000000L};
                nanosleep(&poll_sleep, NULL);
                ++elapsed_ms;
            }
        }
        if (iter_completions < 2 && !stop_requested) {
            fprintf(stderr, "CQ_TIMEOUT iter=%u completions=%u timeout_ms=%u\n",
                    iter, iter_completions, CQ_TIMEOUT_MS);
            stop_requested = 1;
        }
    }
    printf("cq_summary completions=%u send_success=%u recv_success=%u iterations_done=%u\n",
           total_completions, send_completions, recv_completions,
           send_completions < recv_completions ? send_completions : recv_completions);

cleanup:
    ibv_destroy_qp(qp);
    ibv_dereg_mr(mr);
    free(buffer);
    ibv_destroy_cq(cq);
    ibv_dealloc_pd(pd);
    ibv_close_device(ctx);
    ibv_free_device_list(devices);
    return 0;
}
