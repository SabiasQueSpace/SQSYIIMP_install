#include "stratum.h"
#include "algos/sha3x.h"
#include "tari_stratum.h"
#include <signal.h>
#include <sys/resource.h>

#include <string>
#include <vector>

CommonList g_list_coind;
CommonList g_list_client;
CommonList g_list_job;
CommonList g_list_remote;
CommonList g_list_renter;
CommonList g_list_share;
CommonList g_list_worker;
CommonList g_list_block;
CommonList g_list_submit;
CommonList g_list_source;

int g_tcp_port;

char g_tcp_server[1024];
char g_tcp_password[1024];

char g_sql_host[1024];
char g_sql_database[1024];
char g_sql_username[1024];
char g_sql_password[1024];
int g_sql_port = 3306;

char g_server_ip[64] = {0};

char g_stratum_coin_include[256];
char g_stratum_coin_exclude[256];

char g_stratum_algo[256];
double g_stratum_difficulty;
double g_stratum_min_diff;
double g_stratum_max_diff;

double g_stratum_nicehash_difficulty;
double g_stratum_nicehash_min_diff;
double g_stratum_nicehash_max_diff;

double g_stratum_mrr_difficulty;
double g_stratum_mrr_min_diff;
double g_stratum_mrr_max_diff;

int g_stratum_max_ttf;
int g_stratum_max_cons = 5000;
bool g_stratum_reconnect;
bool g_stratum_renting;
bool g_stratum_segwit = false;
bool g_stratum_mweb = false;

int g_limit_txs_per_block = 0;

bool g_handle_haproxy_ips = false;
int g_socket_recv_timeout = 600;

char g_log_directory[1024];
bool g_debuglog_client;
bool g_debuglog_hash;
bool g_debuglog_socket;
bool g_debuglog_rpc;
bool g_debuglog_list;
bool g_debuglog_remote;
bool g_debuglog_verbose;

bool g_autoexchange = true;

uint64_t g_max_shares = 0;
uint64_t g_shares_counter = 0;
uint64_t g_shares_accepted_counter = 0;
uint64_t g_shares_rejected_counter = 0;
uint64_t g_shares_log = 0;
uint64_t g_reject_low_diff_counter = 0;
uint64_t g_reject_stale_counter = 0;
uint64_t g_reject_duplicate_counter = 0;
uint64_t g_reject_invalid_counter = 0;
uint64_t g_reject_other_counter = 0;

int g_observability_rpc_warn_ms = 1000;
int g_observability_rpc_critical_ms = 3000;
int g_observability_rpc_slow_streak = 2;
int g_observability_summary_interval = 300;
bool g_observability_log_shares = true;

// Equihash default
uint32_t g_equihash_wn = EQUIHASH200_9_WN;
uint32_t g_equihash_wk = EQUIHASH200_9_WK;

bool g_allow_rolltime = true;
time_t g_last_broadcasted = 0;
YAAMP_DB *g_db = NULL;

pthread_mutex_t g_db_mutex;
pthread_mutex_t g_nonce1_mutex;
pthread_mutex_t g_context_mutex;
pthread_mutex_t g_job_create_mutex;

struct ifaddrs *g_ifaddr;

volatile bool g_exiting = false;

void *stratum_thread(void *p);
void *monitor_thread(void *p);

bool is_kawpow = false;
bool is_firopow = false;
bool is_phihash = false;
bool is_meowpow = false;
bool is_ethash = false;
bool is_etchash = false;

// MegaHashPool permanent coinbase signature.
// Firma permanente de coinbase de MegaHashPool.
//
// I bless this Stratum in the name of the Father, the Son, and the Holy Spirit.
// Bendigo este Stratum en el nombre del Padre, del Hijo y del Espíritu Santo.
char g_stratum_coinbaseextra[MAX_COINBASE_EXTRA] =
    "JESUSCRISTO MegaHashPool.es";

////////////////////////////////////////////////////////////////////////////////////////

static void scrypt_hash(const char* input, char* output, uint32_t len)
{
	scrypt_1024_1_1_256((unsigned char *)input, (unsigned char *)output);
}

static void scryptn_hash(const char* input, char* output, uint32_t len)
{
	time_t time_table[][2] =
	{
		{2048, 1389306217},
		{4096, 1456415081},
		{8192, 1506746729},
		{16384, 1557078377},
		{32768, 1657741673},
		{65536, 1859068265},
		{131072, 2060394857},
		{262144, 1722307603},
		{524288, 1769642992},
		{0, 0},
	};

	for(int i=0; time_table[i][0]; i++)
		if(time(NULL) < time_table[i+1][1])
		{
			scrypt_N_R_1_256(input, output, time_table[i][0], 1, len);
			return;
		}
}

static void neoscrypt_hash(const char* input, char* output, uint32_t len)
{
	neoscrypt((unsigned char *)input, (unsigned char *)output, 0x80000620);
}

