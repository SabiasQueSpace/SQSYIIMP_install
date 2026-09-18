#include <kawpow/include/ethash/ethash.hpp>
#include <kawpow/include/ethash/keccak.hpp>
#include <kawpow/lib/ethash/bit_manipulation.h>
#include <kawpow/lib/ethash/endianness.hpp>

// Include C++ standard-library headers before stratum.h. The legacy YiiMP
// util.h pulled by stratum.h defines function-like min/max macros, which
// otherwise expand inside <mutex>/<chrono> and break the C++ standard headers.
// Keeping this workaround local avoids changing macros used by other algos.
#include <climits>
#include <memory>
#include <mutex>
#include <strings.h>

#include "stratum.h"
#include "vbc_ethash_bridge.h"
#include "etc_etchash_bridge.h"

// The bundled ethash primitives are shared with KAWPOW and use KAWPOW's
// 512 dataset parents. VirBiCoin uses classic Ethash (256 parents), so the
// share verifier below intentionally reuses only the generated light cache
// and implements the classic Ethash hashimoto-light path locally. This keeps
// KAWPOW's consensus constants untouched.
static const char *skip_0x(const char *s)
{
    if(s && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) return s + 2;
    return s;
}

static bool ethash_is_hex(const char *s, size_t len)
{
    if(!s || strlen(s) != len) return false;
    for(size_t i = 0; i < len; ++i)
    {
        const unsigned char c = (unsigned char)s[i];
        if(!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            return false;
    }
    return true;
}

static bool ethash_hex64(const char *s)
{
    if(!s) return false;
    s = skip_0x(s);
    return ethash_is_hex(s, 64);
}

static bool ethash_hex_to_hash256(const char *hex, ethash::hash256& out)
{
    if(!ethash_hex64(hex)) return false;
    hex = skip_0x(hex);

    for(size_t i = 0; i < 32; ++i)
    {
        char byte_hex[3] = { hex[i * 2], hex[i * 2 + 1], 0 };
        out.bytes[i] = (uint8_t)strtoul(byte_hex, NULL, 16);
    }
    return true;
}

static bool ethash_hash_leq_hex_target(const ethash::hash256& hash, const char *target_hex)
{
    ethash::hash256 target = {};
    if(!ethash_hex_to_hash256(target_hex, target)) return false;

    for(size_t i = 0; i < 32; ++i)
    {
        if(hash.bytes[i] < target.bytes[i]) return true;
        if(hash.bytes[i] > target.bytes[i]) return false;
    }
    return true;
}

static std::string ethash_hash_hex(const ethash::hash256& hash)
{
    static const char lut[] = "0123456789abcdef";
    std::string out(64, '0');
    for(size_t i = 0; i < 32; ++i)
    {
        out[i * 2] = lut[(hash.bytes[i] >> 4) & 0x0f];
        out[i * 2 + 1] = lut[hash.bytes[i] & 0x0f];
    }
    return out;
}

static bool ethash_parse_quantity(const char *value, uint64_t& out)
{
    if(!value || !*value) return false;
    const char *p = skip_0x(value);
    if(!*p) return false;

    char *end = NULL;
    errno = 0;
    unsigned long long n = strtoull(p, &end, 16);
    if(errno == ERANGE || !end || *end != '\0') return false;
    out = (uint64_t)n;
    return true;
}

bool ethash_validate_address(const char *address)
{
    if(!address) return false;
    if(strlen(address) != 42) return false;
    if(address[0] != '0' || (address[1] != 'x' && address[1] != 'X')) return false;
    return ethash_is_hex(address + 2, 40);
}

bool ethash_verify_master_wallet(YAAMP_COIND *coind)
{
    if(!coind || !ethash_validate_address(coind->wallet)) return false;

    json_value *json = rpc_call(&coind->rpc, "eth_coinbase", "[]", coind);
    if(!json) return false;

    json_value *result = json_get_object(json, "result");
    bool ok = result && result->type == json_string && result->u.string.ptr &&
        ethash_validate_address(result->u.string.ptr) &&
        !strcasecmp(result->u.string.ptr, coind->wallet);

    if(!ok)
    {
        const char *reported = (result && result->type == json_string && result->u.string.ptr)
            ? result->u.string.ptr : "(unavailable)";
        stratumlog("SECURITY STOP %s: eth_coinbase=%s does not match master_wallet=%s.\n",
            coind->symbol, reported, coind->wallet);
    }

    json_value_free(json);
    return ok;
}

static int ethash_get_work_height(YAAMP_COIND *coind)
{
    json_value *json = rpc_call(&coind->rpc, "eth_getBlockByNumber", "[\"pending\",false]", coind);
    if(json)
    {
        json_value *result = json_get_object(json, "result");
        const char *number = result && result->type == json_object ? json_get_string(result, "number") : NULL;
        uint64_t height = 0;
        if(ethash_parse_quantity(number, height) && height <= INT_MAX)
        {
            json_value_free(json);
            return (int)height;
        }
        json_value_free(json);
    }

    json = rpc_call(&coind->rpc, "eth_blockNumber", "[]", coind);
    if(!json) return 0;

    json_value *result = json_get_object(json, "result");
    uint64_t height = 0;
    bool ok = result && result->type == json_string &&
        ethash_parse_quantity(result->u.string.ptr, height) && height < INT_MAX;
    json_value_free(json);
    return ok ? (int)height + 1 : 0;
}

YAAMP_JOB_TEMPLATE *ethash_create_worktemplate(YAAMP_COIND *coind)
{
    json_value *json = rpc_call(&coind->rpc, "eth_getWork", "[]", coind);
    if(!json || json_is_null(json))
    {
        if(json) json_value_free(json);
        return NULL;
    }

    json_value *result = json_get_object(json, "result");
    if(!result || result->type != json_array || result->u.array.length < 3)
    {
        json_value_free(json);
        return NULL;
    }

    json_value *powhash = result->u.array.values[0];
    json_value *seedhash = result->u.array.values[1];
    json_value *target = result->u.array.values[2];

    if(!powhash || !seedhash || !target ||
        powhash->type != json_string || seedhash->type != json_string || target->type != json_string ||
        !ethash_hex64(powhash->u.string.ptr) || !ethash_hex64(seedhash->u.string.ptr) || !ethash_hex64(target->u.string.ptr))
    {
        json_value_free(json);
        return NULL;
    }

    // Gvbc extends eth_getWork with a fourth JSON-RPC quantity containing
    // the exact block number for its Ethash work package. Keep that behavior
    // for the existing Ethash/VBC path.
    //
    // Core-Geth can also return a fourth value while the ETC node is syncing;
    // it is not reliable as the pending mining height in that state (we have
    // observed 0x1 while eth_blockNumber was already much higher). Etchash
    // therefore resolves the pending/latest height through the daemon instead
    // of trusting result[3]. This also keeps the ECIP-1099 fork/epoch decision
    // tied to the canonical node height.
    int height = 0;
    if(!is_etchash && result->u.array.length >= 4)
    {
        json_value *block_number = result->u.array.values[3];
        uint64_t work_height = 0;
        if(block_number && block_number->type == json_string &&
            ethash_parse_quantity(block_number->u.string.ptr, work_height) &&
            work_height > 0 && work_height <= INT_MAX)
        {
            height = (int)work_height;
        }
    }

    if(height <= 0)
        height = ethash_get_work_height(coind);

    if(height <= 0)
    {
        json_value_free(json);
        return NULL;
    }

    YAAMP_JOB_TEMPLATE *templ = new YAAMP_JOB_TEMPLATE;
    memset(templ, 0, sizeof(YAAMP_JOB_TEMPLATE));
    templ->created = time(NULL);
    templ->height = height;
    snprintf(templ->ntime, sizeof(templ->ntime), "%08x", (unsigned int)templ->created);
    snprintf(templ->ethash_powhash, sizeof(templ->ethash_powhash), "%s", skip_0x(powhash->u.string.ptr));
    snprintf(templ->ethash_seedhash, sizeof(templ->ethash_seedhash), "%s", skip_0x(seedhash->u.string.ptr));
    snprintf(templ->ethash_target, sizeof(templ->ethash_target), "%s", skip_0x(target->u.string.ptr));

    ethash::hash256 seed = {};
    if(!ethash_hex_to_hash256(templ->ethash_seedhash, seed))
    {
        delete templ;
        json_value_free(json);
        return NULL;
    }

    templ->ethash_epoch = ethash::find_epoch_number(seed);
    if(templ->ethash_epoch < 0)
    {
        stratumlog("%s unable to resolve Ethash epoch from seed %s\n",
            coind->symbol, templ->ethash_seedhash);
        delete templ;
        json_value_free(json);
        return NULL;
    }

    json_value_free(json);
    return templ;
}


/*
 * MHP_ETHASH_ETHV1_SUBSCRIBE_V1
 *
 * Native EthereumStratum/1.0.0 subscription.
 *
 * params[0] = actual miner software/version
 * params[1] = EthereumStratum/1.0.0
 *
 * Never infer a software name: store exactly what the miner sends.
 */
bool ethash_client_subscribe_v1(
    YAAMP_CLIENT *client,
    json_value *json_params)
{
    if(!client ||
        !json_params ||
        json_params->type != json_array ||
        json_params->u.array.length < 2 ||
        !json_is_string(json_params->u.array.values[0]) ||
        !json_is_string(json_params->u.array.values[1]) ||
        !json_params->u.array.values[0]->u.string.ptr ||
        !json_params->u.array.values[1]->u.string.ptr)
    {
        if(client)
            client_send_error(
                client,
                20,
                "Malformed EthereumStratum subscribe");

        return true;
    }

    const char *miner =
        json_params->u.array.values[0]->u.string.ptr;

    const char *protocol =
        json_params->u.array.values[1]->u.string.ptr;

    if(strcasecmp(
            protocol,
            "EthereumStratum/1.0.0"))
    {
        client_send_error(
            client,
            20,
            "Unsupported EthereumStratum version");

        return true;
    }

    client->eth_protocol =
        ETH_PROTOCOL_ETHV1;

    strncpy(
        client->version,
        miner,
        sizeof(client->version) - 1);

    client->version[
        sizeof(client->version) - 1] = '\0';

    get_random_key(client->notify_id);

    get_next_ethash_extraonce1(
        client->extranonce1_default);

    strncpy(
        client->extranonce1,
        client->extranonce1_default,
        sizeof(client->extranonce1) - 1);

    client->extranonce1[
        sizeof(client->extranonce1) - 1] = '\0';

    strncpy(
        client->extranonce1_last,
        client->extranonce1_default,
        sizeof(client->extranonce1_last) - 1);

    client->extranonce1_last[
        sizeof(client->extranonce1_last) - 1] = '\0';

    /*
     * EthereumStratum V1 does not use Bitcoin-style extranonce2.
     * The miner receives a prefix and supplies the remaining
     * bytes of the 64-bit Ethereum nonce in mining.submit.
     */
    client->extranonce2size = 0;
    client->extranonce2size_default = 0;
    client->extranonce2size_last = 0;

    stratumlog(
        "ETHASH_PROTOCOL protocol=ETHV1 "
        "software=%s extranonce=%s ip=%s\n",
        client->version[0]
            ? client->version
            : "unknown",
        client->extranonce1,
        client->sock && client->sock->ip
            ? client->sock->ip
            : "unknown");

    /*
     * Spec:
     * result = [
     *   ["mining.notify", subscription_id,
     *    "EthereumStratum/1.0.0"],
     *   extranonce
     * ]
     */
    return client_send_result(
        client,
        "[[\"mining.notify\",\"%s\","
        "\"EthereumStratum/1.0.0\"],\"%s\"]",
        client->notify_id,
        client->extranonce1) != -1;
}

void ethash_job_mining_notify_buffer(
    YAAMP_JOB *job,
    YAAMP_CLIENT *client,
    char *buffer,
    size_t buffer_size)
{
    if(!job ||
        !job->templ ||
        !client ||
        !buffer ||
        !buffer_size)
        return;

    /*
     * MHP_ETHASH_PROTOCOL_V1
     *
     * ETHV1 uses:
     * [jobid, seedhash, headerhash, cleanjobs]
     *
     * ETHPROXY keeps the existing GetWork-compatible payload.
     */
    if(client->eth_protocol == ETH_PROTOCOL_ETHV1)
    {
        snprintf(
            buffer,
            buffer_size,
            "{\"id\":null,\"method\":\"mining.notify\","
            "\"params\":[\"%x\",\"%s\",\"%s\",true]}\n",
            job->id,
            job->templ->ethash_seedhash,
            job->templ->ethash_powhash);

        return;
    }

    snprintf(
        buffer,
        buffer_size,
        "{\"jsonrpc\":\"2.0\","
        "\"result\":[\"0x%s\",\"0x%s\",\"0x%s\"]}\n",
        job->templ->ethash_powhash,
        job->templ->ethash_seedhash,
        client->share_target.ToString().c_str());
}

static YAAMP_JOB *ethash_find_job_by_powhash(const char *powhash)
{
    if(!powhash) return NULL;
    powhash = skip_0x(powhash);

    YAAMP_JOB *found = NULL;
    g_list_job.Enter();
    for(CLI li = g_list_job.first; li; li = li->next)
    {
        YAAMP_JOB *job = (YAAMP_JOB *)li->data;
        if(!job || !job->templ || !job->coind) continue;

        if(!strcasecmp(job->templ->ethash_powhash, powhash))
        {
            stratumlog(
                "ETHASH_JOB_LOOKUP powhash=%s job=%d deleted=%d "
                "templ_height=%d coind_height=%d status=%d age=%lld\n",
                powhash,
                job->id,
                job->deleted ? 1 : 0,
                job->templ->height,
                job->coind->height,
                job->status,
                (long long)(time(NULL) - job->jobage));

            if(job->deleted)
                continue;

            object_lock(job);
            found = job;
            break;
        }
    }
    g_list_job.Leave();
    return found;
}

bool ethash_client_getwork(YAAMP_CLIENT *client)
{
    if(!client || !g_list_client.Find(client))
    {
        if(client) client_send_error(client, 25, "Not subscribed");
        return true;
    }

    YAAMP_JOB *job = NULL;
    if(client->jobid_next)
        job = (YAAMP_JOB *)object_find(&g_list_job, client->jobid_next, true);
    if(!job && client->jobid_sent)
        job = (YAAMP_JOB *)object_find(&g_list_job, client->jobid_sent, true);

    if(!job || !job->templ)
    {
        if(job) object_unlock(job);
        client_send_error(client, 0, "Work not ready");
        return true;
    }

    int ret = socket_send(client->sock,
        "{\"id\":%d,\"jsonrpc\":\"2.0\",\"result\":[\"0x%s\",\"0x%s\",\"0x%s\"]}\n",
        client->id_int,
        job->templ->ethash_powhash,
        job->templ->ethash_seedhash,
        client->share_target.ToString().c_str());

    object_unlock(job);
    return ret != -1;
}

static bool ethash_submit_work(YAAMP_COIND *coind, const char *nonce, const char *powhash, const char *mixhash)
{
    char params[512];
    int len = snprintf(params, sizeof(params), "[\"0x%s\",\"0x%s\",\"0x%s\"]", nonce, powhash, mixhash);
    if(len < 0 || (size_t)len >= sizeof(params)) return false;

    const long long started = current_timestamp();
    json_value *json = rpc_call(&coind->rpc, "eth_submitWork", params, coind);
    bool accepted = false;
    if(json)
    {
        json_value *result = json_get_object(json, "result");
        accepted = result && result->type == json_boolean && result->u.boolean;
        json_value_free(json);
    }
    kawpow_health_submit_record(coind, current_timestamp() - started, accepted);
    return accepted;
}

static bool ethash_address_equal(const char *a, const char *b)
{
    a = skip_0x(a);
    b = skip_0x(b);

    if(!a || !b)
        return false;

    if(strlen(a) != 40 || strlen(b) != 40)
        return false;

    for(size_t i = 0; i < 40; ++i)
    {
        char ca = a[i];
        char cb = b[i];

        if(ca >= 'A' && ca <= 'F')
            ca = (char)(ca - 'A' + 'a');

        if(cb >= 'A' && cb <= 'F')
            cb = (char)(cb - 'A' + 'a');

        if(ca != cb)
            return false;
    }

    return true;
}

static bool ethash_get_accepted_block(YAAMP_COIND *coind, int expected_height, std::string& block_hash)
{
    /*
     * Query the exact height instead of "latest".
     *
     * Ethash chains can advance before we query the daemon after
     * eth_submitWork. Asking for the exact height avoids losing an
     * accepted block simply because another block arrived meanwhile.
     *
     * This runs only for a network candidate, so a short retry window
     * has negligible impact on normal share processing.
     */
    char params[96];
    snprintf(params, sizeof(params), "[\"0x%x\",false]", expected_height);

    for(int attempt = 0; attempt < 20; ++attempt)
    {
        json_value *json = rpc_call(
            &coind->rpc,
            "eth_getBlockByNumber",
            params,
            coind);

        if(json)
        {
            json_value *result = json_get_object(json, "result");

            const char *number =
                result && result->type == json_object
                ? json_get_string(result, "number")
                : NULL;

            const char *hash =
                result && result->type == json_object
                ? json_get_string(result, "hash")
                : NULL;

            const char *miner =
                result && result->type == json_object
                ? json_get_string(result, "miner")
                : NULL;

            uint64_t height = 0;

            if(hash &&
                ethash_parse_quantity(number, height) &&
                (int)height == expected_height)
            {
                /*
                 * eth_submitWork=true alone is not enough to attribute
                 * the canonical block to this pool. Another block may
                 * have won the same height before our follow-up RPC.
                 *
                 * Only persist it when the canonical block miner is
                 * exactly the configured and verified master_wallet.
                 */
                if(!miner ||
                    !coind->wallet ||
                    !ethash_address_equal(miner, coind->wallet))
                {
                    stratumlog(
                        "ETHASH_BLOCK_CANONICAL_MISMATCH "
                        "coin=%s height=%d "
                        "expected_miner=%s chain_miner=%s "
                        "blockhash=%s\n",
                        coind->symbol,
                        expected_height,
                        coind->wallet ? coind->wallet : "",
                        miner ? miner : "",
                        hash ? hash : "");

                    json_value_free(json);
                    return false;
                }

                block_hash = skip_0x(hash);

                if(g_debuglog_verbose)
                    stratumlog(
                        "ETHASH_BLOCK_CANONICAL_MATCH "
                        "coin=%s height=%d miner=%s "
                        "blockhash=%s\n",
                        coind->symbol,
                        expected_height,
                        miner,
                        block_hash.c_str());

                json_value_free(json);
                return true;
            }

            json_value_free(json);
        }

        usleep(100 * YAAMP_MS);
    }

    return false;
}

bool ethash_client_submit(YAAMP_CLIENT *client, json_value *json_params)
{
    if(!client || !json_params || json_params->type != json_array ||
        json_params->u.array.length < 3 || !valid_string_params(json_params))
    {
        if(client) client_send_error(client, -1, "Malformed PoW result");
        return true;
    }

    /*
     * MHP_ETHASH_ETHV1_SUBMIT_V2
     *
     * ETHPROXY:
     *   [nonce, powhash, mixhash]
     *
     * EthereumStratum/1.0.0:
     *   [username, jobid, minernonce]
     */
    const char *nonce_src = NULL;
    const char *powhash_src = NULL;
    const char *mixhash_src = NULL;

    char ethv1_nonce[17] = { 0 };
    char ethv1_powhash[65] = { 0 };

    if(client->eth_protocol == ETH_PROTOCOL_ETHV1)
    {
        const char *jobid_src =
            skip_0x(
                json_params->u.array.values[1]
                    ->u.string.ptr);

        const char *minernonce_src =
            skip_0x(
                json_params->u.array.values[2]
                    ->u.string.ptr);

        size_t jobid_len =
            jobid_src ? strlen(jobid_src) : 0;

        if(jobid_len == 0 ||
            jobid_len > 8 ||
            !ethash_is_hex(jobid_src, jobid_len))
        {
            client_send_error(
                client,
                21,
                "Invalid job id");

            client->submit_bad++;
            return true;
        }

        char *jobid_end = NULL;

        unsigned long parsed_jobid =
            strtoul(
                jobid_src,
                &jobid_end,
                16);

        if(!jobid_end ||
            *jobid_end != '\0' ||
            parsed_jobid == 0 ||
            parsed_jobid > 0x7fffffffUL)
        {
            client_send_error(
                client,
                21,
                "Invalid job id");

            client->submit_bad++;
            return true;
        }

        int jobid = (int)parsed_jobid;

        /*
         * Only accept a job actually sent to this connection.
         */
        if(!client_find_job_history(
                client,
                jobid,
                0))
        {
            stratumlog(
                "ETHASH_ETHV1_REJECT "
                "user=%s worker=%s job=%x "
                "reason=job_not_sent_to_client\n",
                client->username,
                client_worker_log_label(client),
                jobid);

            client_send_error(
                client,
                21,
                "Invalid job id");

            client->submit_bad++;
            return true;
        }

        /*
         * 3-byte pool extranonce + 5-byte miner nonce
         * = 8-byte Ethash nonce.
         */
        if(strlen(client->extranonce1) != 6 ||
            !ethash_is_hex(client->extranonce1, 6) ||
            !minernonce_src ||
            strlen(minernonce_src) != 10 ||
            !ethash_is_hex(minernonce_src, 10))
        {
            client_send_error(
                client,
                20,
                "Invalid EthereumStratum nonce");

            client->submit_bad++;
            return true;
        }

        YAAMP_JOB *ethv1_job =
            (YAAMP_JOB *)object_find(
                &g_list_job,
                jobid,
                true);

        if(!ethv1_job ||
            ethv1_job->deleted ||
            !ethv1_job->templ ||
            !ethv1_job->coind)
        {
            if(ethv1_job)
                object_unlock(ethv1_job);

            client_send_error(
                client,
                21,
                "Invalid job id");

            client->submit_bad++;
            return true;
        }

        snprintf(
            ethv1_powhash,
            sizeof(ethv1_powhash),
            "%s",
            ethv1_job->templ->ethash_powhash);

        object_unlock(ethv1_job);

        int nonce_len =
            snprintf(
                ethv1_nonce,
                sizeof(ethv1_nonce),
                "%s%s",
                client->extranonce1,
                minernonce_src);

        if(nonce_len != 16)
        {
            client_send_error(
                client,
                20,
                "Invalid EthereumStratum nonce");

            client->submit_bad++;
            return true;
        }

        nonce_src = ethv1_nonce;
        powhash_src = ethv1_powhash;

        /*
         * ETHV1 does not supply mixhash.
         * It is calculated by the pool below.
         */
        mixhash_src = NULL;

        if(g_debuglog_verbose)
        {
            stratumlog(
                "ETHASH_ETHV1_SUBMIT "
                "user=%s worker=%s "
                "job=%x extranonce=%s "
                "minernonce=%s nonce=%s "
                "powhash=%s\n",
                client->username,
                client_worker_log_label(client),
                jobid,
                client->extranonce1,
                minernonce_src,
                nonce_src,
                powhash_src);
        }
    }
    else
    {
        /*
         * Existing ETHPROXY path.
         */
        nonce_src =
            skip_0x(
                json_params->u.array.values[0]
                    ->u.string.ptr);

        powhash_src =
            skip_0x(
                json_params->u.array.values[1]
                    ->u.string.ptr);

        mixhash_src =
            skip_0x(
                json_params->u.array.values[2]
                    ->u.string.ptr);
    }

    if(!nonce_src ||
        strlen(nonce_src) != 16 ||
        !ethash_is_hex(nonce_src, 16) ||
        !ethash_hex64(powhash_src) ||
        (mixhash_src && !ethash_hex64(mixhash_src)))
    {
        client_send_error(
            client,
            20,
            is_etchash ? "Malformed Etchash PoW result" : "Malformed Ethash PoW result");

        client->submit_bad++;
        return true;
    }

    YAAMP_JOB *job = ethash_find_job_by_powhash(powhash_src);
    if(!job)
    {
        stratumlog(
            "ETHASH_SHARE_REJECT user=%s worker=%s powhash=%s "
            "reason=job_not_found\n",
            client->username,
            client_worker_log_label(client),
            powhash_src);

        client_send_error(client, 21, "Invalid job id");
        client->submit_bad++;
        return true;
    }

    YAAMP_JOB_TEMPLATE *templ = job->templ;
    YAAMP_SHARE *duplicate = share_find(job->id, templ->ethash_powhash, templ->ntime,
        (char *)nonce_src, client->extranonce1);
    if(duplicate)
    {
        client_submit_error(client, job, 22, "Duplicate share",
            templ->ethash_powhash, templ->ntime, (char *)nonce_src);
        return true;
    }

    ethash::hash256 submitted_mix = {};

    if(mixhash_src)
    {
        if(!ethash_hex_to_hash256(
                mixhash_src,
                submitted_mix))
        {
            client_submit_error(
                client,
                job,
                20,
                is_etchash ? "Invalid Etchash work" : "Invalid Ethash work",
                templ->ethash_powhash,
                templ->ntime,
                (char *)nonce_src);

            return true;
        }
    }

    uint64_t nonce =
        strtoull(nonce_src, NULL, 16);

    unsigned char official_mix[32] = {};
    unsigned char official_final[32] = {};

    const bool pow_verified = is_etchash
        ? etc_etchash_official_compute(
            (uint64_t)templ->height,
            templ->ethash_powhash,
            nonce,
            official_mix,
            official_final)
        : vbc_ethash_official_compute(
            (uint64_t)templ->height,
            templ->ethash_powhash,
            nonce,
            official_mix,
            official_final);

    if(!pow_verified)
    {
        client_submit_error(
            client,
            job,
            20,
            is_etchash
                ? "ETC Etchash verification unavailable"
                : "VBC Ethash verification unavailable",
            templ->ethash_powhash,
            templ->ntime,
            (char *)nonce_src);

        return true;
    }

    ethash::result result = {};

    memcpy(
        result.mix_hash.bytes,
        official_mix,
        32);

    memcpy(
        result.final_hash.bytes,
        official_final,
        32);

    std::string calculated_mix =
        ethash_hash_hex(
            result.mix_hash);

    /*
     * ETHPROXY must match its submitted mixhash.
     * ETHV1 uses the officially calculated mixhash.
     */
    if(mixhash_src &&
        memcmp(
            result.mix_hash.bytes,
            submitted_mix.bytes,
            32) != 0)
    {
        if(g_debuglog_verbose)
        {
            stratumlog(
                "ETHASH_MIX_REJECT job=%d "
                "height=%d nonce=%s "
                "powhash=%s submitted=%s "
                "official=%s\n",
                job->id,
                templ->height,
                nonce_src,
                templ->ethash_powhash,
                mixhash_src,
                calculated_mix.c_str());
        }

        client_submit_error(
            client,
            job,
            20,
            "Invalid mixhash",
            templ->ethash_powhash,
            templ->ntime,
            (char *)nonce_src);

        return true;
    }

    const char *effective_mixhash =
        mixhash_src
            ? mixhash_src
            : calculated_mix.c_str();

    std::string share_target_hex = client->share_target.ToString();
    if(!ethash_hash_leq_hex_target(result.final_hash, share_target_hex.c_str()))
    {
        client_submit_error(client, job, 26, "Low difficulty share",
            templ->ethash_powhash, templ->ntime, (char *)nonce_src);
        return true;
    }

    std::string final_hash_hex = ethash_hash_hex(result.final_hash);
    uint256 final_hash = uint256S(final_hash_hex);
    double share_diff = target_to_diff(final_hash);

    bool network_candidate = ethash_hash_leq_hex_target(result.final_hash, templ->ethash_target);
    if(network_candidate && !job->block_found)
    {
        const long long detected_ms = current_timestamp();
        YAAMP_COIND *coind = job->coind;
        if(g_debuglog_verbose)
            stratumlog("BLOCK_CANDIDATE coin=%s height=%d user=%s worker=%s job=%d hash=%s detected_ms=%lld protocol=ethash\n",
                coind->symbol, templ->height, client->username, client_worker_log_label(client),
                job->id, final_hash_hex.c_str(), detected_ms);

        bool accepted = ethash_submit_work(coind, nonce_src, templ->ethash_powhash, effective_mixhash);
        if(accepted)
        {
            std::string block_hash;
            bool chain_block_found =
                ethash_get_accepted_block(
                    coind,
                    templ->height,
                    block_hash);

            /*
             * eth_submitWork=true means the daemon accepted the solution,
             * but YiiMP block_prune() requires block_confirm() before the
             * YAAMP_BLOCK is persisted to MySQL.
             *
             * Confirm only when the canonical block hash was obtained
             * from the daemon. Never persist final_hash as a fake
             * Ethereum block hash.
             */
            job->block_found = true;

            blocklog("*** ACCEPTED %s %d by %s (id: %d) [ETHASH] ***\n",
                coind->name,
                templ->height,
                client->sock->ip,
                client->userid);

            /*
             * MHP_ETHASH_ACCEPTED_CANDIDATE_V2
             *
             * Persist every candidate accepted by eth_submitWork.
             *
             * It may ultimately become:
             * - canonical block
             * - uncle
             * - real orphan
             *
             * Do not require immediate canonical ownership here.
             */
            block_add_ethash_candidate(
                client->userid,
                client->workerid,
                coind->id,
                templ->height,
                coind->difficulty,
                share_diff,
                powhash_src,
                nonce_src,
                effective_mixhash,
                final_hash_hex.c_str(),
                (chain_block_found && !block_hash.empty())
                    ? block_hash.c_str()
                    : "",
                client->solo);

            stratumlog(
                "ETHASH_BLOCK_RECORD coin=%s height=%d "
                "persisted_candidate=1 canonical_now=%d "
                "blockhash=%s pow_hash=%s nonce=%s "
                "mix_hash=%s candidate_hash=%s\n",
                coind->symbol,
                templ->height,
                chain_block_found ? 1 : 0,
                block_hash.c_str(),
                powhash_src,
                nonce_src,
                effective_mixhash,
                final_hash_hex.c_str());

            if(g_debuglog_verbose)
                stratumlog("BLOCK_CANDIDATE_RESULT coin=%s height=%d user=%s worker=%s job=%d accepted=1 total_ms=%lld protocol=ethash\n",
                    coind->symbol, templ->height, client->username, client_worker_log_label(client),
                    job->id, current_timestamp() - detected_ms);
            job_signal();
        }
        else if(g_debuglog_verbose)
        {
            stratumlog("BLOCK_CANDIDATE_RESULT coin=%s height=%d user=%s worker=%s job=%d accepted=0 total_ms=%lld protocol=ethash\n",
                coind->symbol, templ->height, client->username, client_worker_log_label(client),
                job->id, current_timestamp() - detected_ms);
        }
    }

    client_send_result(client, "true");
    client_record_difficulty(client);
    client->submit_bad = 0;
    client->shares++;
    client->session_shares_accepted++;
    if(share_diff > client->best_share_diff) client->best_share_diff = share_diff;

    share_add(client, job, true, templ->ethash_powhash, templ->ntime,
        (char *)nonce_src, share_diff, 0, templ->height);

    stratumlog(
        "ETHASH_SHARE_ACCEPT coin=%s height=%d job=%d "
        "user=%s worker=%s nonce=%s "
        "share_diff=%.8f network_candidate=%d hash=%s\n",
        job->coind->symbol,
        templ->height,
        job->id,
        client->username,
        client_worker_log_label(client),
        nonce_src,
        share_diff,
        network_candidate ? 1 : 0,
        final_hash_hex.c_str());

    object_unlock(job);
    return true;
}
