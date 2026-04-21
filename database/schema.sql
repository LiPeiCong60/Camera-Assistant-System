BEGIN;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    user_code VARCHAR(64) NOT NULL UNIQUE,
    phone VARCHAR(32),
    email VARCHAR(255),
    password_hash TEXT,
    display_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    role VARCHAR(32) NOT NULL DEFAULT 'user',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_users_role CHECK (role IN ('user', 'admin')),
    CONSTRAINT chk_users_status CHECK (status IN ('active', 'inactive', 'disabled'))
);

CREATE TABLE IF NOT EXISTS plans (
    id BIGSERIAL PRIMARY KEY,
    plan_code VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price_cents INTEGER NOT NULL DEFAULT 0,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    billing_cycle_days INTEGER NOT NULL DEFAULT 30,
    capture_quota INTEGER,
    ai_task_quota INTEGER,
    feature_flags JSONB NOT NULL DEFAULT '{}'::JSONB,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_plans_price CHECK (price_cents >= 0),
    CONSTRAINT chk_plans_cycle CHECK (billing_cycle_days > 0),
    CONSTRAINT chk_plans_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS user_subscriptions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id BIGINT NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
    quota_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_user_subscriptions_status CHECK (status IN ('active', 'expired', 'cancelled', 'paused'))
);

CREATE TABLE IF NOT EXISTS devices (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_code VARCHAR(64) NOT NULL UNIQUE,
    device_name VARCHAR(100) NOT NULL,
    device_type VARCHAR(32) NOT NULL DEFAULT 'raspberry_pi',
    serial_number VARCHAR(128),
    local_ip VARCHAR(64),
    control_base_url TEXT,
    firmware_version VARCHAR(64),
    status VARCHAR(32) NOT NULL DEFAULT 'offline',
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_devices_type CHECK (device_type IN ('raspberry_pi')),
    CONSTRAINT chk_devices_status CHECK (status IN ('offline', 'online', 'busy', 'disabled'))
);

CREATE TABLE IF NOT EXISTS templates (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    template_type VARCHAR(32) NOT NULL DEFAULT 'pose',
    source_image_url TEXT,
    preview_image_url TEXT,
    template_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_templates_type CHECK (template_type IN ('pose', 'background', 'composition')),
    CONSTRAINT chk_templates_status CHECK (status IN ('active', 'archived', 'deleted'))
);

CREATE TABLE IF NOT EXISTS capture_sessions (
    id BIGSERIAL PRIMARY KEY,
    session_code VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id BIGINT REFERENCES devices(id) ON DELETE SET NULL,
    template_id BIGINT REFERENCES templates(id) ON DELETE SET NULL,
    mode VARCHAR(32) NOT NULL DEFAULT 'mobile_only',
    status VARCHAR(32) NOT NULL DEFAULT 'opened',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_capture_sessions_mode CHECK (
        mode IN ('mobile_only', 'device_link', 'MANUAL', 'AUTO_TRACK', 'SMART_COMPOSE')
    ),
    CONSTRAINT chk_capture_sessions_status CHECK (status IN ('opened', 'closed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS captures (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT NOT NULL REFERENCES capture_sessions(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    capture_type VARCHAR(32) NOT NULL DEFAULT 'single',
    file_url TEXT NOT NULL,
    thumbnail_url TEXT,
    width INTEGER,
    height INTEGER,
    storage_provider VARCHAR(32) NOT NULL DEFAULT 'local',
    is_ai_selected BOOLEAN NOT NULL DEFAULT FALSE,
    score NUMERIC(5, 2),
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_captures_type CHECK (capture_type IN ('single', 'photo', 'burst', 'best', 'background')),
    CONSTRAINT chk_captures_dimensions CHECK (
        (width IS NULL OR width > 0) AND
        (height IS NULL OR height > 0)
    )
);

CREATE TABLE IF NOT EXISTS ai_tasks (
    id BIGSERIAL PRIMARY KEY,
    task_code VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id BIGINT REFERENCES capture_sessions(id) ON DELETE SET NULL,
    capture_id BIGINT REFERENCES captures(id) ON DELETE SET NULL,
    device_id BIGINT REFERENCES devices(id) ON DELETE SET NULL,
    task_type VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    provider_name VARCHAR(100),
    request_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    response_payload JSONB,
    result_summary TEXT,
    result_score NUMERIC(5, 2),
    recommended_pan_delta NUMERIC(8, 2),
    recommended_tilt_delta NUMERIC(8, 2),
    target_box_norm JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    CONSTRAINT chk_ai_tasks_type CHECK (
        task_type IN ('analyze_photo', 'analyze_background', 'analyze_template', 'batch_pick', 'auto_angle', 'background_lock')
    ),
    CONSTRAINT chk_ai_tasks_status CHECK (
        status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')
    )
);

CREATE TABLE IF NOT EXISTS ai_provider_configs (
    id BIGSERIAL PRIMARY KEY,
    provider_code VARCHAR(64) NOT NULL UNIQUE,
    vendor_name VARCHAR(64) NOT NULL DEFAULT 'custom',
    provider_format VARCHAR(32) NOT NULL DEFAULT 'openai_compatible',
    display_name VARCHAR(100) NOT NULL,
    api_base_url TEXT,
    api_key TEXT,
    model_name VARCHAR(120),
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    extra_config JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ai_provider_configs_format CHECK (
        provider_format IN ('openai_compatible', 'anthropic_compatible', 'custom')
    )
);

CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_plans_status ON plans(status);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status ON user_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_templates_user_id ON templates(user_id);
CREATE INDEX IF NOT EXISTS idx_templates_status ON templates(status);
CREATE INDEX IF NOT EXISTS idx_capture_sessions_user_id ON capture_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_capture_sessions_device_id ON capture_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_capture_sessions_status ON capture_sessions(status);
CREATE INDEX IF NOT EXISTS idx_captures_session_id ON captures(session_id);
CREATE INDEX IF NOT EXISTS idx_captures_user_id ON captures(user_id);
CREATE INDEX IF NOT EXISTS idx_captures_type ON captures(capture_type);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_user_id ON ai_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_session_id ON ai_tasks(session_id);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_capture_id ON ai_tasks(capture_id);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_status ON ai_tasks(status);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_type ON ai_tasks(task_type);
CREATE INDEX IF NOT EXISTS idx_ai_provider_configs_provider_code ON ai_provider_configs(provider_code);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_plans_updated_at ON plans;
CREATE TRIGGER trg_plans_updated_at
BEFORE UPDATE ON plans
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_user_subscriptions_updated_at ON user_subscriptions;
CREATE TRIGGER trg_user_subscriptions_updated_at
BEFORE UPDATE ON user_subscriptions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_devices_updated_at ON devices;
CREATE TRIGGER trg_devices_updated_at
BEFORE UPDATE ON devices
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_templates_updated_at ON templates;
CREATE TRIGGER trg_templates_updated_at
BEFORE UPDATE ON templates
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_capture_sessions_updated_at ON capture_sessions;
CREATE TRIGGER trg_capture_sessions_updated_at
BEFORE UPDATE ON capture_sessions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_captures_updated_at ON captures;
CREATE TRIGGER trg_captures_updated_at
BEFORE UPDATE ON captures
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_ai_tasks_updated_at ON ai_tasks;
CREATE TRIGGER trg_ai_tasks_updated_at
BEFORE UPDATE ON ai_tasks
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_ai_provider_configs_updated_at ON ai_provider_configs;
CREATE TRIGGER trg_ai_provider_configs_updated_at
BEFORE UPDATE ON ai_provider_configs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