YAAMP_ALGO g_algos[] =
{
	{"0x10", hash0x10, 1, 0, 0},
	{"a5a", a5a_hash, 0x10000, 0, 0},
	{"aergo", aergo_hash, 1, 0, 0},
	{"allium", allium_hash, 0x100, 0, 0},
	{"anime", anime_hash, 1, 0, 0},
	{"argon2d250", argon2d_crds_hash, 0x10000, 0, 0 }, // Credits Argon2d Implementation
	{"argon2d500", argon2d_dyn_hash, 0x10000, 0, 0 }, // Dynamic Argon2d Implementation
	{"argon2d1000", argon2d1000_hash, 0x10000, 0, 0 }, // Argon2d1000 Implementation
	{"argon2d16000", argon2d16000_hash, 0x10000, 0, 0 }, // Argon2d16000 Implementation
	{"astralhash", astralhash_hash, 0x100, 0, 0},
	{"aurum", aurum_hash, 0x1000, 0, 0},
	{"balloon", balloon_hash, 1, 0, 0},
	{"bastion", bastion_hash, 1, 0 },
	{"bcd", bcd_hash, 1, 0, 0},
	{"bitcore", timetravel10_hash, 0x100, 0, 0},
	{"blake", blake_hash, 1, 0 },
	{"blake2s", blake2s_hash, 1, 0 },
	{"blakecoin", blakecoin_hash, 1 /*0x100*/, 0, sha256_hash_hex },
	{"bmw", bmw_hash, 1, 0, 0},
	{"bmw512", bmw512_hash, 0x100, 0, 0},
	{"c11", c11_hash, 1, 0, 0},
	{"cosa", cosa_hash, 1, 0, 0}, //Cosanta (COSA)
	{"cpupower", cpupower_hash, 0x10000, 0, 0}, //CPUchain
	{"curvehash", curve_hash, 1, 0, 0},
	{"decred", decred_hash, 1, 0 },
	{"dedal", dedal_hash, 0x100, 0, 0},
	{"deep", deep_hash, 1, 0, 0},
	{"dmd-gr", groestl_hash, 0x100, 0, 0}, /* diamond (double groestl) */
	{"equihash", equi_hash, 0x100, 0, 0},
	{"equihash125", equi_hash, 0x100, 0, 0},
	{"equihash144", equi_hash, 0x100, 0, 0},
	{"equihash192", equi_hash, 0x100, 0, 0},
	{"equihash96", equi_hash, 0x100, 0, 0},
	{"ethash", sha256_double_hash, 1, 0, 0},
	{"etchash", sha256_double_hash, 1, 0, 0},
	{"firopow", sha256_double_hash, 1, 0, 0},
	{"flex", flex_hash, 1, 0, sha3d_hash_hex},
	{"fresh", fresh_hash, 0x100, 0, 0},
	{"geek", geek_hash, 1, 0, 0},
	{"gr", gr_hash, 0x10000, 0, 0},
	{"groestl", groestl_hash, 0x100, 0, sha256_hash_hex }, /* groestlcoin */
	{"heavyhash", heavyhash_hash, 1, 0, 0}, /* OBTC */
	{"hex", hex_hash, 0x100, 0, sha256_hash_hex },
	{"hive", hive_hash, 0x10000, 0, 0},
	{"hmq1725", hmq17_hash, 0x10000, 0, 0},
	{"honeycomb", beenode_hash, 0x10000, 0, 0},
	{"hsr", hsr_hash, 1, 0, 0},
	{"interchained", interchained_hash, 0x10000, 0, 0 },
	{"jeonghash", jeonghash_hash, 0x100, 0, 0},
	{"jha", jha_hash, 0x10000, 0},
	{"kawpow", sha256_double_hash, 1, 0, 0},
	{"keccak", keccak256_hash, 0x80, 0, sha256_hash_hex },
	{"keccakc", keccak256_hash, 0x100, 0, 0},
	{"lbk3", lbk3_hash, 0x100, 0, 0},
	{"lbry", lbry_hash, 0x100, 0, 0},
	{"luffa", luffa_hash, 1, 0, 0},
	{"lyra2", lyra2re_hash, 0x80, 0, 0},
	{"lyra2v2", lyra2v2_hash, 0x100, 0, 0},
	{"lyra2v3", lyra2v3_hash, 0x100, 0, 0},
	{"lyra2vc0ban", lyra2vc0ban_hash, 0x100, 0, 0},
	{"lyra2z", lyra2z_hash, 0x100, 0, 0},
	{"lyra2z330", lyra2z330_hash, 0x100, 0, 0},
	{"m7m", m7m_hash, 0x10000, 0, 0},
	{"memehash", meme_hash, 1, 0, 0}, /*PepePow Algo*/
	{"meowpow", sha256_double_hash, 1, 0, 0},
	{"megabtx", megabtx_hash, 0x100, 0, 0}, /* Bitcore New Algo*/
	{"megamec", megamec_hash, 0x100, 0, 0}, /* Megacoin New Algo*/
	{"mike", mike_hash, 0x10000, 0, 0},
	{"minotaur", minotaur_hash, 1, 0, 0},
	{"minotaurx", minotaurx_hash, 1, 0, 0},
	{"myr-gr", groestlmyriad_hash, 1, 0, 0}, /* groestl + sha 64 */
	{"neoscrypt", neoscrypt_hash, 0x10000, 0, 0},
	{"neoscrypt-xaya", neoscrypt_hash, 0x10000, 0, 0},
	{"nist5", nist5_hash, 1, 0, 0},
	{"pawelhash", pawelhash_hash, 0x100, 0, 0},
	{"penta", penta_hash, 1, 0, 0},
	{"phi", phi_hash, 1, 0, 0},
	{"phi2", phi2_hash, 0x100, 0, 0},
	{"phi5", phi5_hash, 1, 0, 0},
	{"phihash", sha256_double_hash, 1, 0, 0},
	{"pipe", pipe_hash, 1,0,0},
	{"polytimos", polytimos_hash, 1, 0, 0},
	{"power2b", power2b_hash, 0x10000, 0, 0 },
	{"quark", quark_hash, 1, 0, 0},
	{"qubit", qubit_hash, 1, 0, 0},
	{"rainforest", rainforest_hash, 0x100, 0, 0},
	{"renesis", renesis_hash, 1, 0, 0},
	{"rinhash", rinhash_hash, 1, 0, 0},
	{"scrypt", scrypt_hash, 0x10000, 0, 0},
	{"scryptn", scryptn_hash, 0x10000, 0, 0},
	{"sha256", sha256_double_hash, 1, 0, 0},
	{"sha256d", sha256_double_hash, 1, 0, 0},
	{"sha256dt", sha256dt_hash, 1, 0, 0},
	{"sha256csm", sha256csm_hash, 1, 0, 0},
	{"sha256t", sha256t_hash, 1, 0, 0}, // sha256 3x
	{"sha3d", sha3d_hash, 1, 0, sha3d_hash_hex},
	{"sha512256d", sha512_256_double_hash, 1, 0, 0},
	{"sib", sib_hash, 1, 0, 0},
	{"skydoge", skydoge_hash, 1, 0, 0}, /* Skydoge */
	{"skein", skein_hash, 1, 0, 0}, 
	{"skein2", skein2_hash, 1, 0, 0},
	{"skunk", skunk_hash, 1, 0, 0},
	{"sonoa", sonoa_hash, 1, 0, 0},
	{"soterg", soterg_hash, 1, 0, 0},
	{"timetravel", timetravel_hash, 0x100, 0, 0},
	{"tribus", tribus_hash, 1, 0, 0},
	{"vanilla", blakecoin_hash, 1, 0 },
	{"veltor", veltor_hash, 1, 0, 0},
	{"velvet", velvet_hash, 0x10000, 0, 0},
	{"vitalium", vitalium_hash, 1, 0, 0},
	{"x11", x11_hash, 1, 0, 0},
	{"x11evo", x11evo_hash, 1, 0, 0},
	{"x11k", x11k_hash, 1, 0, 0},
	{"x11kvs", x11kvs_hash, 0x100, 0, 0,7},
	{"x12", x12_hash, 1, 0, 0},
	{"x13", x13_hash, 1, 0, 0},
	{"x14", x14_hash, 1, 0, 0},
	{"x15", x15_hash, 1, 0, 0},
	{"x16r", x16r_hash, 0x100, 0, 0},
	{"x16rv2", x16rv2_hash, 0x100, 0, 0},
	{"x16rt", x16rt_hash, 0x100, 0, 0},
	{"x16s", x16s_hash, 0x100, 0, 0},
	{"x17", x17_hash, 1, 0, 0},
	{"x17r", x17r_hash, 1, 0, 0},	//ufo-project
	{"x18", x18_hash, 1, 0, 0},
	{"x20r", x20r_hash, 0x100, 0, 0},
	{"x21s", x21s_hash, 0x100, 0, 0},
	{"x22", x22_hash, 1, 0, 0},
	{"x22i", x22i_hash, 1, 0, 0},
	{"x25x", x25x_hash, 1, 0, 0},
	{"xevan", xevan_hash, 0x100, 0, 0},
	{"xelisv2-pepew", xelisv2_hash, 0x10000, 0, 0},
	{"yescrypt", yescrypt_hash, 0x10000, 0, 0},
	{"yescryptR8", yescryptR8_hash, 0x10000, 0, 0 },
	{"yescryptR16", yescryptR16_hash, 0x10000, 0, 0 },
	{"yescryptR32", yescryptR32_hash, 0x10000, 0, 0 },
	{"yespower", yespower_hash, 0x10000, 0, 0 },
	{"yespowerIC", yespowerIC_hash, 0x10000, 0, 0 }, //IsotopeC[IC]
	{"yespowerIOTS", yespowerIOTS_hash, 0x10000, 0, 0 }, //Iots [IOTS]
	{"yespowerLITB", yespowerLITB_hash, 0x10000, 0, 0 }, //LightBit[LITB]
	{"yespowerLTNCG", yespowerLTNCG_hash, 0x10000, 0, 0 }, //LightningCash Gold[LTNCG]
	{"yespowerR16", yespowerR16_hash, 0x10000, 0, 0 },
	{"yespowerRES", yespowerRES_hash, 0x10000, 0, 0 }, //Resistanse[RES] 
	{"yespowerSUGAR", yespowerSUGAR_hash, 0x10000, 0, 0 }, //Sugarchain[SUGAR] 
	{"yespowerTIDE", yespowerTIDE_hash, 0x10000, 0, 0 }, //Tidecoin[TDC] 
	{"yespowerURX", yespowerURX_hash, 0x10000, 0, 0 }, //UraniumX[URX] 
	{"yespowerMGPC", yespowerMGPC_hash, 0x10000, 0, 0 }, //Magpiecoin[MGPC] 
	{"yespowerARWN", yespowerARWN_hash, 0x10000, 0, 0 }, //Arowanacoin[ARWN] 
	{"yespowerADVC", yespowerADVC_hash, 0x10000, 0, 0 },  
	{"whirlcoin", whirlpool_hash, 1, 0, sha256_hash_hex }, /* old sha merkleroot */
	{"whirlpool", whirlpool_hash, 1, 0 }, /* sha256d merkleroot */
	{"whirlpoolx", whirlpoolx_hash, 1, 0, 0},
	{"zr5", zr5_hash, 1, 0, 0},
	{"", NULL, 0, 0},
};

