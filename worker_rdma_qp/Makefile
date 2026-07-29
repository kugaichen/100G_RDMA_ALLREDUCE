CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
TARGET := worker_rdma_qp

all: $(TARGET)

$(TARGET): worker_rdma_qp.c
	$(CC) $(CFLAGS) -o $@ $< -libverbs

clean:
	rm -f $(TARGET)

.PHONY: all clean
