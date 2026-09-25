-- SQSYIIMP - Quantus QPoW / Poseidon2
-- Idempotent database integration.
--
-- Stratum:      quantus / TCP 6477
-- YiiMP RPC:    127.0.0.1:6350
-- Native RPC:   127.0.0.1:9944
-- Native miner: UDP 9833 (not exposed through YiiMP)
--
-- QTC remains enable=0 / auto_ready=0 until the native
-- NewJob/share/block-candidate bridge is production ready.

-- ------------------------------------------------------------
-- Keep algos.name compatible with coins.algo.
-- This avoids illegal-mix-of-collations joins.
-- ------------------------------------------------------------

SET @quantus_algo_charset = (
    SELECT CHARACTER_SET_NAME
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'algo'
    LIMIT 1
);

SET @quantus_algo_collation = (
    SELECT COLLATION_NAME
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'algo'
    LIMIT 1
);

SET @quantus_current_charset = (
    SELECT CHARACTER_SET_NAME
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'algos'
      AND COLUMN_NAME = 'name'
    LIMIT 1
);

SET @quantus_current_collation = (
    SELECT COLLATION_NAME
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'algos'
      AND COLUMN_NAME = 'name'
    LIMIT 1
);

SET @quantus_alter_sql =
    IF(
        @quantus_algo_charset IS NULL
        OR @quantus_algo_collation IS NULL
        OR (
            @quantus_current_charset =
                @quantus_algo_charset
            AND
            @quantus_current_collation =
                @quantus_algo_collation
        ),
        'SELECT 1',
        CONCAT(
            'ALTER TABLE `algos` ',
            'MODIFY `name` varchar(16) ',
            'CHARACTER SET ',
            @quantus_algo_charset,
            ' COLLATE ',
            @quantus_algo_collation,
            ' DEFAULT NULL'
        )
    );

PREPARE quantus_stmt
FROM @quantus_alter_sql;

EXECUTE quantus_stmt;

DEALLOCATE PREPARE quantus_stmt;


-- ------------------------------------------------------------
-- Algorithm
-- ------------------------------------------------------------

INSERT INTO algos
(
    name,
    profit,
    rent,
    factor,
    overflow,
    norm,
    color,
    speedfactor,
    port,
    visible,
    powlimit_bits
)
SELECT
    'quantus',
    0,
    0,
    1.0,
    0,
    1.0,
    '#7c3aed',
    1.0,
    6477,
    1,
    0
WHERE NOT EXISTS
(
    SELECT 1
    FROM algos
    WHERE name = 'quantus'
);

UPDATE algos
SET
    profit        = 0,
    rent          = 0,
    factor        = 1.0,
    overflow      = 0,
    norm          = 1.0,
    color         = '#7c3aed',
    speedfactor   = 1.0,
    port          = 6477,
    visible       = 1,
    powlimit_bits = 0
WHERE name = 'quantus';


-- ------------------------------------------------------------
-- Quantus QTC
--
-- This intentionally updates an existing QTC coin only.
-- It does not create an incomplete coins row on a fresh DB.
-- ------------------------------------------------------------

UPDATE coins
SET
    algo           = 'quantus',
    installed      = 1,
    visible        = 1,
    enable         = 0,
    auto_ready     = 0,
    rpcencoding    = 'QUANTUS',
    rpchost        = '127.0.0.1',
    rpcport        = 6350,
    hasgetinfo     = 1,
    rpccurl        = 1,
    rpcssl         = 0,
    auxpow         = 0,
    hassubmitblock = 0,
    txmessage      = 0,
    index_avg      = 1
WHERE UPPER(symbol) = 'QTC'
  AND LOWER(name) = 'quantus';
