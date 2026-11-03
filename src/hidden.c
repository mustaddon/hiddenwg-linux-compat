#include "hidden.h"
#include "messages.h"
#include "peerlookup.h"


#define XOR_HEAD(skb, mask) ((u8 *)(skb))[0]=(((u8 *)(skb))[0]&0xF0)|((((u8 *)(skb))[0]^((u8 *)(mask))[3])&0x0F)
#define MASK_HLEN(val, mask) ((val)^((u8 *)(mask))[7])
#define SKB_HLEN(skb, qlen, mask) ((((u8 *)(skb))[0]&1) == 0 ? qlen : qlen + MASK_HLEN(((u8 *)(skb))[qlen], mask))


static void xor_mac2(void *skb, size_t len, u32 zero, u32 *mask)
{
    u32 *ptr = (u32 *)((u8 *)skb + len - 16);
    ptr[0] ^= zero^mask[4];
    ptr[1] ^= zero^mask[5];
    ptr[2] ^= zero^mask[6];
    ptr[3] ^= zero^mask[7];
}

static void xor_init(void *skb, u32 *mask)
{
    u32 *ptr = (u32 *)(skb);
    u32 zero = ptr[0]^mask[0];
    ptr[1] ^= zero^mask[1];
    xor_mac2(skb, sizeof(struct message_handshake_initiation), zero, mask);
}

static void xor_resp(void *skb, u32 *mask)
{
    u32 *ptr = (u32 *)(skb);
    u32 zero = ptr[0]^mask[0];
    ptr[1] ^= zero^mask[1];
    ptr[2] ^= zero^mask[2];
    xor_mac2(skb, sizeof(struct message_handshake_response), zero, mask);
}

static void xor_cook(void *skb, u32 *mask)
{
    u32 *ptr = (u32 *)(skb);
    u32 zero = ptr[0]^mask[0];
    ptr[1] ^= zero^mask[1];
}

static void xor_data(void *skb, u32 *mask)
{
    u32 *ptr = (u32 *)(skb);
    u32 zero = ptr[0]^mask[0];
    ptr[1] ^= zero^mask[1];
    ptr[2] ^= zero^mask[2];
    ptr[3] ^= zero^mask[3];
}

size_t prepare_skb_hidden(struct sk_buff *skb, struct wg_device *wg) 
{
    int type;
    size_t hlen = 0;

    if (unlikely(!pskb_may_pull(skb, 32)))
        return ERROR_HIDDEN_LEN;

    XOR_HEAD(skb->data, wg->static_identity.static_public);
    
    if (likely((((u8 *)(skb->data))[0] & 0x80) == 0))
    {
        type = MESSAGE_DATA;

        if (unlikely(((u8 *)(skb->data))[0] & 1))
        {
            hlen = SKB_HLEN(skb->data, sizeof(struct QUIC_data), wg->static_identity.static_public);
            if (unlikely(!pskb_may_pull(skb, hlen)))
                return ERROR_HIDDEN_LEN;
            skb_pull(skb, hlen);
        }

        if (unlikely(!pskb_may_pull(skb, sizeof(struct message_data))))
            return ERROR_HIDDEN_LEN;
        xor_data(skb->data, (u32 *)wg->static_identity.static_public);
    }
    else
    {
        if(((u8 *)(skb->data))[5] != 3)
        {
            hlen = SKB_HLEN(skb->data, sizeof(struct QUIC_init), wg->static_identity.static_public);
            type = MESSAGE_HANDSHAKE_INITIATION;
            if (unlikely(!pskb_may_pull(skb, hlen + sizeof(struct message_handshake_initiation))))
                return ERROR_HIDDEN_LEN;
            skb_pull(skb, hlen);
            xor_init(skb->data, (u32 *)wg->static_identity.static_public);
        }
        else if(((u8 *)(skb->data))[9] != 0)
        {
            hlen = SKB_HLEN(skb->data, sizeof(struct QUIC_resp), wg->static_identity.static_public);
            type = MESSAGE_HANDSHAKE_RESPONSE;
            if (unlikely(!pskb_may_pull(skb, hlen + sizeof(struct message_handshake_response))))
                return ERROR_HIDDEN_LEN;
            skb_pull(skb, hlen);
            xor_resp(skb->data, (u32 *)wg->static_identity.static_public);
        }
        else 
        {
            hlen = SKB_HLEN(skb->data, sizeof(struct QUIC_cook), wg->static_identity.static_public);
            type = MESSAGE_HANDSHAKE_COOKIE;
            if (unlikely(!pskb_may_pull(skb, hlen + sizeof(struct message_handshake_cookie))))
                return ERROR_HIDDEN_LEN;
            skb_pull(skb, hlen);
            xor_cook(skb->data, (u32 *)wg->static_identity.static_public);
        }
    }

    ((__le32 *)(skb->data))[0] = cpu_to_le32(type);

    return hlen;
}

#define QUIC_START(flags) \
    quic->flags = flags; \
    quic->version = cpu_to_be32(1);

#define QUIC_END(data, quic, hlen) \
    quic->token_len = 0; \
    quic->data_len = cpu_to_be16(0x4000 | (sizeof(*data)+hlen));

#define QUIC_HLEN(quic, hlen, mask) \
    if (hlen > 0) { \
        if (hlen > 1) get_random_bytes((u8 *)quic+sizeof(*quic)+1, hlen-1); \
        ((u8 *)quic)[sizeof(*quic)]=MASK_HLEN(hlen, mask); }

