/*
 * Author: Hardik Soni
 * Email: hks57@cornell.edu
 */

#include"msa.p4"
#include"common-encap.p4"

struct l3_meta_t { }

header ipv6_h {
  bit<128> srcAddr;
  bit<128> dstAddr; 
}

header ipv4_h {
  bit<4> version;
  bit<4> ihl;
  bit<8> diffserv;
  bit<16> totalLen;
  bit<16> identification;
  bit<3> flags;
  bit<13> fragOffset;
  bit<8> ttl;
  bit<8> protocol;
  bit<16> hdrChecksum;
  bit<16> srcAddr;
  bit<16> dstAddr; 
}

header ipv4_h1 {
  bit<16> srcAddr;
  bit<16> dstAddr; 
}


struct l3_hdr_t {
  ipv4_h ipv4;
  ipv4_h ipv4_1;
  ipv6_h ipv6;
}

cpackage L3v4 : implements Unicast<l3_hdr_t, l3_meta_t, empty_t, bit<16>, bit<16>> {
  parser micro_parser(extractor ex, pkt p, im_t im, out l3_hdr_t hdr, inout l3_meta_t meta,
                        in empty_t ia, inout bit<16> ethType) { //inout arg
    state start {
      transition select(ethType){
        0x0800: parse_ipv4;
      }
    }
    state parse_ipv4 {
      ex.extract(p, hdr.ipv4);
      transition accept;
    }
  }

  control micro_control(pkt p, im_t im, inout l3_hdr_t hdr, inout l3_meta_t m,
                          in empty_t e, out bit<16> nexthop, 
                          inout bit<16> ethType) { // nexthop out arg
    action process(bit<16> nh) {
      hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
      nexthop = nh;  // setting out param
      hdr.ipv6.setValid();
    }
    action default_act() {
      hdr.ipv4.setInvalid();
      hdr.ipv4_1.setValid();
      nexthop = 0; 
    }

    table ipv4_lpm_tbl {
      key = { hdr.ipv4.dstAddr : lpm; } 
      actions = { process; default_act;}
      default_action = default_act;

    }
    apply { ipv4_lpm_tbl.apply(); }
  }

  control micro_deparser(emitter em, pkt p, in l3_hdr_t h) {
    apply { 
      em.emit(p, h.ipv4); 
      em.emit(p, h.ipv4_1); 
      em.emit(p, h.ipv6); 
    }
  }
}

 