/*
 * Tari SHA3X is deliberately NOT part of g_algos[].
 *
 * Tari does not use the Bitcoin-style 80-byte header or the
 * generic client_submit() path. This descriptor only allows
 * the common YiiMP runtime to identify algo=sha3x.
 */
static YAAMP_ALGO g_tari_sha3x_algo = {
        "sha3x",
        sha3x_hash,
        1.0,
        1.0,
        NULL,
        1.0,
        0,
        0.0,
        0.0,
        false
};

YAAMP_ALGO *g_current_algo = NULL;

YAAMP_ALGO *stratum_find_algo(const char *name)
{
        if(!name)
                return NULL;

        /*
         * Special Tari protocol descriptor.
         * Keep SHA3X outside the generic g_algos[] table.
         */
        if(!strcmp(name, "sha3x"))
                return &g_tari_sha3x_algo;

        for(int i=0; g_algos[i].name[0]; i++)
                if(!strcmp(name, g_algos[i].name))
                        return &g_algos[i];

        return NULL;
}

////////////////////////////////////////////////////////////////////////////////////////

int main(int argc, char **argv)
{
	// stdout is normally redirected through tee/screen by the launcher.  In
	// that mode libc uses block buffering, delaying startup messages until the
	// buffer fills.  Make every log line visible as soon as it is emitted.
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);

	if(argc < 2)
	{
		printf("usage: %s <config_file>\n", argv[0]);
		return 1;
	}

	srand(time(NULL));
	getifaddrs(&g_ifaddr);

	// init g_log_directory with static value until set by config
	sprintf(g_log_directory, "/var/stratum/logs/");
	initlog(NULL, NULL);

	char configfile[1024];
	sprintf(configfile, "%s", argv[1]);

	dictionary *ini = iniparser_load(configfile);
	if(!ini)
	{
		debuglog("cant load config file %s\n", configfile);
		return 1;
	}

	g_tcp_port = iniparser_getint(ini, "TCP:port", 3333);
	strcpy(g_tcp_server, iniparser_getstring(ini, "TCP:server", NULL));
	strcpy(g_tcp_password, iniparser_getstring(ini, "TCP:password", NULL));

	strcpy(g_sql_host, iniparser_getstring(ini, "SQL:host", NULL));
	strcpy(g_sql_database, iniparser_getstring(ini, "SQL:database", NULL));
	strcpy(g_sql_username, iniparser_getstring(ini, "SQL:username", NULL));
	strcpy(g_sql_password, iniparser_getstring(ini, "SQL:password", NULL));
	g_sql_port = iniparser_getint(ini, "SQL:port", 3306);

	if (iniparser_getint(ini, "STRATUM:autoexchange", 1) == 0)
		g_autoexchange = false;
	else
		g_autoexchange = true;

	// optional coin filters (to mine only one on a special port or a test instance)
	char *coin_filter = iniparser_getstring(ini, "WALLETS:include", NULL);
	strcpy(g_stratum_coin_include, coin_filter ? coin_filter : "");
	coin_filter = iniparser_getstring(ini, "WALLETS:exclude", NULL);
	strcpy(g_stratum_coin_exclude, coin_filter ? coin_filter : "");

	strcpy(g_stratum_algo, iniparser_getstring(ini, "STRATUM:algo", NULL));
	g_stratum_difficulty = iniparser_getdouble(ini, "STRATUM:difficulty", 16);
	g_stratum_min_diff = iniparser_getdouble(ini, "STRATUM:diff_min", g_stratum_difficulty/2);
	g_stratum_max_diff = iniparser_getdouble(ini, "STRATUM:diff_max", g_stratum_difficulty*8192);
	
	char *new_log_directory = iniparser_getstring(ini, "STRATUM:logdir", NULL);
	if (new_log_directory) { strcpy(g_log_directory, new_log_directory); }

	g_stratum_nicehash_difficulty = iniparser_getdouble(ini, "STRATUM:nicehash", 16);
	g_stratum_nicehash_min_diff = iniparser_getdouble(ini, "STRATUM:nicehash_diff_min", g_stratum_nicehash_difficulty/2);
	g_stratum_nicehash_max_diff = iniparser_getdouble(ini, "STRATUM:nicehash_diff_max", g_stratum_nicehash_difficulty*8192);
	if(!isfinite(g_stratum_nicehash_difficulty) || g_stratum_nicehash_difficulty <= 0)
		g_stratum_nicehash_difficulty = g_stratum_difficulty;
	if(!isfinite(g_stratum_nicehash_min_diff) || g_stratum_nicehash_min_diff <= 0)
		g_stratum_nicehash_min_diff = g_stratum_nicehash_difficulty/2;
	if(!isfinite(g_stratum_nicehash_max_diff) || g_stratum_nicehash_max_diff < g_stratum_nicehash_min_diff)
		g_stratum_nicehash_max_diff = g_stratum_nicehash_difficulty*8192;
	if(g_stratum_nicehash_difficulty < g_stratum_nicehash_min_diff)
		g_stratum_nicehash_difficulty = g_stratum_nicehash_min_diff;
	if(g_stratum_nicehash_difficulty > g_stratum_nicehash_max_diff)
		g_stratum_nicehash_difficulty = g_stratum_nicehash_max_diff;

	g_stratum_mrr_difficulty = iniparser_getdouble(ini, "STRATUM:mrr", g_stratum_difficulty);
	g_stratum_mrr_min_diff = iniparser_getdouble(ini, "STRATUM:mrr_diff_min", g_stratum_min_diff);
	g_stratum_mrr_max_diff = iniparser_getdouble(ini, "STRATUM:mrr_diff_max", g_stratum_max_diff);
	if(!isfinite(g_stratum_mrr_difficulty) || g_stratum_mrr_difficulty <= 0)
		g_stratum_mrr_difficulty = g_stratum_difficulty;
	if(!isfinite(g_stratum_mrr_min_diff) || g_stratum_mrr_min_diff <= 0)
		g_stratum_mrr_min_diff = g_stratum_min_diff;
	if(!isfinite(g_stratum_mrr_max_diff) || g_stratum_mrr_max_diff < g_stratum_mrr_min_diff)
		g_stratum_mrr_max_diff = g_stratum_max_diff;
	if(g_stratum_mrr_difficulty < g_stratum_mrr_min_diff)
		g_stratum_mrr_difficulty = g_stratum_mrr_min_diff;
	if(g_stratum_mrr_difficulty > g_stratum_mrr_max_diff)
		g_stratum_mrr_difficulty = g_stratum_mrr_max_diff;

	g_stratum_max_cons = iniparser_getint(ini, "STRATUM:max_cons", 5000);
	g_stratum_max_ttf = iniparser_getint(ini, "STRATUM:max_ttf", 0x70000000);
	g_stratum_reconnect = iniparser_getint(ini, "STRATUM:reconnect", true);
	g_stratum_renting = iniparser_getint(ini, "STRATUM:renting", true);
	g_handle_haproxy_ips = iniparser_getint(ini, "STRATUM:haproxy_ips", g_handle_haproxy_ips);
	g_socket_recv_timeout = iniparser_getint(ini, "STRATUM:recv_timeout", 600);
	g_observability_rpc_warn_ms = iniparser_getint(ini, "STRATUM:rpc_warn_ms", 1000);
	g_observability_rpc_critical_ms = iniparser_getint(ini, "STRATUM:rpc_critical_ms", 3000);
	g_observability_rpc_slow_streak = iniparser_getint(ini, "STRATUM:rpc_slow_streak", 2);
	g_observability_summary_interval = iniparser_getint(ini, "STRATUM:summary_interval", 300);
	g_observability_log_shares = iniparser_getint(ini, "STRATUM:log_shares", 1) != 0;
	if(g_observability_rpc_warn_ms < 1) g_observability_rpc_warn_ms = 1000;
	if(g_observability_rpc_critical_ms <= g_observability_rpc_warn_ms)
		g_observability_rpc_critical_ms = g_observability_rpc_warn_ms * 3;
	if(g_observability_rpc_slow_streak < 1) g_observability_rpc_slow_streak = 1;
	if(g_observability_summary_interval < 60) g_observability_summary_interval = 60;

	g_max_shares = iniparser_getint(ini, "STRATUM:max_shares", g_max_shares);
	g_limit_txs_per_block = iniparser_getint(ini, "STRATUM:max_txs_per_block", 0);
	

	g_debuglog_client = iniparser_getint(ini, "DEBUGLOG:client", false);
	g_debuglog_hash = iniparser_getint(ini, "DEBUGLOG:hash", false);
	g_debuglog_socket = iniparser_getint(ini, "DEBUGLOG:socket", false);
	g_debuglog_rpc = iniparser_getint(ini, "DEBUGLOG:rpc", false);
	g_debuglog_list = iniparser_getint(ini, "DEBUGLOG:list", false);
	g_debuglog_remote = iniparser_getint(ini, "DEBUGLOG:remote", false);
	g_debuglog_verbose = iniparser_getint(ini, "DEBUGLOG:verbose", false);

	iniparser_freedict(ini);

	// re-init logfiles
	closelogs(); initlog(g_stratum_algo, g_stratum_coin_include);	

	validate_hashfunctions();
	
	g_current_algo = stratum_find_algo(g_stratum_algo);

	if(!g_current_algo) yaamp_error("invalid algo");
	if(!g_current_algo->hash_function) yaamp_error("no hash function");

	if (!strcmp(g_current_algo->name,"kawpow"))
	{
		is_kawpow = true;
		stratumlog("Algorithm engine selected: KAWPOW\n");
	}
	else if(!strcmp(g_current_algo->name,"firopow"))
	{
		is_firopow = true;
		stratumlog("Algorithm engine selected: FIROPOW\n");
	}
	else if(!strcmp(g_current_algo->name,"phihash"))
	{
		is_phihash = true;
		stratumlog("Algorithm engine selected: PHIHASH\n");
	}
	else if (!strcmp(g_current_algo->name,"meowpow"))
	{
		is_meowpow = true;
		stratumlog("Algorithm engine selected: MEOWPOW\n");
	}
	else if (!strcmp(g_current_algo->name,"ethash"))
	{
		is_ethash = true;
		stratumlog("Algorithm engine selected: ETHASH (geth-compatible)\n");
	}
	else if (!strcmp(g_current_algo->name,"etchash"))
	{
		// Etchash uses the same Ethereum JSON-RPC/miner protocol paths as
		// Ethash, but PoW verification is selected separately below.
		is_ethash = true;
		is_etchash = true;
		stratumlog("Algorithm engine selected: ETCHASH (Ethereum Classic ECIP-1099)\n");
	}

