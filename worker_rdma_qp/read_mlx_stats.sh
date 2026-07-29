#!/usr/bin/env bash
set -u

for iface in enp193s0f0np0 enp129s0f0np0; do
    echo "=== ${iface} ==="
    ethtool -S "$iface" 2>/dev/null |
        grep -E '^[[:space:]]+(rx_packets_phy|rx_bytes_phy|rx_vport_rdma_unicast_packets|rx_vport_rdma_unicast_bytes|rx_crc_errors_phy|rx_in_range_len_errors_phy|rx_out_of_range_len_phy|rx_oversize_pkts_phy|rx_discards_phy|rx_1024_to_1518_bytes_phy|tx_packets_phy|tx_vport_rdma_unicast_packets):'
done
