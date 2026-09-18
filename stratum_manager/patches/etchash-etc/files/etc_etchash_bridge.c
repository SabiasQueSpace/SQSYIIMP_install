#include "etc_etchash_bridge.h"

/*
 * Reuse the already-vendored classic Ethash implementation used by VBC,
 * but construct the verification cache with the ECIP-1099 epoch/seed rules.
 *
 * ECIP-1099 (ETC mainnet):
 *   - before block 11,700,000: epoch = block / 30,000
 *   - from block 11,700,000:  epoch = block / 60,000
 *   - cache/DAG sizes use that recalibrated epoch
 *   - seed generation continues to use the old 30,000-block cadence;
 *     for a post-fork Etchash epoch E the seed boundary is E*60,000 + 1,
 *     therefore the classic seed routine performs 2*E Keccak rounds.
 *
 * The internal libethash API lets us provide cache size, seed and full-DAG
 * size independently. This avoids changing VBC Ethash consensus constants
 * and avoids linking a second library with colliding ethash_* symbols.
 */
#include <libethash/ethash.h>
#include <libethash/internal.h>

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t g_etc_etchash_lock =
    PTHREAD_MUTEX_INITIALIZER;

static ethash_light_t g_etc_etchash_light = NULL;
static uint64_t g_etc_etchash_cache_epoch = UINT64_MAX;
static uint64_t g_etc_etchash_seed_epoch = UINT64_MAX;
static uint64_t g_etc_etchash_full_size = 0;

static int hexval(char c)
{
    if(c >= '0' && c <= '9') return c - '0';
    if(c >= 'a' && c <= 'f') return c - 'a' + 10;
    if(c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int parse_h256(
    const char *hex,
    ethash_h256_t *out)
{
    if(!hex || !out || strlen(hex) != 64)
        return 0;

    for(int i = 0; i < 32; ++i)
    {
        int hi = hexval(hex[i * 2]);
        int lo = hexval(hex[i * 2 + 1]);

        if(hi < 0 || lo < 0)
            return 0;

        out->b[i] =
            (uint8_t)((hi << 4) | lo);
    }

    return 1;
}

static uint64_t etc_etchash_cache_epoch(uint64_t block_number)
{
    if(block_number < ETC_ETCHASH_FORK_BLOCK)
        return block_number / ETC_ETHASH_EPOCH_LENGTH;

    return block_number / ETC_ETCHASH_EPOCH_LENGTH;
}

static uint64_t etc_etchash_seed_epoch(
    uint64_t block_number,
    uint64_t cache_epoch)
{
    if(block_number < ETC_ETCHASH_FORK_BLOCK)
        return cache_epoch;

    /*
     * seedHash(epoch * 60000 + 1) still divides by the old 30000,
     * yielding 2 * epoch on ETC after ECIP-1099.
     */
    return cache_epoch *
        (ETC_ETCHASH_EPOCH_LENGTH / ETC_ETHASH_EPOCH_LENGTH);
}

static int etc_etchash_prepare(uint64_t block_number)
{
    const uint64_t cache_epoch =
        etc_etchash_cache_epoch(block_number);
    const uint64_t seed_epoch =
        etc_etchash_seed_epoch(block_number, cache_epoch);

    if(cache_epoch >= 2048 || seed_epoch >= UINT32_MAX)
        return 0;

    if(g_etc_etchash_light &&
       g_etc_etchash_cache_epoch == cache_epoch &&
       g_etc_etchash_seed_epoch == seed_epoch &&
       g_etc_etchash_full_size != 0)
        return 1;

    /*
     * libethash sizes are indexed by block/30000. A synthetic block at
     * cache_epoch*30000 therefore selects exactly the recalibrated Etchash
     * cache/DAG size while leaving VBC's normal API untouched.
     */
    const uint64_t size_block =
        cache_epoch * ETC_ETHASH_EPOCH_LENGTH;

    /*
     * libethash's seed routine also divides by 30000. Passing
     * seed_epoch*30000 produces the ECIP-1099 seed (2*epoch post-fork).
     */
    const uint64_t seed_block =
        seed_epoch * ETC_ETHASH_EPOCH_LENGTH;

    const uint64_t cache_size =
        ethash_get_cachesize(size_block);
    const uint64_t full_size =
        ethash_get_datasize(size_block);
    const ethash_h256_t seed =
        ethash_get_seedhash(seed_block);

    if(cache_size == 0 || full_size == 0)
        return 0;

    ethash_light_t new_light =
        ethash_light_new_internal(cache_size, &seed);

    if(!new_light)
        return 0;

    if(g_etc_etchash_light)
        ethash_light_delete(g_etc_etchash_light);

    g_etc_etchash_light = new_light;
    g_etc_etchash_cache_epoch = cache_epoch;
    g_etc_etchash_seed_epoch = seed_epoch;
    g_etc_etchash_full_size = full_size;

    return 1;
}

int etc_etchash_official_compute(
    uint64_t block_number,
    const char *header_hash_hex,
    uint64_t nonce,
    unsigned char mix_hash_out[32],
    unsigned char final_hash_out[32])
{
    if(!header_hash_hex ||
       !mix_hash_out ||
       !final_hash_out)
        return 0;

    ethash_h256_t header;

    if(!parse_h256(header_hash_hex, &header))
        return 0;

    pthread_mutex_lock(&g_etc_etchash_lock);

    if(!etc_etchash_prepare(block_number))
    {
        pthread_mutex_unlock(&g_etc_etchash_lock);
        return 0;
    }

    ethash_return_value_t result =
        ethash_light_compute_internal(
            g_etc_etchash_light,
            g_etc_etchash_full_size,
            header,
            nonce);

    if(!result.success)
    {
        pthread_mutex_unlock(&g_etc_etchash_lock);
        return 0;
    }

    memcpy(mix_hash_out, result.mix_hash.b, 32);
    memcpy(final_hash_out, result.result.b, 32);

    pthread_mutex_unlock(&g_etc_etchash_lock);
    return 1;
}

void etc_etchash_official_cleanup(void)
{
    pthread_mutex_lock(&g_etc_etchash_lock);

    if(g_etc_etchash_light)
    {
        ethash_light_delete(g_etc_etchash_light);
        g_etc_etchash_light = NULL;
    }

    g_etc_etchash_cache_epoch = UINT64_MAX;
    g_etc_etchash_seed_epoch = UINT64_MAX;
    g_etc_etchash_full_size = 0;

    pthread_mutex_unlock(&g_etc_etchash_lock);
}