//	struct rlimit rlim_files = {0x10000, 0x10000};
//	setrlimit(RLIMIT_NOFILE, &rlim_files);

	struct rlimit rlim_threads = {0x8000, 0x8000};
	setrlimit(RLIMIT_NPROC, &rlim_threads);

	stratumlogdate("starting stratum for %s on %s:%d\n",
		g_current_algo->name, g_tcp_server, g_tcp_port);

        const bool tari_mode =
                tari_protocol_enabled();

        if(tari_mode)
        {
                stratumlog(
                        "TARI_MODE enabled: legacy coind RPC and "
                        "generic YiiMP job scheduler disabled\n");
        }

	// init Equihash parameters
	if (!strcmp(g_current_algo->name,"equihash144")) {
		g_equihash_wn = EQUIHASH144_5_WN;
		g_equihash_wk = EQUIHASH144_5_WK;
	}
	else if (!strcmp(g_current_algo->name,"equihash192")) {
		g_equihash_wn = EQUIHASH192_7_WN;
		g_equihash_wk = EQUIHASH192_7_WK;
	}
	else if (!strcmp(g_current_algo->name,"equihash96")) {
		g_equihash_wn = EQUIHASH96_5_WN;
		g_equihash_wk = EQUIHASH96_5_WK;
	}
	else if (!strcmp(g_current_algo->name,"equihash125")) {
		g_equihash_wn = EQUIHASH125_4_WN;
		g_equihash_wk = EQUIHASH125_4_WK;
	}

	// ntime should not be changed by miners for these algos
	g_allow_rolltime = strcmp(g_stratum_algo,"x11evo");
	g_allow_rolltime = g_allow_rolltime && strcmp(g_stratum_algo,"timetravel");
	g_allow_rolltime = g_allow_rolltime && strcmp(g_stratum_algo,"bitcore");
	g_allow_rolltime = g_allow_rolltime && strcmp(g_stratum_algo,"exosis");
	if (!g_allow_rolltime)
		stratumlog("note: time roll disallowed for %s algo\n", g_current_algo->name);

	g_db = db_connect();
	if(!g_db) yaamp_error("Cant connect database");

