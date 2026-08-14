#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

iverilog -g2012 -I imports/src/allreduce \
  -s tb_moe_fullflow \
  -o /tmp/tb_moe_fullflow.vvp \
  scripts/iverilog_xilinx_primitives_stub.v \
  $(find imports/src/allreduce -maxdepth 1 -name '*.v' ! -name 'tb_*' ! -name '*_tb.v' -print) \
  imports/src/allreduce/tb_moe_fullflow.v

sim_output="$(vvp /tmp/tb_moe_fullflow.vvp)"
printf '%s\n' "$sim_output"

if printf '%s\n' "$sim_output" | grep -q "FAIL:"; then
  exit 1
fi

if ! printf '%s\n' "$sim_output" | grep -q "TB_MOE_FULLFLOW_PASS"; then
  exit 1
fi

echo "MOE_FULLFLOW_IVERILOG_CHECK_PASS"
