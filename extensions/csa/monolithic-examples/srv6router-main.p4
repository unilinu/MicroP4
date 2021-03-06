/*
 * Author: Myriana Rifai
 * Email: myriana.rifai@nokia-bell-labs.com
 */
#include <core.p4>
#include <v1model.p4>

#define MAC_TABLE_SIZE 32
#define TABLE_SIZE 1024
#define MAX_SEG_LEFT 256
#define SEG_LEN 128
#define ROUTER_FUNC 0 // 0 for SR domain entry point , 1 for SR transit node
#define FIRST_SEG 0x02560a0b0c025660a0b0f5670dbbfe03
#define ROUTER_IP 0x20010a0b0c025660a0b0f5670dbbfe01
#define LOCAL_SRV6_SID 0x025603a1cc025660000000000000000
#define LOCAL_INT 0x02560a0b0c0256600000000000000000


struct srv6router_meta_t { 
  bit<8> if_index;
  bit<16> next_hop;
  bit<1> drop_flag;
}
 
header ethernet_h {
  bit<48> dstAddr;
  bit<48> srcAddr;
  bit<16> etherType;
}


header ipv6_h {
  bit<4> version;
  bit<8> class;
  bit<20> label;
  bit<16> totalLen;
  bit<8> nexthdr;
  bit<8> hoplimit;
  bit<128> srcAddr;
  bit<128> dstAddr;  
}

header routing_ext_h {
	bit<8> nexthdr;
	bit<8> hdr_ext_len; // gives the length of the routing extension header in octets
	bit<8> routing_type;
}

header sr6_h {
	bit<8> seg_left;
	bit<8> last_entry;  // index of the last element of the segment list zero based
	bit<8> flags; // 0 flag --> unused 
	bit<16> tag; // 0 if unused , not used when processsing the sid in 4.3.1	
}

header seg1_h {
	bit<128> seg1;
}

header seg2_h {
	bit<128> seg1;
	bit<128> seg2;
}

header seg3_h {
	bit<128> seg1;
	bit<128> seg2;
	bit<128> seg3;
	bit<128> seg4;
}

header seg4ton_h {
	bit<128> seg1;
	bit<128> seg2;
	bit<128> seg3;
	bit<128> seg4;
	varbit<((MAX_SEG_LEFT-4) * SEG_LEN)> segment_lists; // first element contains the last segment of the SR policy 
}

struct srv6router_hdr_t {
  ethernet_h ethernet;
  ipv6_h outer_ipv6;
  routing_ext_h routing_ext0;
  sr6_h sr6;
  seg1_h seg1;
  seg2_h seg2;
  seg3_h seg3;
  seg4ton_h seg4ton;
  ipv6_h inner_ipv6; 
  routing_ext_h routing_ext1;
  
}

parser ParserImpl (packet_in pin, out srv6router_hdr_t parsed_hdr, 
                inout srv6router_meta_t meta, 
                inout standard_metadata_t standard_metadata) {
 state start {
	   meta.if_index = (bit<8>)standard_metadata.ingress_port;
      transition parse_ethernet;
    }
    
    state parse_ethernet {
      pin.extract(parsed_hdr.ethernet);
      transition select(parsed_hdr.ethernet.etherType){
        0x86DD: parse_ipv6;
        _ : accept;
      }
    }
    
    state parse_ipv6 {
      pin.extract(parsed_hdr.outer_ipv6);
       transition select(parsed_hdr.outer_ipv6.nexthdr) {
        43: parse_routing_ext;
        _ : accept;
      }
    }
  
  	 state parse_routing_ext {
      pin.extract(parsed_hdr.routing_ext0);
      transition select(parsed_hdr.routing_ext0.routing_type){
      	4: check_seg_routing; 
      	_ : accept;
      }
    }
  
    state check_seg_routing {
      	transition select(parsed_hdr.outer_ipv6.dstAddr){
      		ROUTER_IP : parse_seg_routing;
      		_ : accept;
      	}
	}
    
    state parse_seg_routing {
    	pin.extract(parsed_hdr.sr6);
    	transition select(parsed_hdr.sr6.seg_left){
    		1: parse_seg1;
    		2: parse_seg2;
    		3: parse_seg3;
    		_: parse_seg4ton;
    	}
    }
    
    state parse_seg1 {
      	pin.extract(parsed_hdr.seg1);
		transition accept;
	}
	
	state parse_seg2 {
      	pin.extract(parsed_hdr.seg2);
		transition accept;
	}
	
	state parse_seg3 {
      	pin.extract(parsed_hdr.seg3);
		transition accept;
	}
    state parse_seg4ton {
      	pin.extract(parsed_hdr.seg4ton, (bit<32>)(parsed_hdr.routing_ext0.hdr_ext_len *128 - 24));
		transition accept;
	}
}