//	db_query(g_db, "update mining set stratumids='loading'");

	yaamp_create_mutex(&g_db_mutex);
	yaamp_create_mutex(&g_nonce1_mutex);
	yaamp_create_mutex(&g_context_mutex);
	yaamp_create_mutex(&g_job_create_mutex);

	YAAMP_DB *db = db_connect();
	if(!db) yaamp_error("Cant connect database");

	db_register_stratum(db);
	if(tari_mode &&
	                !tari_coin_identity_refresh(db))
	        {
	                yaamp_error(
	                        "Tari coin identity unavailable");
	        }

                        db_update_algos(db);
	if(!tari_mode)
	        db_update_coinds(db);
	load_server_ip(g_db);

	sleep(2);
	if(!tari_mode)
	        job_init();

//	job_signal();

	////////////////////////////////////////////////

	pthread_t thread1;
	pthread_create(&thread1, NULL, monitor_thread, NULL);

	pthread_t thread2;
	pthread_create(&thread2, NULL, stratum_thread, NULL);

        if(tari_mode)
        {
                pthread_t tari_bridge_tid;

                int tari_bridge_res =
                        pthread_create(
                                &tari_bridge_tid,
                                NULL,
                                tari_bridge_thread,
                                NULL);

                if(tari_bridge_res)
                {
                        stratumlog(
                                "TARI_BRIDGE_POLLER_THREAD_ERROR "
                                "error=%d\n",
                                tari_bridge_res);

                        g_exiting = true;
                }
        }


	sleep(20);

	while(!g_exiting)
	{
		db_register_stratum(db);
		db_update_workers(db);
		db_update_algos(db);
		if(!tari_mode)
		        db_update_coinds(db);

		if(g_stratum_renting && !tari_mode)
		{
			db_update_renters(db);
			db_update_remotes(db);
		}

		share_write(db);
		share_prune(db);

		block_prune(db);
		submit_prune(db);

		sleep(1);
		if(!tari_mode)
		        job_signal();

		////////////////////////////////////

//		source_prune();
		if(!tari_mode)
		        job_check_status();

		object_prune(&g_list_coind, coind_delete);
		object_prune(&g_list_remote, remote_delete);
		object_prune(&g_list_job, job_delete);
		object_prune(&g_list_client, client_delete);
		object_prune(&g_list_block, block_delete);
		object_prune(&g_list_worker, worker_delete);
		object_prune(&g_list_share, share_delete);
		object_prune(&g_list_submit, submit_delete);

		// One operational snapshot per minute. Distinguish connected workers and
		// cumulative submit results from the internal queues awaiting DB flush.
		static time_t last_stats_log = 0;
		static time_t last_summary_log = 0;
		static uint64_t previous_submits = 0;
		static uint64_t previous_accepted = 0;
		static uint64_t previous_rejected = 0;
		static uint64_t previous_low_diff = 0;
		static uint64_t previous_stale = 0;
		static uint64_t previous_duplicate = 0;
		static uint64_t previous_invalid = 0;
		static uint64_t previous_other = 0;
		static uint64_t summary_submits = 0;
		static uint64_t summary_accepted = 0;
		static uint64_t summary_rejected = 0;
		time_t stats_now = time(NULL);
		if (g_debuglog_verbose && (!last_stats_log || stats_now - last_stats_log >= 60))
		{
			int workers_connected = 0;
			g_list_client.Enter();
			for (CLI li = g_list_client.first; li; li = li->next)
			{
				YAAMP_CLIENT *client = (YAAMP_CLIENT *)li->data;
				if (!client->deleted && client->workerid > 0)
					workers_connected++;
			}
			g_list_client.Leave();

			const uint64_t submits = __sync_fetch_and_add(&g_shares_counter, 0);
			const uint64_t accepted = __sync_fetch_and_add(&g_shares_accepted_counter, 0);
			const uint64_t rejected = __sync_fetch_and_add(&g_shares_rejected_counter, 0);
			const uint64_t low_diff = __sync_fetch_and_add(&g_reject_low_diff_counter, 0);
			const uint64_t stale = __sync_fetch_and_add(&g_reject_stale_counter, 0);
			const uint64_t duplicate = __sync_fetch_and_add(&g_reject_duplicate_counter, 0);
			const uint64_t invalid = __sync_fetch_and_add(&g_reject_invalid_counter, 0);
			const uint64_t other = __sync_fetch_and_add(&g_reject_other_counter, 0);
			const uint64_t window_submits = submits - previous_submits;
			const uint64_t window_accepted = accepted - previous_accepted;
			const uint64_t window_rejected = rejected - previous_rejected;
			const double window_accept_pct = window_submits ?
				100.0 * (double)window_accepted / (double)window_submits : 100.0;
			debuglog(
				"STATS coinds=%i jobs=%i clients=%i blocks_pending=%i "
				"workers_connected=%i worker_updates_pending=%i share_rows_pending=%i "
				"share_submit_total=%llu share_accept_total=%llu share_reject_total=%llu "
				"window_submit=%llu window_accept=%llu window_reject=%llu window_accept_pct=%.3f "
				"reject_low_diff=%llu reject_stale=%llu reject_duplicate=%llu "
				"reject_invalid=%llu reject_other=%llu%s\n",
				g_list_coind.count, g_list_job.count, g_list_client.count,
				g_list_block.count, workers_connected, g_list_worker.count,
				g_list_share.count, (unsigned long long)submits,
				(unsigned long long)accepted, (unsigned long long)rejected,
				(unsigned long long)window_submits, (unsigned long long)window_accepted,
				(unsigned long long)window_rejected, window_accept_pct,
				(unsigned long long)(low_diff - previous_low_diff),
				(unsigned long long)(stale - previous_stale),
				(unsigned long long)(duplicate - previous_duplicate),
				(unsigned long long)(invalid - previous_invalid),
				(unsigned long long)(other - previous_other),
				g_list_coind.count == 0 ? " WARNING=no_coin_connected" : "");
			previous_submits = submits;
			previous_accepted = accepted;
			previous_rejected = rejected;
			previous_low_diff = low_diff;
			previous_stale = stale;
			previous_duplicate = duplicate;
			previous_invalid = invalid;
			previous_other = other;
			if(!last_summary_log) last_summary_log = stats_now;
			if(stats_now - last_summary_log >= g_observability_summary_interval)
			{
				const uint64_t summary_window_submits = submits - summary_submits;
				const uint64_t summary_window_accepted = accepted - summary_accepted;
				const uint64_t summary_window_rejected = rejected - summary_rejected;
				const double summary_accept_pct = summary_window_submits ?
					100.0 * (double)summary_window_accepted /
					(double)summary_window_submits : 100.0;
				stratumlog("STRATUM_SUMMARY interval=%ds algo=%s clients=%i workers=%i "
					"submitted=%llu accepted=%llu rejected=%llu acceptance=%.3f%% "
					"pending_shares=%i pending_blocks=%i\n",
					g_observability_summary_interval, g_stratum_algo,
					g_list_client.count, workers_connected,
					(unsigned long long)summary_window_submits,
					(unsigned long long)summary_window_accepted,
					(unsigned long long)summary_window_rejected, summary_accept_pct,
					g_list_share.count, g_list_block.count);
				summary_submits = submits;
				summary_accepted = accepted;
				summary_rejected = rejected;
				last_summary_log = stats_now;
			}
			last_stats_log = stats_now;
		}
		kawpow_health_maybe_log();

		if ( g_list_coind.count < g_list_job.count ) {
			job_log_statistic();
		}

		if (!g_exiting) sleep(20);
	}

	stratumlog("closing database...\n");
	db_close(db);

	pthread_join(thread2, NULL);
	db_close(g_db); // client threads (called by stratum one)

	closelogs();

	return 0;
}

