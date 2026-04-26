#include <vmlinux.h>
#include <bpf/bpf_tracing.h>
#include "maps.bpf.h"

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, u64);
    __type(value, u64);
} cgroup_tcp_send_bytes_total SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, u64);
    __type(value, u64);
} cgroup_tcp_recv_bytes_total SEC(".maps");

SEC("fentry/tcp_sendmsg")
int BPF_PROG(tcp_sendmsg, struct sock *sk, struct msghdr *msg, size_t size)
{
    u64 cgroup_id = bpf_get_current_cgroup_id();
    increment_map(&cgroup_tcp_send_bytes_total, &cgroup_id, size);
    return 0;
}

SEC("fentry/tcp_cleanup_rbuf")
int BPF_PROG(tcp_cleanup_rbuf, struct sock *sk, int copied)
{
    if (copied <= 0) {
        return 0;
    }
    u64 cgroup_id = bpf_get_current_cgroup_id();
    increment_map(&cgroup_tcp_recv_bytes_total, &cgroup_id, copied);
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