control egress(inout srv6router_hdr_t parsed_hdr, inout srv6router_meta_t meta,
                 inout standard_metadata_t standard_metadata) {	
              
     action drop_action() {
   		 meta.drop_flag = 1;
    }
 
      table drop_table{
            key = { 
                standard_metadata.deq_qdepth
                  : exact ;
            }
            actions = {
                drop_action;
                NoAction;
            }
            
            const entries = {
                19w64 : drop_action();
            }
           
            size = MAC_TABLE_SIZE;
            default_action = NoAction;
        }	
    
	apply{
        drop_table.apply();
	}
}
    
control ingress(inout srv6router_hdr_t parsed_hdr, inout srv6router_meta_t meta,
                 inout standard_metadata_t standard_metadata) {	
                 
        
      action set_dmac(bit<48> dmac, bit<9> port) {
          // P4Runtime error...
            standard_metadata.egress_port = port;
            parsed_hdr.ethernet.dstAddr = dmac;
        }

        action drop_action() {
            meta.drop_flag = 1;
        }
 
        table dmac {
            key = { meta.next_hop: exact; }
            actions = {
                drop_action;
                set_dmac;
            }
            const entries = {
                16w15 : set_dmac(0x000000000002, 9w2);
                16w32 : set_dmac(0x000000000003, 9w3);
            }
            default_action = drop_action;
            // size = TABLE_SIZE;
        }
 
        action set_smac(bit<48> smac) {
            parsed_hdr.ethernet.srcAddr = smac;
        }
 
        table smac {
            key = {  standard_metadata.egress_port : exact ; }
            actions = {
                drop_action;
                set_smac;
            }
            default_action = drop_action;
            const entries = {
                9w2 : set_smac(0x000000000020);
                9w3 : set_smac(0x000000000030);
            }
            // size = MAC_TABLE_SIZE;
        }
 
    action default_act() {
    	meta.next_hop = 0;
    }
    
    action process_v6(bit<16> nexthop, bit<9> port){
	      parsed_hdr.outer_ipv6.hoplimit = parsed_hdr.outer_ipv6.hoplimit - 1;
	      meta.next_hop = nexthop;
	      standard_metadata.egress_port = port;
    }
     
    table ipv6_lpm_tbl {
      key = { 
      	parsed_hdr.outer_ipv6.dstAddr : lpm ;
        parsed_hdr.outer_ipv6.hoplimit : exact;
        parsed_hdr.outer_ipv6.class : ternary;
        parsed_hdr.outer_ipv6.label : ternary;
        } 
      actions = { 
	      process_v6; 
	      default_act;
	   }
	  default_action = default_act;    
      
    }
    
                     
   	action ingress_sr(){
		// SR domain ingress router : generate SR segment packet with segment in the destination i.e. encapsulates a received pkt in outer ipv6 hdr followed by optional srh
		parsed_hdr.routing_ext0.setValid();
		parsed_hdr.routing_ext0.nexthdr = 43;
		parsed_hdr.routing_ext0.hdr_ext_len = 6; 
		parsed_hdr.routing_ext0.routing_type = 4;
		parsed_hdr.sr6.setValid();
		parsed_hdr.sr6. seg_left = 3;
		parsed_hdr.sr6.last_entry = 3;  
		parsed_hdr.sr6.flags = 0;
		parsed_hdr.sr6.tag = 0; 
		parsed_hdr.seg3.setValid();
		parsed_hdr.seg3.seg1 = 0x02560a0b0c025660a0b0f5670dbbfe03;
		parsed_hdr.seg3.seg2 = 0x025d0a0b0c125660a0b0f5670dbbfe03;
		parsed_hdr.seg3.seg3 = 0x02560ade0c025660a0b0f5670dbbfe03;
		parsed_hdr.outer_ipv6.dstAddr = FIRST_SEG;
	
		parsed_hdr.inner_ipv6.setValid();
		// copy the exact same values from the outer ipv6 address with the original ipv6 destination address 
		parsed_hdr.inner_ipv6.version = parsed_hdr.outer_ipv6.version ;
  		parsed_hdr.inner_ipv6.class = parsed_hdr.outer_ipv6.class;
  		parsed_hdr.inner_ipv6.label = parsed_hdr.outer_ipv6.label;
  		parsed_hdr.inner_ipv6.totalLen = parsed_hdr.outer_ipv6.totalLen;
  		parsed_hdr.inner_ipv6.nexthdr = parsed_hdr.outer_ipv6.nexthdr;
  		parsed_hdr.inner_ipv6.hoplimit = parsed_hdr.outer_ipv6.hoplimit;
  		parsed_hdr.inner_ipv6.srcAddr = parsed_hdr.outer_ipv6.srcAddr;
  		parsed_hdr.inner_ipv6.dstAddr = parsed_hdr.outer_ipv6.dstAddr;  
	 
	}  
	                     
	action endpoint_sr_lss() {
		parsed_hdr.sr6.seg_left = parsed_hdr.sr6.seg_left -1;
		//parsed_hdr.outer_ipv6.dstAddr = parsed_hdr.sr6.segment_lists[(parsed_hdr.routing_ext0..ext_len-3-parsed_hdr.sr6.seg_left)*128:(parsed_hdr.routing_ext0.ext_len-2-parsed_hdr.sr6.seg_left)*128];
	}

	// if egress domain sr router then decap the SR outer IP header + SRH and process next hdr 
	action egress_sr(){
		parsed_hdr.routing_ext0.setInvalid();
		parsed_hdr.sr6.setInvalid();
		parsed_hdr.inner_ipv6.setInvalid();
		parsed_hdr.outer_ipv6.version = parsed_hdr.inner_ipv6.version ;
  		parsed_hdr.outer_ipv6.class = parsed_hdr.inner_ipv6.class;
  		parsed_hdr.outer_ipv6.label = parsed_hdr.inner_ipv6.label;
  		parsed_hdr.outer_ipv6.totalLen = parsed_hdr.inner_ipv6.totalLen;
  		parsed_hdr.outer_ipv6.nexthdr = parsed_hdr.inner_ipv6.nexthdr;
  		parsed_hdr.outer_ipv6.hoplimit = parsed_hdr.inner_ipv6.hoplimit;
  		parsed_hdr.outer_ipv6.srcAddr = parsed_hdr.inner_ipv6.srcAddr;
  		parsed_hdr.outer_ipv6.dstAddr = parsed_hdr.inner_ipv6.dstAddr;   
	}
	
	table srv6_tbl{
    	key = {
	    	 parsed_hdr.routing_ext0.routing_type: exact;
	    	 parsed_hdr.outer_ipv6.dstAddr: lpm;
	    	 parsed_hdr.sr6.last_entry: ternary; 
	    	 parsed_hdr.sr6.seg_left: ternary; 
    	}
    	actions = {
    		ingress_sr;
    		endpoint_sr_lss;
    		egress_sr;
    		drop_action;    		
    	}
    	 const entries = {
	    	(4, LOCAL_SRV6_SID, _, 0) : egress_sr();
	    	//(4, LOCAL_SRV6_SID, _, _ ) : drop_action();
	    	(4, LOCAL_SRV6_SID, _, _) : endpoint_sr_lss(); 
	    	(4, LOCAL_INT, _, 0) : egress_sr();
	    	(4, LOCAL_INT, _, _) : drop_action();
	    	(4, _, _, _) : ingress_sr();
    	}
    }	
    
	apply{

	if (parsed_hdr.ethernet.etherType == 0x86DD){
		if (parsed_hdr.outer_ipv6.nexthdr == 43)
    		srv6_tbl.apply();
		ipv6_lpm_tbl.apply();
	}
	 dmac.apply(); 
     smac.apply();
	}
}

control DeparserImpl(packet_out packet, in  srv6router_hdr_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.outer_ipv6); 
        packet.emit(hdr.routing_ext0);
        packet.emit(hdr.sr6); 
        packet.emit(hdr.seg1); 
        packet.emit(hdr.seg2); 
        packet.emit(hdr.seg3); 
        packet.emit(hdr.seg4ton); 
        packet.emit(hdr.inner_ipv6);  
        packet.emit(hdr.routing_ext1);  
    }
}


control verifyChecksum(inout  srv6router_hdr_t hdr, inout srv6router_meta_t meta) {
    apply {
    }
}

control computeChecksum(inout  srv6router_hdr_t hdr, inout srv6router_meta_t meta) {
    apply {
    }
}

V1Switch(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;