///////////////////////////////////////////////////////////////////////////////

void *monitor_thread(void *p)
{
        while(!g_exiting)
        {
                sleep(120);

                /*
                 * No miners means there is nobody to receive a job broadcast.
                 * Do not interpret an idle stratum as a deadlock.
                 */
                g_list_client.Enter();
                int client_count = g_list_client.count;
                g_list_client.Leave();

                if(g_list_coind.count > 0 &&
                        client_count > 0 &&
                        g_last_broadcasted + YAAMP_MAXJOBDELAY < time(NULL))
                {
                        g_exiting = true;
                        stratumlogdate("%s dead lock, exiting...\n", g_stratum_algo);
                        exit(1);
                }
        }
        return NULL;
}

///////////////////////////////////////////////////////////////////////////////

void *stratum_thread(void *p)
{
	int listen_sock = socket(AF_INET, SOCK_STREAM, 0);
	if(listen_sock <= 0) yaamp_error("socket");

	int optval = 1;
	setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof optval);

	struct sockaddr_in serv;

	serv.sin_family = AF_INET;
	serv.sin_addr.s_addr = htonl(INADDR_ANY);
	serv.sin_port = htons(g_tcp_port);

	int res = bind(listen_sock, (struct sockaddr*)&serv, sizeof(serv));
	if(res < 0) yaamp_error("bind");

	res = listen(listen_sock, 4096);
	if(res < 0) yaamp_error("listen");

	/////////////////////////////////////////////////////////////////////////

	int failcount = 0;
	while(!g_exiting)
	{
		int sock = accept(listen_sock, NULL, NULL);
		if(sock <= 0)
		{
			int error = errno;
			stratumlog("%s socket accept() error %d\n", g_stratum_algo, error);
			failcount++;
			usleep(50000);
			if (error == 24 && failcount > 5) {
				g_exiting = true; // happen when max open files is reached (see ulimit)
				stratumlogdate("%s too much socket failure, exiting...\n", g_stratum_algo);
				exit(error);
			}
			continue;
		}

		failcount = 0;
		pthread_t thread;
		int res = pthread_create(&thread, NULL, client_thread, (void *)(long)sock);
		if(res != 0)
		{
			int error = errno;
			close(sock);
			g_exiting = true;
			stratumlog("%s pthread_create error %d %d\n", g_stratum_algo, res, error);
		}

		pthread_detach(thread);
	}
        return NULL;
}

bool validate_hashfunctions() {
    int len;
	char input_hex[512]; char output_hex[8192];
	char input_bin[512]; char output_bin[8192];
	bool check_failure = false;

	struct Checkdata {
		string algoname;
		YAAMP_HASH_FUNCTION hash_function;
		string hashdata;
		string inputdata;
	};

	std::vector<Checkdata> VectorCheckdata;

	for(auto CurrentCheckdata : VectorCheckdata)
    {
		strcpy(input_hex,CurrentCheckdata.inputdata.c_str());
		len = strlen(input_hex) / 2;
		binlify((unsigned char*)input_bin, input_hex);

		CurrentCheckdata.hash_function(input_bin, output_bin, len);
		hexlify(input_bin,(const unsigned char*)output_bin, 32);
		string_be((const char*)input_bin, output_hex);
		if (CurrentCheckdata.hashdata != std::string(output_hex)) {
			if (!check_failure) { debuglog("hash-function validation failed\n"); check_failure = true; };
			debuglog("validation for \"%s\" failed\n", CurrentCheckdata.algoname.c_str());
			debuglog(" this   : %s\n", output_hex);
			debuglog(" correct: %s\n", CurrentCheckdata.hashdata.c_str());
		}
	}

	if (!check_failure) { debuglog("hash-function passed\n"); }

	return check_failure;
}

void load_server_ip(YAAMP_DB *db)
{
    MYSQL_RES *result = NULL;

    db_query(db, "SELECT value FROM serverconfig WHERE name='SERVER_IP' LIMIT 1");

    result = mysql_store_result(&db->mysql);
    if(result)
    {
        MYSQL_ROW row = mysql_fetch_row(result);
        if(row && row[0])
        {
            strncpy(g_server_ip, row[0], sizeof(g_server_ip)-1);
            g_server_ip[sizeof(g_server_ip)-1] = '\0';
        }

        mysql_free_result(result);
    }

    stratumlog("SERVER_IP loaded: %s\n", g_server_ip);
}
