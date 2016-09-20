#include "includes/headers.p4"
#include "includes/parser.p4"
#include "includes/ip_forwarding.p4"

metadata routing_metadata_t routing_metadata;
header_type routing_metadata_t {
    fields {
        nhop_ipv4 : 32;
    }
}

metadata bier_metadata_t bier_metadata;
header_type bier_metadata_t {
    fields {
        k_pos : 4;
        bs_remaining: 16;
        needs_cloning : 1;
    }
}

metadata intrinsic_metadata_t intrinsic_metadata;

control ingress {
    if(ethernet.etherType == 0xBBBB) {
        /* received a BIER packet */
        /* Falls BS nur aus 0en besteht, verwerfen */
        if(bier.BitString == 0) {
            /* markiere Paket zum drop */
            /* (wird bei find_pos mitbehandelt */
        }

        /* Finde Position k der ersten 1 im BS */
        /* -> workaround mit find_pos möglich */
        /* soll die Position in Metadaten festhalten, falls kein Hit vorliegt, besteht BitString nur aus 0en => drop action  */
        apply(find_pos) {
            hit {
                /* Falls k der eigenen BFR-id entspricht, weiter geben an multicast overlay*/
        /* prüfen evtl mit einer Tabelle mit nur dem Eintrag der eigenen BFR-id, falls ein match auftritt, ist k identisch der BFR-id */
                apply(check_bfr_id){
                    hit {
                         /* Übergabe an multicast overlay, cleare Bit k und beginne von vorne */
                    }
                }
        /* Nutze die BFR-id k als lookup key für die Bit Index Forwarding Table, erhalte als Rückgabe die F-BM und den Nachbarn NBR (evtl als Port?) */
                apply(bift);
            }
        }
        /* Bearbeitung des Packets geschieht in der Action zu bift */
        
    } else if(ethernet.etherType == 0x0800) {
        /* received a IPv4 packet. Check if it should be encapsulated in a BIER packet */
        apply(bier_ingress) {
            miss {
                /* normal ip forwarding on miss */
                apply(ipv4_lpm);
                apply(forward);
            }
            hit {
                /* BIER header was added, just recirculate it to the ingress to begin normal BIER processing */
            }
        }
    }
}

control egress {
    /*if (cloning_metadata.i2i == 1) {
        clone_egress_to_egress(1, bier_FL);
    }*/
    
    /* type 2 -> egress clone */
    if (standard_metadata.instance_type == 2) {
        
    }
    if (ethernet.etherType == 0x0800) {
        apply(send_frame);
    }
}

action _drop() {
    drop();
}

action bift_action(f_bm, nbr_port) {
    modify_field(bier_metadata.bs_remaining, bier.BitString & ~ f_bm);       
    modify_field(bier_metadata.needs_cloning, 1);
    /*clone_egress_pkt_to_egress(2, bier_FL);*/
    
    modify_field(standard_metadata.egress_spec, nbr_port);
    modify_field(bier.BitString, bier.BitString & f_bm);

    /*recirculate(bier_FL);*/
}

table bift {
    reads {
        bier_metadata.k_pos: exact;
    }
    actions {
        bift_action;
    }
}

action packet_for_bfr(bm) {
    modify_field(bier.BitString, bier.BitString & ~ bm);
    /* clear bit k and recirculate */
    /*recirculate(bier_FL);*/
}

table check_bfr_id {
    reads {
        bier_metadata.k_pos : exact;
    }
    actions {
        /* Weiterleitung an multicast overlay */
        packet_for_bfr;
    }
}

table bier_ingress {
  reads {
    ipv4.dstAddr : exact;
  }
  actions {
    add_bier_header;
    _drop;
  }
}

action add_bier_header(bitstring) {
    add_header(bier);
    modify_field(bier.BitString, bitstring);
        
    /* set ether type to BBBB, for bier packet */
    modify_field(ethernet.etherType, 0xBBBB);
    /* recirculate the paket to begin standard bier processing */
    recirculate(bier_FL);
}

/* recirculation takes a field list as parameter */
field_list bier_FL {
    bier;
    ethernet;
    bier_metadata;
    standard_metadata;
}

/* workaround to find pos k of first 1 in bitstring */
action save_pos(pos) {
    modify_field(bier_metadata.k_pos, pos);
}

table find_pos {
    reads {
        /* normally read bit string*/
        bier.BitString : lpm;
    }
    actions {
        save_pos;
        _drop;
        /* default action sollte drop sein, dann wird ein BS der nur aus 0en besteht direkt verworfen */
    }
}
