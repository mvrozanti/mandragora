#include <vmlinux.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_endian.h>
#include "maps.bpf.h"

#define AF_INET  2
#define AF_INET6 10

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, u64);
    __type(value, u64);
} cgroup_wan_tcp_send_bytes_total SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, u64);
    __type(value, u64);
} cgroup_wan_tcp_recv_bytes_total SEC(".maps");

static __always_inline int v4_is_local(__be32 daddr_be)
{
    u32 daddr = bpf_ntohl(daddr_be);
    u8 a = (daddr >> 24) & 0xFF;
    u8 b = (daddr >> 16) & 0xFF;

    if (a == 127) return 1;                   // 127.0.0.0/8 loopback
    if (a == 10) return 1;                    // 10.0.0.0/8 RFC1918
    if (a == 192 && b == 168) return 1;       // 192.168.0.0/16 RFC1918
    if (a == 172 && b >= 16 && b <= 31) return 1; // 172.16.0.0/12 RFC1918
    if (a == 169 && b == 254) return 1;       // 169.254.0.0/16 link-local
    if (a == 100 && b >= 64 && b <= 127) return 1; // 100.64.0.0/10 CGNAT (Tailscale)
    if (a >= 224) return 1;                   // multicast + reserved
    if (a == 0) return 1;                     // 0.0.0.0/8
    return 0;
}

static __always_inline int v6_is_local(const u8 *a)
{
    // ::1 loopback: 15 zero bytes followed by 0x01
    int i;
    int all_zero = 1;
    for (i = 0; i < 15; i++) {
        if (a[i] != 0) { all_zero = 0; break; }
    }
    if (all_zero && a[15] == 1) return 1;

    if (a[0] == 0xFE && (a[1] & 0xC0) == 0x80) return 1; // fe80::/10 link-local
    if ((a[0] & 0xFE) == 0xFC) return 1;                  // fc00::/7 ULA

    // ::ffff:0:0/96 IPv4-mapped — re-check the embedded IPv4
    if (a[0] == 0 && a[1] == 0 && a[2] == 0 && a[3] == 0 &&
        a[4] == 0 && a[5] == 0 && a[6] == 0 && a[7] == 0 &&
        a[8] == 0 && a[9] == 0 && a[10] == 0xFF && a[11] == 0xFF) {
        __be32 v4 = *(__be32 *)(a + 12);
        return v4_is_local(v4);
    }
    return 0;
}

static __always_inline int sk_peer_is_local(struct sock *sk)
{
    u16 family = BPF_CORE_READ(sk, __sk_common.skc_family);
    if (family == AF_INET) {
        __be32 daddr = BPF_CORE_READ(sk, __sk_common.skc_daddr);
        return v4_is_local(daddr);
    }
    if (family == AF_INET6) {
        struct in6_addr v6;
        BPF_CORE_READ_INTO(&v6, sk, __sk_common.skc_v6_daddr);
        return v6_is_local(v6.in6_u.u6_addr8);
    }
    return 1; // unknown family — drop
}

SEC("fentry/tcp_sendmsg")
int BPF_PROG(tcp_sendmsg, struct sock *sk, struct msghdr *msg, size_t size)
{
    if (sk_peer_is_local(sk)) {
        return 0;
    }
    u64 cgroup_id = bpf_get_current_cgroup_id();
    increment_map(&cgroup_wan_tcp_send_bytes_total, &cgroup_id, size);
    return 0;
}

SEC("fentry/tcp_cleanup_rbuf")
int BPF_PROG(tcp_cleanup_rbuf, struct sock *sk, int copied)
{
    if (copied <= 0) {
        return 0;
    }
    if (sk_peer_is_local(sk)) {
        return 0;
    }
    u64 cgroup_id = bpf_get_current_cgroup_id();
    increment_map(&cgroup_wan_tcp_recv_bytes_total, &cgroup_id, copied);
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
