-- Anonymous device identity + durable progress (build-order steps 16-17).

CREATE TABLE devices (
    id UUID PRIMARY KEY,
    token_hash TEXT NOT NULL UNIQUE,
    name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE puzzle_progress (
    device_id UUID NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    puzzle_id TEXT NOT NULL,
    puzzle_version INT NOT NULL,
    solved BOOLEAN NOT NULL DEFAULT FALSE,
    best_rank TEXT,
    best_metrics JSONB NOT NULL DEFAULT '{}',
    attempt_count INT NOT NULL DEFAULT 0,
    first_solved_at TIMESTAMPTZ,
    best_solved_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, puzzle_id)
);

-- Every meaningful submission: difficulty analysis, common wrong answers,
-- broken-puzzle detection, replay measurement.
CREATE TABLE puzzle_attempts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    puzzle_id TEXT NOT NULL,
    puzzle_version INT NOT NULL,
    operations JSONB NOT NULL,
    status TEXT NOT NULL,
    rank TEXT,
    metrics JSONB NOT NULL,
    cached BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX puzzle_attempts_device_puzzle
    ON puzzle_attempts (device_id, puzzle_id);
