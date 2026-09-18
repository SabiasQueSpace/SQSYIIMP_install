#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "vbc_ethash_bridge.h"
#include "etc_etchash_bridge.h"

static void hex32(const unsigned char x[32], char out[65])
{
    static const char *h = "0123456789abcdef";
    for(int i = 0; i < 32; ++i)
    {
        out[2 * i] = h[x[i] >> 4];
        out[2 * i + 1] = h[x[i] & 15];
    }
    out[64] = 0;
}

int main(void)
{
    /* Known pre-fork Ethash vector from the vendored VBC ethash tests. */
    const char *header =
        "372eca2454ead349c3df0ab5d00b0b706b23e49d469387db91811cee0358fc6d";
    const uint64_t nonce = 0x495732e0ed7a801cULL;
    const char *expected_final =
        "00000b184f1fdd88bfd94c86c39e65db0c36144d5e43f745f722196e730cb614";

    unsigned char vbc_mix[32], vbc_final[32];
    unsigned char etc_mix[32], etc_final[32];
    char vbc_final_hex[65], etc_final_hex[65];

    if(!vbc_ethash_official_compute(22, header, nonce, vbc_mix, vbc_final))
        return 10;
    if(!etc_etchash_official_compute(22, header, nonce, etc_mix, etc_final))
        return 11;

    hex32(vbc_final, vbc_final_hex);
    hex32(etc_final, etc_final_hex);

    const int equal =
        memcmp(vbc_mix, etc_mix, 32) == 0 &&
        memcmp(vbc_final, etc_final, 32) == 0;
    const int known = strcmp(vbc_final_hex, expected_final) == 0;

    printf("VBC final:         %s\n", vbc_final_hex);
    printf("ETC pre-fork:      %s\n", etc_final_hex);
    printf("Pre-fork equal:    %s\n", equal ? "YES" : "NO");
    printf("Known vector:      %s\n", known ? "PASS" : "FAIL");

    vbc_ethash_official_cleanup();
    etc_etchash_official_cleanup();
    return (equal && known) ? 0 : 20;
}
