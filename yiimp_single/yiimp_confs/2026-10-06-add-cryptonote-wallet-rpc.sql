-- SQSYIIMP - CryptoNote/XMR separate wallet RPC support

SET @db := DATABASE();

SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE coins ADD COLUMN wallet_rpchost VARCHAR(128) NULL DEFAULT NULL AFTER rpcport',
        'SELECT 1'
    )
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @db
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'wallet_rpchost'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE coins ADD COLUMN wallet_rpcport INT(11) NULL DEFAULT NULL AFTER wallet_rpchost',
        'SELECT 1'
    )
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @db
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'wallet_rpcport'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE coins ADD COLUMN wallet_rpcuser VARCHAR(128) NULL DEFAULT NULL AFTER wallet_rpcport',
        'SELECT 1'
    )
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @db
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'wallet_rpcuser'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE coins ADD COLUMN wallet_rpcpasswd VARCHAR(128) NULL DEFAULT NULL AFTER wallet_rpcuser',
        'SELECT 1'
    )
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @db
      AND TABLE_NAME = 'coins'
      AND COLUMN_NAME = 'wallet_rpcpasswd'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
