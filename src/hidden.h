#ifndef _WG_HIDDEN_H
#define _WG_HIDDEN_H

#include "device.h"
#include "peer.h"


size_t prepare_skb_hidden(struct sk_buff *skb, struct wg_device *wg);

void skb_push_hidden_handshake_cookie(void *skb, void *buffer, struct wg_device *wg);

void skb_push_hidden_handshake(void *skb, void *buffer, struct wg_peer *peer);

void skb_push_hidden_data(struct sk_buff *skb, struct wg_peer *peer, bool is_keepalive);


#define QUIC_START_FIELDS u8 flags; __be32 version;
#define QUIC_END_FIELDS u8 token_len; __be16 data_len;

struct QUIC_init {
	QUIC_START_FIELDS
	u8 DCID_len;
	u8 DCID[8];
	u8 SCID_len;
	u8 SCID[3];
	QUIC_END_FIELDS
} __attribute__((packed));

struct QUIC_resp {
	QUIC_START_FIELDS
	u8 DCID_len;
	u8 DCID[3];
	u8 SCID_len;
	u8 SCID[3];
	QUIC_END_FIELDS
} __attribute__((packed));

struct QUIC_cook {
	QUIC_START_FIELDS
	u8 DCID_len;
	u8 DCID[3];
	u8 SCID_len;
	QUIC_END_FIELDS
} __attribute__((packed));

struct QUIC_data {
	u8 flags;
	u8 DCID[3];
} __attribute__((packed));

#define HIDDEN_NOIZE 31
#define HIDDEN_HS_LEN (sizeof(struct QUIC_init) + HIDDEN_NOIZE)
#define	ERROR_HIDDEN_LEN 0xFFFF

#endif 