static void add_quick_init(
    struct message_handshake_initiation *data, 
    struct QUIC_init *quic,
    u8 flags,
    size_t hlen,
    u8 *mask)
{
    QUIC_START(flags);

    quic->DCID_len = sizeof(quic->DCID);
    get_random_bytes(quic->DCID, sizeof(quic->DCID));

    quic->SCID_len = sizeof(quic->SCID);
    memcpy(quic->SCID, &data->sender_index, sizeof(quic->SCID));

    QUIC_END(data, quic, hlen);
    QUIC_HLEN(quic, hlen, mask);
}

static void add_quick_resp(
    struct message_handshake_response *data, 
    struct QUIC_resp *quic,
    u8 flags,
    size_t hlen,
    u8 *mask)
{
    QUIC_START(flags);

    quic->DCID_len = sizeof(quic->DCID);
    memcpy(quic->DCID, &data->receiver_index, sizeof(quic->DCID));

    quic->SCID_len = sizeof(quic->SCID);
    memcpy(quic->SCID, &data->sender_index, sizeof(quic->SCID));

    QUIC_END(data, quic, hlen);
    QUIC_HLEN(quic, hlen, mask);
}

static void add_quick_cook(
    struct message_handshake_cookie *data, 
    struct QUIC_cook *quic,
    u8 flags,
    size_t hlen,
    u8 *mask)
{
    QUIC_START(flags);

    quic->DCID_len = sizeof(quic->DCID);
    memcpy(quic->DCID, &data->receiver_index, sizeof(quic->DCID));

    quic->SCID_len = 0;

    QUIC_END(data, quic, hlen);
    QUIC_HLEN(quic, hlen, mask);
}

void skb_push_hidden_handshake(void *skb, void *buffer, struct wg_peer *peer)
{
    u8 *quic;
    u8 type = ((u8 *)buffer)[0];
    u8 flags;
    size_t hlen;
    
    get_random_bytes(buffer, sizeof(u32));
    hlen = ((u8 *)buffer)[0]&HIDDEN_NOIZE;
    flags = (hlen>0 ? 0xC1 : 0xC0) | (((u8 *)buffer)[1]&0x0E);
    
    switch (type) {
        case MESSAGE_HANDSHAKE_INITIATION:
            quic = (u8 *)skb_push(skb, sizeof(struct QUIC_init) + hlen);
            add_quick_init(
                (struct message_handshake_initiation *)buffer,
                (struct QUIC_init *)quic, 
                flags, hlen, peer->handshake.remote_static);
            xor_init(buffer, (u32 *)peer->handshake.remote_static);
            break;

        case MESSAGE_HANDSHAKE_RESPONSE:
            quic = (u8 *)skb_push(skb, sizeof(struct QUIC_resp) + hlen);
            add_quick_resp(
                (struct message_handshake_response *)buffer,
                (struct QUIC_resp *)quic, 
                flags, hlen, peer->handshake.remote_static);
            xor_resp(buffer, (u32 *)peer->handshake.remote_static);
            break;

        case MESSAGE_HANDSHAKE_COOKIE:
            quic = (u8 *)skb_push(skb, sizeof(struct QUIC_cook) + hlen);
            add_quick_cook(
                (struct message_handshake_cookie *)buffer,
                (struct QUIC_cook *)quic, 
                flags, hlen, peer->handshake.remote_static);
            xor_cook(buffer, (u32 *)peer->handshake.remote_static);
            break;
    }

    XOR_HEAD(quic, peer->handshake.remote_static);
}

void skb_push_hidden_handshake_cookie(void *skb, void *buffer, struct wg_device *wg)
{
    struct wg_peer *peer = NULL;

	if (unlikely(!wg_index_hashtable_lookup(wg->index_hashtable,
            INDEX_HASHTABLE_HANDSHAKE | INDEX_HASHTABLE_KEYPAIR,
            ((struct message_handshake_cookie *)buffer)->receiver_index, &peer)))
		return;
    
    skb_push_hidden_handshake(skb, buffer, peer);
}

void skb_push_hidden_data(struct sk_buff *skb, struct wg_peer *peer, bool is_keepalive)
{
    u8 *buffer = (u8 *)(skb->data);
    u8 *quic = buffer;
    u8 hlen;

    if (unlikely(!pskb_may_pull(skb, sizeof(struct message_data))))
        return;

    if (likely(!is_keepalive)) 
    {
        quic[0] = (((u8)ktime_get_coarse_boottime_ns())&0x1E) | 0x40;
    }
    else
    {
        hlen = (((u32 *)buffer)[0] = ktime_get_coarse_boottime_ns())&HIDDEN_NOIZE;
        if(!hlen) hlen = 1;
        quic = (u8 *)skb_push(skb, sizeof(struct QUIC_data)+hlen);
        if (hlen > 1) get_random_bytes(quic+sizeof(struct QUIC_data)+1, hlen-1);
        quic[sizeof(struct QUIC_data)] = MASK_HLEN(hlen, peer->handshake.remote_static);
        quic[0] = (((u32 *)buffer)[0]&0x1E) | 0x41;
    }

    memcpy(&quic[1], &((struct message_data *)buffer)->key_idx, 3);
    xor_data(buffer, (u32 *)peer->handshake.remote_static);
    XOR_HEAD(quic, peer->handshake.remote_static);
}
