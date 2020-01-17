/*
 * Author: Hardik Soni
 * Email: hks57@cornell.edu
 */

#include"msa.p4"
#include"common.p4"

header ipv4_nat_acl_h {

  bit<64> u1;
  // bit<4> version;
  // bit<4> ihl;
  // bit<8> diffserv;
  // bit<16> totalLen;
  // bit<16> identification;
  // bit<3> flags;
  // bit<13> fragOffset;
  bit<8> ttl;
  bit<8> protocol;
  bit<16> checksum;
  bit<32> srcAddr;
  bit<32> dstAddr; 
}

header tcp_nat_acl_h {
  bit<16> srcPort;
  bit<16> dstPort;
  bit<96> unused;
  bit<16> checksum;
  bit<16> urgentPointer;
}

header udp_nat_acl_h {
  bit<16> srcPort;
  bit<16> dstPort;
  bit<16> len;
  bit<16> checksum;
}

struct ipv4_nat_acl_hdr_t {
  ipv4_nat_acl_h ipv4nf;
  tcp_nat_acl_h tcpnf;
  udp_nat_acl_h udpnf;
}

struct ipv4_nat_acl_meta_t {
  bit<16> sp;
  bit<16> dp;
}

cpackage IPv4NatACL : implements Unicast<ipv4_nat_acl_hdr_t, 
                                            ipv4_nat_acl_meta_t, 
                                            empty_t, empty_t, acl_result_t> {

  parser micro_parser(extractor ex, pkt p, im_t im, out ipv4_nat_acl_hdr_t hdr, 
                      inout ipv4_nat_acl_meta_t meta, in empty_t ia, 
                      inout acl_result_t ioa) {
    state start {
      ex.extract(p, hdr.ipv4nf);
      transition select (hdr.ipv4nf.protocol) {
        8w0x17 : parse_udp;
        8w0x06 : parse_tcp;
      }
    }

    state parse_tcp {
      ex.extract(p, hdr.tcpnf);
      meta.sp = hdr.tcpnf.srcPort;
      meta.dp = hdr.tcpnf.dstPort;
      transition accept;
    }
    state parse_udp {
      ex.extract(p, hdr.udpnf);
      meta.sp = hdr.udpnf.srcPort;
      meta.dp = hdr.udpnf.dstPort;
      transition accept;
    }
  }

  control micro_control(pkt p, im_t im, inout ipv4_nat_acl_hdr_t hdr, 
                        inout ipv4_nat_acl_meta_t meta, in empty_t ia, 
                        out empty_t oa, inout acl_result_t ioa) {

    IPv4ACL() acl_i;
    ipv4_acl_in_t  ft_in;
    bit<32> nsrc = 32w0;
    action set_ipv4_src(bit<32> is) {
      hdr.ipv4nf.srcAddr = is;
      hdr.ipv4nf.checksum = 16w0x0000;
    }
    action set_ipv4_dst(bit<32> id) {
      hdr.ipv4nf.dstAddr = id;
      hdr.ipv4nf.checksum = 16w0x0000;
    }
    action set_tcp_dst_src(bit<16> td, bit<16> ts) {
      hdr.tcpnf.dstPort = td;
      hdr.tcpnf.srcPort = ts;
      hdr.tcpnf.checksum = 16w0x0000;
    }

    action set_tcp_dst(bit<16> td) {
      hdr.tcpnf.dstPort = td;
      hdr.tcpnf.checksum = 16w0x0000;
    }
    action set_tcp_src(bit<16> ts) {
      hdr.tcpnf.srcPort = ts;
      hdr.tcpnf.checksum = 16w0x0000;
    }

    action set_udp_dst_src(bit<16> ud, bit<16> us) {
      hdr.udpnf.dstPort = ud;
      hdr.udpnf.srcPort = us;
      hdr.udpnf.checksum = 16w0x0000;
    }
    action set_udp_dst(bit<16> ud) {
      hdr.udpnf.dstPort = ud;
      hdr.udpnf.checksum = 16w0x0000;
    }
    action set_udp_src(bit<16> us) {
      hdr.udpnf.srcPort = us;
      hdr.udpnf.checksum = 16w0x0000;
    }
    action na(){}

    table ipv4_nat {
      key = { 
        hdr.ipv4nf.srcAddr : exact;
        hdr.ipv4nf.dstAddr : exact;
        hdr.ipv4nf.protocol : exact;
        meta.sp : exact;
        meta.dp : exact;
      } 
      actions = { 
        set_ipv4_src;
        set_ipv4_dst;
        set_tcp_src;
        set_tcp_dst;
        set_udp_dst;
        set_udp_src;
        set_tcp_dst_src;
        set_udp_dst_src;
        na;
      }
      default_action = na();
    }

    apply { 
      ft_in.sa = hdr.ipv4nf.srcAddr;
      ft_in.da = hdr.ipv4nf.dstAddr;
      ipv4_nat.apply(); 
      ft_in.da = hdr.ipv4nf.dstAddr;
      acl_i.apply(p, im, ft_in, oa, ioa);
    }
  }

  control micro_deparser(emitter em, pkt p, in ipv4_nat_acl_hdr_t h) {
    apply { 
      em.emit(p, h.ipv4nf); 
      em.emit(p, h.tcpnf); 
      em.emit(p, h.udpnf); 
    }
  }
}

/*************** an alternative approach ***************/
/*
struct no_hdr_t {}
struct ipv4_nattable_in_t {
  bit<32> sa;
  bit<32> da;
}
cpackage IPv4NatACLTable : implements Unicast<no_hdr_t, empty_t, 
                                  ipv4_nattable_in_t, empty_t, acl_result_t> {
  parser micro_parser(extractor ex, pkt p, im_t im, out no_hdr_t hdr, 
                      inout empty_t meta, 
                      in ipv4_nattable_in_t ia, inout acl_result_t ioa) {
    state start {
      transition accept;
    }
  }

  control micro_control(pkt p, im_t im, inout no_hdr_t hdr, inout empty_t m,
                          in ipv4_nattable_in_t ia, out empty_t oa, 
                          inout acl_result_t ioa) {
    action set_hard_drop() {
      ioa.hard_drop = 1w1;
      ioa.soft_drop = 1w0;
    }
    action set_soft_drop() {
      ioa.hard_drop = 1w0;
      ioa.soft_drop = 1w1;
    }
    action allow() {
      ioa.hard_drop = 1w0;
      ioa.soft_drop = 1w0;
    }

    table ipv4_nat {
      key = { 
        ia.sa : exact;
        ia.da : exact;
      } 
      actions = { 
        set_hard_drop; 
        set_soft_drop;
        allow;
      }
      default_action = allow;

    }
    apply { 
      ipv4_nat.apply(); 
    }
  }

  control micro_deparser(emitter em, pkt p, in no_hdr_t h) {
    apply { 
    }
  }
}
*/
/*******************************************************/
