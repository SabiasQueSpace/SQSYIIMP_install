#ifndef ETC_ETCHASH_BRIDGE_H
#define ETC_ETCHASH_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Ethereum Classic mainnet ECIP-1099 / Thanos activation. */
#define ETC_ETCHASH_FORK_BLOCK 11700000ULL
#define ETC_ETHASH_EPOCH_LENGTH 30000ULL
#define ETC_ETCHASH_EPOCH_LENGTH 60000ULL

int etc_etchash_official_compute(
    uint64_t block_number,
    const char *header_hash_hex,
    uint64_t nonce,
    unsigned char mix_hash_out[32],
    unsigned char final_hash_out[32]);

void etc_etchash_official_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif
