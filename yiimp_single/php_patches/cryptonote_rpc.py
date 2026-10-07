#!/usr/bin/env python3

from pathlib import Path
import argparse
import os
import re
import sys


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def read_storage_root(config_path=Path("/etc/yiimpool.conf")):
    if not config_path.is_file():
        return None

    try:
        content = config_path.read_text()
    except OSError:
        return None

    pattern = re.compile(
        r"""(?mx)
        ^\s*
        (?:export\s+)?
        STORAGE_ROOT
        \s*=\s*
        (?:
            "([^"]*)"
            |
            '([^']*)'
            |
            ([^#\s]+)
        )
        """
    )

    match = pattern.search(content)

    if not match:
        return None

    return next(
        (value for value in match.groups() if value is not None),
        None,
    )


def resolve_site():
    parser = argparse.ArgumentParser(
        description="Apply SQSYIIMP CryptoNote/XMR YiiMP PHP compatibility patches."
    )

    parser.add_argument(
        "--site",
        help="Absolute path to the YiiMP site directory.",
    )

    args = parser.parse_args()

    if args.site:
        return Path(args.site).expanduser()

    env_site = os.environ.get("YIIMP_SITE", "").strip()

    if env_site:
        return Path(env_site).expanduser()

    storage_root = os.environ.get("STORAGE_ROOT", "").strip()

    if not storage_root:
        storage_root = read_storage_root() or ""

    if storage_root:
        return Path(storage_root).expanduser() / "yiimp/site"

    fail(
        "No se pudo determinar YiiMP site. "
        "Use --site, YIIMP_SITE, STORAGE_ROOT o configure "
        "STORAGE_ROOT en /etc/yiimpool.conf."
    )


SITE = resolve_site()

wallet_rpc = SITE / "web/yaamp/core/rpc/wallet-rpc.php"
xmr_rpc = SITE / "web/yaamp/core/rpc/xmr-rpc.php"


print(f"INFO: YiiMP site: {SITE}")

if not wallet_rpc.exists():
    fail(f"No existe {wallet_rpc}")

if not xmr_rpc.exists():
    fail(f"No existe {xmr_rpc}")


# ---------------------------------------------------------
# wallet-rpc.php
# ---------------------------------------------------------

s = wallet_rpc.read_text()

if (
    "case 'CRYPTONOTE':" in s
    and "wallet_rpchost" in s
    and "wallet_rpcport" in s
):
    print("OK: wallet-rpc.php ya tiene soporte CryptoNote separado")
else:
    pattern = re.compile(
        r"""(?ms)^(\s*)case 'XMR':\s*
\1\s*\$this->type\s*=\s*'CryptoNote';.*?
\1\s*break;\s*
(?=\1\s*default:)"""
    )

    m = pattern.search(s)

    if not m:
        fail("No se pudo localizar el bloque XMR en wallet-rpc.php")

    indent = m.group(1)

    new = f"""{indent}case 'XMR':
{indent}case 'CRYPTONOTE':
{indent}        $this->type = 'CryptoNote';
{indent}        $this->coin = $coin;

{indent}        // CryptoNote daemon RPC
{indent}        $this->rpc = new CryptoRPC(
{indent}                $coin->rpchost,
{indent}                $coin->rpcport,
{indent}                $coin->rpcuser,
{indent}                $coin->rpcpasswd
{indent}        );

{indent}        // CryptoNote wallet RPC runs separately from daemon RPC.
{indent}        // Legacy fallback preserves old XMR configurations.
{indent}        $walletHost = !empty($coin->wallet_rpchost)
{indent}                ? $coin->wallet_rpchost
{indent}                : '127.0.0.1';

{indent}        $walletPort = !empty($coin->wallet_rpcport)
{indent}                ? $coin->wallet_rpcport
{indent}                : $coin->rpcport;

{indent}        $walletUser = !empty($coin->wallet_rpcuser)
{indent}                ? $coin->wallet_rpcuser
{indent}                : $coin->rpcuser;

{indent}        $walletPass = !empty($coin->wallet_rpcpasswd)
{indent}                ? $coin->wallet_rpcpasswd
{indent}                : $coin->rpcpasswd;

{indent}        $this->rpc_wallet = new CryptoRPC(
{indent}                $walletHost,
{indent}                $walletPort,
{indent}                $walletUser,
{indent}                $walletPass
{indent}        );
{indent}        break;
"""

    s2, count = pattern.subn(new, s, count=1)

    if count != 1:
        fail(f"wallet-rpc.php: reemplazos inesperados: {count}")

    wallet_rpc.write_text(s2)
    print("OK: wallet-rpc.php actualizado")


# ---------------------------------------------------------
# xmr-rpc.php
# ---------------------------------------------------------

s = xmr_rpc.read_text()

if '$url .= "?ts=".time();' in s:
    print("OK: xmr-rpc.php ya conserva la URL")
else:
    pattern = r'(\$url\s*)=\s*"\?ts="\s*\.\s*time\(\);'

    s2, count = re.subn(
        pattern,
        r'\1.= "?ts=".time();',
        s,
        count=1,
    )

    if count != 1:
        fail("No se pudo localizar el bug rpcget en xmr-rpc.php")

    xmr_rpc.write_text(s2)
    print("OK: xmr-rpc.php actualizado")


print("OK: soporte PHP CryptoNote/XMR preparado")
