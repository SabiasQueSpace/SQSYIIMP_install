-- SQSYIIMP - RandomX algorithm registration
-- Idempotent migration.

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
    'randomx',
    0,
    0,
    1.0,
    0,
    1.0,
    '#5b8def',
    1.0,
    4242,
    1,
    NULL
WHERE NOT EXISTS
(
    SELECT 1 FROM algos WHERE name = 'randomx'
);

UPDATE algos
SET
    color       = '#5b8def',
    speedfactor = 1.0,
    port        = 4242,
    visible     = 1
WHERE name = 'randomx';
