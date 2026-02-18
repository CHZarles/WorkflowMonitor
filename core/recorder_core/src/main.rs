use axum::{
    extract::{Path, Query, State},
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post},
    Json, Router,
};
use clap::Parser;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    net::{IpAddr, SocketAddr},
    path::PathBuf,
    sync::Arc,
};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tokio::sync::Mutex;
use tower_http::cors::CorsLayer;
use tracing::{error, info};

const DEFAULT_PORT: u16 = 17600;
const TZ_OFFSET_MINUTES_MIN: i32 = -14 * 60;
const TZ_OFFSET_MINUTES_MAX: i32 = 14 * 60;
// How long a tab/domain attribution remains valid while a browser app stays focused.
// This must be >= browser extension heartbeat (default 60s), with slack for MV3 background throttling.
const DOMAIN_FRESHNESS_SECONDS: i64 = 300;
const AUDIO_IDLE_CUTOFF_SECONDS: i64 = 120;

#[derive(Parser, Debug)]
#[command(name = "recorder_core", version)]
struct Args {
    /// Listen address.
    ///
    /// Accepts:
    /// - ip:port (recommended), e.g. 127.0.0.1:17600
    /// - ip (implies port 17600), e.g. 127.0.0.1
    ///
    /// In WSL, if Windows cannot reach it via localhost, try 0.0.0.0:17600.
    #[arg(long, default_value = "127.0.0.1:17600")]
    listen: String,

    /// SQLite database path.
    #[arg(long, default_value = "./data/recorder-core.db")]
    db: PathBuf,

    /// Block length in seconds.
    #[arg(long, default_value_t = 45 * 60)]
    block_seconds: i64,

    /// Idle cutoff for attributing duration between events (seconds).
    #[arg(long, default_value_t = 5 * 60)]
    idle_cutoff_seconds: i64,
}

#[derive(Clone)]
struct AppState {
    conn: Arc<Mutex<Connection>>,
    settings: Arc<Mutex<Settings>>,
}

#[derive(Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
struct Settings {
    block_seconds: i64,
    idle_cutoff_seconds: i64,
    store_titles: bool,
    store_exe_path: bool,
}

#[derive(Serialize)]
struct OkResponse<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
}

#[derive(Serialize)]
struct ErrResponse {
    ok: bool,
    error: &'static str,
}

#[derive(Deserialize)]
struct IngestEvent {
    v: i32,
    ts: String,
    source: String,
    event: String,
    #[serde(default)]
    domain: Option<String>,
    #[serde(default)]
    app: Option<String>,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    browser: Option<String>,
    #[serde(rename = "tabId", default)]
    #[allow(dead_code)]
    tab_id: Option<i64>,
    #[serde(rename = "windowId", default)]
    #[allow(dead_code)]
    window_id: Option<i64>,
    #[serde(flatten)]
    #[allow(dead_code)]
    extra: HashMap<String, Value>,
}

#[derive(Clone, Serialize)]
struct EventRecord {
    id: i64,
    ts: String,
    source: String,
    event: String,
    entity: Option<String>,
    title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    activity: Option<String>,
}

#[derive(Deserialize)]
struct EventsQuery {
    #[serde(default = "default_limit")]
    limit: usize,
}

fn default_limit() -> usize {
    50
}

#[derive(Deserialize)]
struct NowQuery {
    #[serde(default = "default_now_limit")]
    limit: usize,
}

fn default_now_limit() -> usize {
    200
}

#[derive(Serialize)]
struct NowSnapshot {
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_event_id: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    app_active: Option<EventRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tab_focus: Option<EventRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tab_audio: Option<EventRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tab_audio_stop: Option<EventRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    app_audio: Option<EventRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    app_audio_stop: Option<EventRecord>,
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    latest_titles: HashMap<String, String>, // key: "app|<entity>" or "domain|<hostname>"
}

#[derive(Deserialize)]
struct BlocksQuery {
    /// Date in YYYY-MM-DD.
    date: Option<String>,
    /// Client local offset minutes, e.g. 480 for UTC+8.
    tz_offset_minutes: Option<i32>,
}

#[derive(Serialize)]
struct TrackingStatus {
    paused: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    paused_until_ts: Option<String>,
    updated_at: String,
}

#[derive(Deserialize)]
struct PauseRequest {
    #[serde(default)]
    minutes: Option<i64>,
    #[serde(default)]
    until_ts: Option<String>,
}

#[derive(Deserialize)]
struct SettingsUpdate {
    #[serde(default)]
    block_seconds: Option<i64>,
    #[serde(default)]
    idle_cutoff_seconds: Option<i64>,
    #[serde(default)]
    store_titles: Option<bool>,
    #[serde(default)]
    store_exe_path: Option<bool>,
}

#[derive(Deserialize)]
struct BlockDeleteRequest {
    #[serde(default)]
    block_id: Option<String>,
    #[serde(default)]
    start_ts: Option<String>,
    #[serde(default)]
    end_ts: Option<String>,
}

#[derive(Serialize)]
struct DeleteRangeResult {
    start_ts: String,
    end_ts: String,
    events_deleted: i64,
    reviews_deleted: i64,
}

#[derive(Deserialize)]
struct DeleteDayRequest {
    date: String,
    #[serde(default)]
    tz_offset_minutes: Option<i32>,
}

#[derive(Serialize)]
struct DeleteDayResult {
    date: String,
    tz_offset_minutes: i32,
    start_ts: String,
    end_ts: String,
    events_deleted: i64,
    reviews_deleted: i64,
}

#[derive(Serialize)]
struct WipeAllResult {
    events_deleted: i64,
    reviews_deleted: i64,
}

#[derive(Clone, Serialize)]
struct TopItem {
    kind: String,
    name: String,
    seconds: i64,
}

#[derive(Clone, Serialize)]
struct BlockReview {
    skipped: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    skip_reason: Option<String>,
    doing: Option<String>,
    output: Option<String>,
    next: Option<String>,
    tags: Vec<String>,
    updated_at: String,
}

#[derive(Clone, Serialize)]
struct BlockSummary {
    id: String,
    start_ts: String,
    end_ts: String,
    total_seconds: i64,
    top_items: Vec<TopItem>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    background_top_items: Vec<TopItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    background_seconds: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    review: Option<BlockReview>,
}

#[derive(Serialize)]
struct TimelineSegment {
    kind: String,   // "app" | "domain"
    entity: String, // app id or hostname
    #[serde(skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    activity: Option<String>, // "focus" | "audio"
    start_ts: String,
    end_ts: String,
    seconds: i64,
}

#[derive(Deserialize)]
struct ReviewUpsert {
    block_id: String,
    #[serde(default)]
    skipped: bool,
    #[serde(default)]
    skip_reason: Option<String>,
    #[serde(default)]
    doing: Option<String>,
    #[serde(default)]
    output: Option<String>,
    #[serde(default)]
    next: Option<String>,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(Serialize)]
struct PrivacyRuleRow {
    id: i64,
    kind: String,
    value: String,
    action: String,
    created_at: String,
}

#[derive(Deserialize)]
struct PrivacyRuleUpsert {
    kind: String,
    value: String,
    action: String,
}

#[derive(Default)]
struct PrivacyIndex {
    // (kind, value) -> action ("drop" | "mask")
    action_by_kind_value: HashMap<(String, String), String>,
}

impl PrivacyIndex {
    fn load(conn: &mut Connection) -> rusqlite::Result<Self> {
        let rules = list_privacy_rules(conn)?;
        let mut idx = PrivacyIndex::default();
        for r in rules {
            idx.action_by_kind_value
                .insert((r.kind, r.value), r.action);
        }
        Ok(idx)
    }

    fn decision_for(&self, event: &str, entity: &str) -> PrivacyDecision {
        let kind = privacy_kind_for_event(event);
        let value = if kind == "domain" {
            entity.trim().to_lowercase()
        } else {
            entity.trim().to_string()
        };
        match self
            .action_by_kind_value
            .get(&(kind.to_string(), value))
            .map(|s| s.as_str())
        {
            Some("drop") => PrivacyDecision::Drop,
            Some("mask") => PrivacyDecision::Mask,
            _ => PrivacyDecision::Allow,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum PrivacyDecision {
    Allow,
    Drop,
    Mask,
}

fn privacy_kind_for_event(event: &str) -> &'static str {
    match event {
        "tab_active" | "tab_audio_stop" => "domain",
        "app_active" | "app_audio" | "app_audio_stop" => "app",
        _ => "app",
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "recorder_core=info,tower_http=info".into()),
        )
        .init();

    let args = Args::parse();
    let default_settings = Settings {
        block_seconds: args.block_seconds,
        idle_cutoff_seconds: args.idle_cutoff_seconds,
        store_titles: false,
        store_exe_path: false,
    };

    if let Some(parent) = args.db.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let mut conn = Connection::open(&args.db)?;
    init_db(&conn)?;
    let settings = load_or_init_settings(&mut conn, default_settings)?;

    let state = AppState {
        conn: Arc::new(Mutex::new(conn)),
        settings: Arc::new(Mutex::new(settings)),
    };

    let cors = CorsLayer::new()
        .allow_origin(HeaderValue::from_static("*"))
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([axum::http::header::CONTENT_TYPE]);

    let app = Router::new()
        .route("/health", get(health))
        .route("/event", post(post_event).options(options_ok))
        .route("/events", get(get_events))
        .route("/now", get(get_now))
        .route("/tracking/status", get(get_tracking_status))
        .route("/tracking/pause", post(post_tracking_pause).options(options_ok))
        .route("/tracking/resume", post(post_tracking_resume).options(options_ok))
        .route(
            "/settings",
            get(get_settings).post(post_settings).options(options_ok),
        )
        .route("/timeline/day", get(get_timeline_day))
        .route("/blocks/today", get(get_blocks_today))
        .route("/blocks/due", get(get_blocks_due))
        .route("/blocks/review", post(post_block_review).options(options_ok))
        .route("/blocks/delete", post(post_block_delete).options(options_ok))
        .route(
            "/privacy/rules",
            get(get_privacy_rules)
                .post(post_privacy_rule)
                .options(options_ok),
        )
        .route(
            "/privacy/rules/:id",
            delete(delete_privacy_rule).options(options_ok),
        )
        .route(
            "/data/delete_day",
            post(post_data_delete_day).options(options_ok),
        )
        .route("/data/wipe", post(post_data_wipe).options(options_ok))
        .route("/export/markdown", get(get_export_markdown))
        .route("/export/csv", get(get_export_csv))
        .with_state(state)
        .layer(cors);

    let addr = parse_listen(&args.listen)?;
    info!("Core listening on http://{addr}");
    info!("DB: {}", args.db.display());

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

fn parse_listen(input: &str) -> anyhow::Result<SocketAddr> {
    if let Ok(addr) = input.parse::<SocketAddr>() {
        return Ok(addr);
    }

    if let Ok(ip) = input.parse::<IpAddr>() {
        return Ok(SocketAddr::new(ip, DEFAULT_PORT));
    }

    // Support host:port for localhost (handy for docs/UX).
    if let Some((host, port_str)) = input.rsplit_once(':') {
        if host == "localhost" {
            let port: u16 = port_str.parse().map_err(|_| {
                anyhow::anyhow!(
                    "invalid --listen '{}': bad port. Example: 127.0.0.1:{}",
                    input,
                    DEFAULT_PORT
                )
            })?;
            return Ok(SocketAddr::new(IpAddr::from([127, 0, 0, 1]), port));
        }

        // Also accept IPv6 without brackets (best effort): ::1:17600
        if let Ok(ip) = host.parse::<IpAddr>() {
            let port: u16 = port_str.parse().map_err(|_| {
                anyhow::anyhow!(
                    "invalid --listen '{}': bad port. Example: 127.0.0.1:{}",
                    input,
                    DEFAULT_PORT
                )
            })?;
            return Ok(SocketAddr::new(ip, port));
        }
    }

    if input == "localhost" {
        return Ok(SocketAddr::new(IpAddr::from([127, 0, 0, 1]), DEFAULT_PORT));
    }

    Err(anyhow::anyhow!(
        "invalid --listen '{}'. Use ip:port (e.g. 127.0.0.1:{}) or ip (e.g. 127.0.0.1).",
        input,
        DEFAULT_PORT
    ))
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    info!("shutdown requested");
}

async fn options_ok() -> impl IntoResponse {
    StatusCode::OK
}

#[derive(Serialize)]
struct HealthInfo {
    service: &'static str,
    version: &'static str,
}

async fn health() -> impl IntoResponse {
    Json(OkResponse {
        ok: true,
        data: Some(HealthInfo {
            service: "recorder_core",
            version: env!("CARGO_PKG_VERSION"),
        }),
    })
}

async fn post_event(State(state): State<AppState>, Json(payload): Json<Value>) -> Response {
    let e: IngestEvent = match serde_json::from_value(payload.clone()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_json",
                }),
            )
                .into_response();
        }
    };

    if e.v < 1 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "invalid_version",
            }),
        )
            .into_response();
    }

    // Validate timestamp format early (store as-is, but ensure parseable).
    if OffsetDateTime::parse(&e.ts, &Rfc3339).is_err() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "invalid_ts",
            }),
        )
            .into_response();
    }

    // Minimal event validation:
    // - tab_active/tab_audio_stop requires domain
    // - app_active/app_audio/app_audio_stop requires app
    let mut entity = match e.event.as_str() {
        "tab_active" => e.domain.clone().filter(|d| !d.trim().is_empty()),
        "app_active" => e.app.clone().filter(|a| !a.trim().is_empty()),
        _ => e
            .domain
            .clone()
            .filter(|d| !d.trim().is_empty())
            .or_else(|| e.app.clone().filter(|a| !a.trim().is_empty())),
    };
    if e.event == "tab_active" && entity.is_none() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_domain",
            }),
        )
            .into_response();
    }
    if e.event == "tab_audio_stop" && entity.is_none() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_domain",
            }),
        )
            .into_response();
    }
    if (e.event == "app_active" || e.event == "app_audio" || e.event == "app_audio_stop")
        && entity.is_none()
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_app",
            }),
        )
            .into_response();
    }

    let mut title = e.title.clone();
    let mut payload_to_store = payload;

    let settings = { *state.settings.lock().await };

    let mut conn = state.conn.lock().await;

    match tracking_is_paused(&mut conn, OffsetDateTime::now_utc()) {
        Ok(true) => {
            return Json(OkResponse::<Value> { ok: true, data: None }).into_response();
        }
        Ok(false) => {}
        Err(err) => {
            error!("tracking_is_paused failed: {err}");
        }
    }

    // Apply privacy rules (exact match, MVP).
    if let Some(action) = match privacy_action_for_event(&mut conn, &e) {
        Ok(v) => v,
        Err(err) => {
            error!("privacy_action_for_event failed: {err}");
            None
        }
    } {
        match action.as_str() {
            "drop" => {
                return Json(OkResponse::<Value> { ok: true, data: None }).into_response();
            }
            "mask" => {
                entity = Some("__hidden__".to_string());
                title = None;
                if let Some(obj) = payload_to_store.as_object_mut() {
                    obj.insert("masked".to_string(), Value::Bool(true));
                    // Mask all supported entity fields, not just specific event types.
                    // (e.g. tab_audio_stop/app_audio must not leak their domain/app in payload_json.)
                    if obj.contains_key("domain") {
                        obj.insert("domain".to_string(), Value::String("__hidden__".to_string()));
                        obj.remove("title");
                    }
                    if obj.contains_key("app") {
                        obj.insert("app".to_string(), Value::String("__hidden__".to_string()));
                        obj.remove("title");
                        obj.remove("exePath");
                        obj.remove("pid");
                    }
                }
            }
            _ => {}
        }
    }

    // Apply global privacy settings (L1/L2). Even if collectors/extensions send more fields,
    // the Core controls what is actually persisted.
    if !settings.store_titles {
        title = None;
        if let Some(obj) = payload_to_store.as_object_mut() {
            obj.remove("title");
        }
    }
    if !settings.store_exe_path {
        if let Some(obj) = payload_to_store.as_object_mut() {
            obj.remove("exePath");
            obj.remove("pid");
        }
    }

    let payload_json = match serde_json::to_string(&payload_to_store) {
        Ok(s) => s,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_json",
                }),
            )
                .into_response();
        }
    };

    if let Err(err) = insert_event(
        &mut conn,
        &e,
        entity.as_deref(),
        title.as_deref(),
        &payload_json,
    ) {
        error!("insert_event failed: {err}");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrResponse {
                ok: false,
                error: "db_error",
            }),
        )
            .into_response();
    }

    Json(OkResponse::<Value> { ok: true, data: None }).into_response()
}

async fn get_events(State(state): State<AppState>, Query(q): Query<EventsQuery>) -> Response {
    let limit = q.limit.clamp(1, 500);
    let mut conn = state.conn.lock().await;
    let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
    match list_events(&mut conn, limit, &privacy) {
        Ok(events) => Json(OkResponse {
            ok: true,
            data: Some(events),
        })
        .into_response(),
        Err(err) => {
            error!("list_events failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn get_now(State(state): State<AppState>, Query(q): Query<NowQuery>) -> Response {
    let limit = q.limit.clamp(1, 2000);
    let mut conn = state.conn.lock().await;
    let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();

    let events = match list_events(&mut conn, limit, &privacy) {
        Ok(v) => v,
        Err(err) => {
            error!("list_events for /now failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    let latest_event_id = events.first().map(|e| e.id);
    let mut app_active: Option<EventRecord> = None;
    let mut tab_focus: Option<EventRecord> = None;
    let mut tab_audio: Option<EventRecord> = None;
    let mut tab_audio_stop: Option<EventRecord> = None;
    let mut app_audio: Option<EventRecord> = None;
    let mut app_audio_stop: Option<EventRecord> = None;

    let mut latest_titles: HashMap<String, String> = HashMap::new();

    for e in &events {
        if app_active.is_none() && e.event == "app_active" {
            app_active = Some(e.clone());
        }
        if tab_focus.is_none() && e.event == "tab_active" && e.activity.as_deref() != Some("audio") {
            tab_focus = Some(e.clone());
        }
        if tab_audio.is_none() && e.event == "tab_active" && e.activity.as_deref() == Some("audio") {
            tab_audio = Some(e.clone());
        }
        if tab_audio_stop.is_none() && e.event == "tab_audio_stop" {
            tab_audio_stop = Some(e.clone());
        }
        if app_audio.is_none() && e.event == "app_audio" {
            app_audio = Some(e.clone());
        }
        if app_audio_stop.is_none() && e.event == "app_audio_stop" {
            app_audio_stop = Some(e.clone());
        }

        if let (Some(entity), Some(title)) = (e.entity.as_deref(), e.title.as_deref()) {
            let ent = entity.trim();
            let t = title.trim();
            if !ent.is_empty() && !t.is_empty() {
                if e.event == "tab_active" {
                    latest_titles
                        .entry(format!("domain|{}", ent.to_lowercase()))
                        .or_insert_with(|| t.to_string());
                } else if e.event == "app_active" {
                    latest_titles
                        .entry(format!("app|{}", ent))
                        .or_insert_with(|| t.to_string());
                }
            }
        }

        if app_active.is_some()
            && tab_focus.is_some()
            && tab_audio.is_some()
            && tab_audio_stop.is_some()
            && app_audio.is_some()
            && app_audio_stop.is_some()
            && latest_titles.len() >= 64
        {
            break;
        }
    }

    Json(OkResponse {
        ok: true,
        data: Some(NowSnapshot {
            latest_event_id,
            app_active,
            tab_focus,
            tab_audio,
            tab_audio_stop,
            app_audio,
            app_audio_stop,
            latest_titles,
        }),
    })
    .into_response()
}

async fn get_tracking_status(State(state): State<AppState>) -> Response {
    let now = OffsetDateTime::now_utc();
    let mut conn = state.conn.lock().await;
    if let Err(err) = tracking_is_paused(&mut conn, now) {
        error!("tracking_is_paused failed: {err}");
    }

    match load_tracking_status(&mut conn) {
        Ok(status) => Json(OkResponse {
            ok: true,
            data: Some(status),
        })
        .into_response(),
        Err(err) => {
            error!("load_tracking_status failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn post_tracking_pause(
    State(state): State<AppState>,
    Json(req): Json<PauseRequest>,
) -> Response {
    let now = OffsetDateTime::now_utc();
    let updated_at = now.format(&Rfc3339).unwrap_or_default();

    let paused_until_ts = if let Some(until_ts) = req.until_ts.as_deref() {
        if OffsetDateTime::parse(until_ts, &Rfc3339).is_err() {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_until_ts",
                }),
            )
                .into_response();
        }
        Some(until_ts.to_string())
    } else if let Some(minutes) = req.minutes {
        if minutes <= 0 {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_minutes",
                }),
            )
                .into_response();
        }
        let until = now + time::Duration::minutes(minutes);
        Some(until.format(&Rfc3339).unwrap_or_default())
    } else {
        None
    };

    let mut conn = state.conn.lock().await;
    if let Err(err) =
        set_tracking_pause(&mut conn, paused_until_ts.as_deref(), &updated_at)
    {
        error!("set_tracking_pause failed: {err}");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrResponse {
                ok: false,
                error: "db_error",
            }),
        )
            .into_response();
    }

    match load_tracking_status(&mut conn) {
        Ok(status) => Json(OkResponse {
            ok: true,
            data: Some(status),
        })
        .into_response(),
        Err(err) => {
            error!("load_tracking_status failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn post_tracking_resume(State(state): State<AppState>) -> Response {
    let now = OffsetDateTime::now_utc();
    let updated_at = now.format(&Rfc3339).unwrap_or_default();

    let mut conn = state.conn.lock().await;
    if let Err(err) = set_tracking_resume(&mut conn, &updated_at) {
        error!("set_tracking_resume failed: {err}");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrResponse {
                ok: false,
                error: "db_error",
            }),
        )
            .into_response();
    }

    match load_tracking_status(&mut conn) {
        Ok(status) => Json(OkResponse {
            ok: true,
            data: Some(status),
        })
        .into_response(),
        Err(err) => {
            error!("load_tracking_status failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn get_settings(State(state): State<AppState>) -> Response {
    let settings = { *state.settings.lock().await };
    Json(OkResponse {
        ok: true,
        data: Some(settings),
    })
    .into_response()
}

async fn post_settings(State(state): State<AppState>, Json(req): Json<SettingsUpdate>) -> Response {
    if let Some(block_seconds) = req.block_seconds {
        if block_seconds < 60 {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_block_seconds",
                }),
            )
                .into_response();
        }
    }
    if let Some(idle_cutoff_seconds) = req.idle_cutoff_seconds {
        if idle_cutoff_seconds < 10 {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_idle_cutoff_seconds",
                }),
            )
                .into_response();
        }
    }

    let mut settings = { *state.settings.lock().await };
    if let Some(v) = req.block_seconds {
        settings.block_seconds = v;
    }
    if let Some(v) = req.idle_cutoff_seconds {
        settings.idle_cutoff_seconds = v;
    }
    if let Some(v) = req.store_titles {
        settings.store_titles = v;
    }
    if let Some(v) = req.store_exe_path {
        settings.store_exe_path = v;
    }

    let updated_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
    {
        let mut conn = state.conn.lock().await;
        if let Err(err) = upsert_app_settings(&mut conn, settings, &updated_at) {
            error!("upsert_app_settings failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    }

    {
        let mut guard = state.settings.lock().await;
        *guard = settings;
    }

    Json(OkResponse {
        ok: true,
        data: Some(settings),
    })
    .into_response()
}

async fn get_blocks_today(State(state): State<AppState>, Query(q): Query<BlocksQuery>) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(q.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let date = match q.date {
        Some(s) => s,
        None => OffsetDateTime::now_utc()
            .to_offset(tz_offset)
            .date()
            .to_string(),
    };

    let day_start = match parse_day_start_utc_for_offset(&date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let events = {
        let mut conn = state.conn.lock().await;
        let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
        match list_events_between(&mut conn, day_start, day_end, &privacy) {
            Ok(v) => v,
            Err(err) => {
                error!("list_events_between failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        }
    };

    let settings = { *state.settings.lock().await };
    let blocks = build_blocks(&events, settings, OffsetDateTime::now_utc().min(day_end));

    let blocks_with_reviews = {
        let mut conn = state.conn.lock().await;
        attach_reviews(&mut conn, blocks).unwrap_or_else(|err| {
            error!("attach_reviews failed: {err}");
            Vec::new()
        })
    };

    Json(OkResponse {
        ok: true,
        data: Some(blocks_with_reviews),
    })
    .into_response()
}

fn block_is_reviewed(r: &BlockReview) -> bool {
    if r.skipped {
        return true;
    }
    if !r.doing.as_deref().unwrap_or("").trim().is_empty() {
        return true;
    }
    if !r.output.as_deref().unwrap_or("").trim().is_empty() {
        return true;
    }
    if !r.next.as_deref().unwrap_or("").trim().is_empty() {
        return true;
    }
    !r.tags.is_empty()
}

fn find_due_block(blocks: &[BlockSummary], block_seconds: i64, now: OffsetDateTime) -> Option<BlockSummary> {
    if blocks.is_empty() {
        return None;
    }
    let min_seconds = 5 * 60;

    for i in (0..blocks.len()).rev() {
        let b = &blocks[i];
        if b.total_seconds < min_seconds {
            continue;
        }
        if let Some(r) = &b.review {
            if block_is_reviewed(r) {
                continue;
            }
        }

        let has_next = i < blocks.len() - 1;
        if has_next {
            return Some(b.clone());
        }

        if b.total_seconds >= block_seconds {
            return Some(b.clone());
        }

        if let Ok(end) = OffsetDateTime::parse(&b.end_ts, &Rfc3339) {
            if now - end > time::Duration::seconds(30) {
                return Some(b.clone());
            }
        }
    }

    None
}

async fn get_blocks_due(State(state): State<AppState>, Query(q): Query<BlocksQuery>) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(q.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let date = match q.date {
        Some(s) => s,
        None => OffsetDateTime::now_utc()
            .to_offset(tz_offset)
            .date()
            .to_string(),
    };

    let day_start = match parse_day_start_utc_for_offset(&date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let now = OffsetDateTime::now_utc().min(day_end);

    let events = {
        let mut conn = state.conn.lock().await;
        let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
        match list_events_between(&mut conn, day_start, day_end, &privacy) {
            Ok(v) => v,
            Err(err) => {
                error!("list_events_between failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        }
    };

    let settings = { *state.settings.lock().await };
    let blocks = build_blocks(&events, settings, now);

    let blocks_with_reviews = {
        let mut conn = state.conn.lock().await;
        attach_reviews(&mut conn, blocks).unwrap_or_else(|err| {
            error!("attach_reviews failed: {err}");
            Vec::new()
        })
    };

    let due = find_due_block(&blocks_with_reviews, settings.block_seconds.max(60), now);

    Json(OkResponse { ok: true, data: due }).into_response()
}

async fn get_timeline_day(State(state): State<AppState>, Query(q): Query<BlocksQuery>) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(q.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let date = match q.date {
        Some(s) => s,
        None => OffsetDateTime::now_utc()
            .to_offset(tz_offset)
            .date()
            .to_string(),
    };

    let day_start = match parse_day_start_utc_for_offset(&date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let events = {
        let mut conn = state.conn.lock().await;
        let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
        match list_events_between(&mut conn, day_start, day_end, &privacy) {
            Ok(v) => v,
            Err(err) => {
                error!("list_events_between failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        }
    };

    let settings = { *state.settings.lock().await };
    let segments = build_timeline_segments(&events, settings, OffsetDateTime::now_utc().min(day_end));

    Json(OkResponse {
        ok: true,
        data: Some(segments),
    })
    .into_response()
}

async fn post_block_review(State(state): State<AppState>, Json(r): Json<ReviewUpsert>) -> Response {
    if r.block_id.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_block_id",
            }),
        )
            .into_response();
    }

    let updated_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_else(|_| r.block_id.clone());
    let tags_json = serde_json::to_string(&r.tags).unwrap_or_else(|_| "[]".to_string());
    let skip_reason = if r.skipped {
        r.skip_reason
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToString::to_string)
    } else {
        None
    };

    let mut conn = state.conn.lock().await;
    if let Err(err) = upsert_review(&mut conn, &r, skip_reason.as_deref(), &tags_json, &updated_at) {
        error!("upsert_review failed: {err}");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrResponse {
                ok: false,
                error: "db_error",
            }),
        )
            .into_response();
    }

    Json(OkResponse::<Value> { ok: true, data: None }).into_response()
}

async fn post_block_delete(
    State(state): State<AppState>,
    Json(req): Json<BlockDeleteRequest>,
) -> Response {
    let start_ts = req
        .start_ts
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .or_else(|| req.block_id.as_deref().filter(|s| !s.trim().is_empty()));

    let start_ts = match start_ts {
        Some(s) => s,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "missing_start_ts",
                }),
            )
                .into_response();
        }
    };

    let start = match OffsetDateTime::parse(start_ts, &Rfc3339) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_start_ts",
                }),
            )
                .into_response();
        }
    };

    let end = if let Some(end_ts) = req.end_ts.as_deref().filter(|s| !s.trim().is_empty()) {
        match OffsetDateTime::parse(end_ts, &Rfc3339) {
            Ok(t) => t,
            Err(_) => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ErrResponse {
                        ok: false,
                        error: "invalid_end_ts",
                    }),
                )
                    .into_response();
            }
        }
    } else {
        let settings = { *state.settings.lock().await };
        start + time::Duration::seconds(settings.block_seconds.max(60))
    };

    if end <= start {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "invalid_range",
            }),
        )
            .into_response();
    }

    let start_s = start.format(&Rfc3339).unwrap_or_default();
    let end_s = end.format(&Rfc3339).unwrap_or_default();

    let conn = state.conn.lock().await;
    let events_deleted = match conn.execute(
        "DELETE FROM events WHERE ts >= ?1 AND ts < ?2",
        (&start_s, &end_s),
    ) {
        Ok(n) => n as i64,
        Err(err) => {
            error!("delete events failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    let reviews_deleted =
        match conn.execute("DELETE FROM block_reviews WHERE block_id = ?1", [&start_s]) {
            Ok(n) => n as i64,
            Err(err) => {
                error!("delete block_review failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        };

    Json(OkResponse {
        ok: true,
        data: Some(DeleteRangeResult {
            start_ts: start_s,
            end_ts: end_s,
            events_deleted,
            reviews_deleted,
        }),
    })
    .into_response()
}

async fn get_privacy_rules(State(state): State<AppState>) -> Response {
    let mut conn = state.conn.lock().await;
    match list_privacy_rules(&mut conn) {
        Ok(rules) => Json(OkResponse {
            ok: true,
            data: Some(rules),
        })
        .into_response(),
        Err(err) => {
            error!("list_privacy_rules failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn post_privacy_rule(State(state): State<AppState>, Json(r): Json<PrivacyRuleUpsert>) -> Response {
    let kind = r.kind.trim().to_lowercase();
    let action = r.action.trim().to_lowercase();
    let mut value = r.value.trim().to_string();

    if kind.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_kind",
            }),
        )
            .into_response();
    }
    if value.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrResponse {
                ok: false,
                error: "missing_value",
            }),
        )
            .into_response();
    }

    match kind.as_str() {
        "domain" => {
            value = value.to_lowercase();
        }
        "app" => {}
        _ => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_kind",
                }),
            )
                .into_response();
        }
    }

    match action.as_str() {
        "drop" | "mask" => {}
        _ => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_action",
                }),
            )
                .into_response();
        }
    }

    let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();

    let mut conn = state.conn.lock().await;
    match upsert_privacy_rule(&mut conn, &kind, &value, &action, &created_at) {
        Ok(rule) => Json(OkResponse {
            ok: true,
            data: Some(rule),
        })
        .into_response(),
        Err(err) => {
            error!("upsert_privacy_rule failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn delete_privacy_rule(State(state): State<AppState>, Path(id): Path<i64>) -> Response {
    let mut conn = state.conn.lock().await;
    match delete_privacy_rule_by_id(&mut conn, id) {
        Ok(0) => (
            StatusCode::NOT_FOUND,
            Json(ErrResponse {
                ok: false,
                error: "not_found",
            }),
        )
            .into_response(),
        Ok(_) => Json(OkResponse::<Value> { ok: true, data: None }).into_response(),
        Err(err) => {
            error!("delete_privacy_rule_by_id failed: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response()
        }
    }
}

async fn post_data_delete_day(
    State(state): State<AppState>,
    Json(req): Json<DeleteDayRequest>,
) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(req.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let day_start = match parse_day_start_utc_for_offset(&req.date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let start_s = day_start.format(&Rfc3339).unwrap_or_default();
    let end_s = day_end.format(&Rfc3339).unwrap_or_default();

    let conn = state.conn.lock().await;
    let events_deleted = match conn.execute(
        "DELETE FROM events WHERE ts >= ?1 AND ts < ?2",
        (&start_s, &end_s),
    ) {
        Ok(n) => n as i64,
        Err(err) => {
            error!("delete events failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    let reviews_deleted = match conn.execute(
        "DELETE FROM block_reviews WHERE block_id >= ?1 AND block_id < ?2",
        (&start_s, &end_s),
    ) {
        Ok(n) => n as i64,
        Err(err) => {
            error!("delete block_reviews failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    Json(OkResponse {
        ok: true,
        data: Some(DeleteDayResult {
            date: req.date,
            tz_offset_minutes,
            start_ts: start_s,
            end_ts: end_s,
            events_deleted,
            reviews_deleted,
        }),
    })
    .into_response()
}

async fn post_data_wipe(State(state): State<AppState>) -> Response {
    let conn = state.conn.lock().await;

    let events_deleted = match conn.execute("DELETE FROM events", []) {
        Ok(n) => n as i64,
        Err(err) => {
            error!("wipe events failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    let reviews_deleted = match conn.execute("DELETE FROM block_reviews", []) {
        Ok(n) => n as i64,
        Err(err) => {
            error!("wipe block_reviews failed: {err}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrResponse {
                    ok: false,
                    error: "db_error",
                }),
            )
                .into_response();
        }
    };

    // Best effort: reset AUTOINCREMENT sequence so ids start small again.
    // Ignore errors (sqlite_sequence may not exist depending on build/pragma).
    let _ = conn.execute("DELETE FROM sqlite_sequence WHERE name = 'events'", []);

    Json(OkResponse {
        ok: true,
        data: Some(WipeAllResult {
            events_deleted,
            reviews_deleted,
        }),
    })
    .into_response()
}

#[derive(Deserialize)]
struct ExportQuery {
    date: Option<String>,
    tz_offset_minutes: Option<i32>,
}

async fn get_export_markdown(
    State(state): State<AppState>,
    Query(q): Query<ExportQuery>,
) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(q.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let date = match q.date {
        Some(s) => s,
        None => OffsetDateTime::now_utc()
            .to_offset(tz_offset)
            .date()
            .to_string(),
    };

    let day_start = match parse_day_start_utc_for_offset(&date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let events = {
        let mut conn = state.conn.lock().await;
        let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
        match list_events_between(&mut conn, day_start, day_end, &privacy) {
            Ok(v) => v,
            Err(err) => {
                error!("list_events_between failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        }
    };
    let settings = { *state.settings.lock().await };
    let blocks = build_blocks(&events, settings, OffsetDateTime::now_utc().min(day_end));
    let blocks = {
        let mut conn = state.conn.lock().await;
        attach_reviews(&mut conn, blocks).unwrap_or_default()
    };

    let md = export_markdown(&date, &blocks, tz_offset);
    (
        StatusCode::OK,
        [("content-type", "text/markdown; charset=utf-8")],
        md,
    )
        .into_response()
}

async fn get_export_csv(State(state): State<AppState>, Query(q): Query<ExportQuery>) -> Response {
    let tz_offset_minutes = normalize_tz_offset_minutes(q.tz_offset_minutes);
    let tz_offset = tz_offset_from_minutes(tz_offset_minutes);

    let date = match q.date {
        Some(s) => s,
        None => OffsetDateTime::now_utc()
            .to_offset(tz_offset)
            .date()
            .to_string(),
    };

    let day_start = match parse_day_start_utc_for_offset(&date, tz_offset) {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrResponse {
                    ok: false,
                    error: "invalid_date",
                }),
            )
                .into_response();
        }
    };
    let day_end = day_start + time::Duration::days(1);

    let events = {
        let mut conn = state.conn.lock().await;
        let privacy = PrivacyIndex::load(&mut conn).unwrap_or_default();
        match list_events_between(&mut conn, day_start, day_end, &privacy) {
            Ok(v) => v,
            Err(err) => {
                error!("list_events_between failed: {err}");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrResponse {
                        ok: false,
                        error: "db_error",
                    }),
                )
                    .into_response();
            }
        }
    };
    let settings = { *state.settings.lock().await };
    let blocks = build_blocks(&events, settings, OffsetDateTime::now_utc().min(day_end));
    let blocks = {
        let mut conn = state.conn.lock().await;
        attach_reviews(&mut conn, blocks).unwrap_or_default()
    };

    let csv = export_csv(&date, &blocks);
    (
        StatusCode::OK,
        [("content-type", "text/csv; charset=utf-8")],
        csv,
    )
        .into_response()
}

fn init_db(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  source TEXT NOT NULL,
  event TEXT NOT NULL,
  entity TEXT,
  title TEXT,
  payload_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);

CREATE TABLE IF NOT EXISTS block_reviews (
  block_id TEXT PRIMARY KEY,
  skipped INTEGER NOT NULL DEFAULT 0,
  skip_reason TEXT,
  doing TEXT,
  output TEXT,
  next TEXT,
  tags_json TEXT,
  updated_at TEXT NOT NULL
);

	CREATE TABLE IF NOT EXISTS app_settings (
	  id INTEGER PRIMARY KEY CHECK (id = 1),
	  block_seconds INTEGER NOT NULL,
	  idle_cutoff_seconds INTEGER NOT NULL,
	  store_titles INTEGER NOT NULL DEFAULT 0,
	  store_exe_path INTEGER NOT NULL DEFAULT 0,
	  updated_at TEXT NOT NULL
	);

CREATE TABLE IF NOT EXISTS privacy_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  value TEXT NOT NULL,
  action TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(kind, value)
);
CREATE INDEX IF NOT EXISTS idx_privacy_rules_kind_value ON privacy_rules(kind, value);

CREATE TABLE IF NOT EXISTS tracking_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  paused INTEGER NOT NULL DEFAULT 0,
  paused_until_ts TEXT,
  updated_at TEXT NOT NULL
);
INSERT INTO tracking_state (id, paused, paused_until_ts, updated_at)
VALUES (1, 0, NULL, '1970-01-01T00:00:00Z')
ON CONFLICT(id) DO NOTHING;
"#,
	    )?;
	    ensure_app_settings_columns(conn)?;
	    ensure_block_reviews_columns(conn)?;
	    Ok(())
}

fn ensure_app_settings_columns(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(app_settings)")?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(1))?;
    let mut cols: HashSet<String> = HashSet::new();
    for r in rows {
        cols.insert(r?);
    }

    if !cols.contains("store_titles") {
        conn.execute(
            "ALTER TABLE app_settings ADD COLUMN store_titles INTEGER NOT NULL DEFAULT 0",
            [],
        )?;
    }
    if !cols.contains("store_exe_path") {
        conn.execute(
            "ALTER TABLE app_settings ADD COLUMN store_exe_path INTEGER NOT NULL DEFAULT 0",
            [],
        )?;
    }

    Ok(())
}

fn ensure_block_reviews_columns(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(block_reviews)")?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(1))?;
    let mut cols: HashSet<String> = HashSet::new();
    for r in rows {
        cols.insert(r?);
    }

    if !cols.contains("skipped") {
        conn.execute(
            "ALTER TABLE block_reviews ADD COLUMN skipped INTEGER NOT NULL DEFAULT 0",
            [],
        )?;
    }
    if !cols.contains("skip_reason") {
        conn.execute("ALTER TABLE block_reviews ADD COLUMN skip_reason TEXT", [])?;
    }

    Ok(())
}

fn load_or_init_settings(conn: &mut Connection, defaults: Settings) -> rusqlite::Result<Settings> {
    if let Some(settings) = load_app_settings(conn)? {
        let fixed = Settings {
            block_seconds: settings.block_seconds.max(60),
            idle_cutoff_seconds: settings.idle_cutoff_seconds.max(10),
            store_titles: settings.store_titles,
            store_exe_path: settings.store_exe_path,
        };
        if fixed != settings {
            let updated_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
            upsert_app_settings(conn, fixed, &updated_at)?;
        }
        return Ok(fixed);
    }

    let fixed = Settings {
        block_seconds: defaults.block_seconds.max(60),
        idle_cutoff_seconds: defaults.idle_cutoff_seconds.max(10),
        store_titles: defaults.store_titles,
        store_exe_path: defaults.store_exe_path,
    };
    let updated_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
    upsert_app_settings(conn, fixed, &updated_at)?;
    Ok(fixed)
}

fn load_app_settings(conn: &mut Connection) -> rusqlite::Result<Option<Settings>> {
    let mut stmt =
        conn.prepare("SELECT block_seconds, idle_cutoff_seconds, store_titles, store_exe_path FROM app_settings WHERE id = 1")?;
    match stmt.query_row([], |row| {
        let store_titles: i64 = row.get(2)?;
        let store_exe_path: i64 = row.get(3)?;
        Ok(Settings {
            block_seconds: row.get(0)?,
            idle_cutoff_seconds: row.get(1)?,
            store_titles: store_titles != 0,
            store_exe_path: store_exe_path != 0,
        })
    }) {
        Ok(v) => Ok(Some(v)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(err) => Err(err),
    }
}

fn upsert_app_settings(
    conn: &mut Connection,
    settings: Settings,
    updated_at: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        r#"
INSERT INTO app_settings (id, block_seconds, idle_cutoff_seconds, store_titles, store_exe_path, updated_at)
VALUES (1, ?1, ?2, ?3, ?4, ?5)
ON CONFLICT(id) DO UPDATE SET
  block_seconds=excluded.block_seconds,
  idle_cutoff_seconds=excluded.idle_cutoff_seconds,
  store_titles=excluded.store_titles,
  store_exe_path=excluded.store_exe_path,
  updated_at=excluded.updated_at
        "#,
        (
            settings.block_seconds,
            settings.idle_cutoff_seconds,
            settings.store_titles as i64,
            settings.store_exe_path as i64,
            updated_at,
        ),
    )?;
    Ok(())
}

fn insert_event(
    conn: &mut Connection,
    e: &IngestEvent,
    entity: Option<&str>,
    title: Option<&str>,
    payload_json: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO events (ts, source, event, entity, title, payload_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        (
            &e.ts,
            &e.source,
            &e.event,
            entity,
            title,
            payload_json,
        ),
    )?;
    Ok(())
}

fn list_privacy_rules(conn: &mut Connection) -> rusqlite::Result<Vec<PrivacyRuleRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, kind, value, action, created_at FROM privacy_rules ORDER BY id DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(PrivacyRuleRow {
            id: row.get(0)?,
            kind: row.get(1)?,
            value: row.get(2)?,
            action: row.get(3)?,
            created_at: row.get(4)?,
        })
    })?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

fn upsert_privacy_rule(
    conn: &mut Connection,
    kind: &str,
    value: &str,
    action: &str,
    created_at: &str,
) -> rusqlite::Result<PrivacyRuleRow> {
    conn.execute(
        r#"
INSERT INTO privacy_rules (kind, value, action, created_at)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(kind, value) DO UPDATE SET
  action=excluded.action
"#,
        (kind, value, action, created_at),
    )?;

    let mut stmt = conn.prepare(
        "SELECT id, kind, value, action, created_at FROM privacy_rules WHERE kind = ?1 AND value = ?2",
    )?;
    stmt.query_row((kind, value), |row| {
        Ok(PrivacyRuleRow {
            id: row.get(0)?,
            kind: row.get(1)?,
            value: row.get(2)?,
            action: row.get(3)?,
            created_at: row.get(4)?,
        })
    })
}

fn delete_privacy_rule_by_id(conn: &mut Connection, id: i64) -> rusqlite::Result<usize> {
    conn.execute("DELETE FROM privacy_rules WHERE id = ?1", [id])
}

fn privacy_action_for_event(
    conn: &mut Connection,
    e: &IngestEvent,
) -> rusqlite::Result<Option<String>> {
    let check = |kind: &str, value: &str| -> rusqlite::Result<Option<String>> {
        let mut stmt =
            conn.prepare("SELECT action FROM privacy_rules WHERE kind = ?1 AND value = ?2 LIMIT 1")?;
        let mut rows = stmt.query((kind, value))?;
        if let Some(row) = rows.next()? {
            Ok(Some(row.get(0)?))
        } else {
            Ok(None)
        }
    };

    let check_domain = |domain: &str| -> rusqlite::Result<Option<String>> {
        let domain_lc = domain.to_lowercase();
        if !domain_lc.contains('.') {
            return check("domain", &domain_lc);
        }

        // Suffix match: a rule for `youtube.com` also matches `m.youtube.com`.
        // (We intentionally stop before top-level domains like `com`.)
        let mut candidate: &str = domain_lc.as_str();
        loop {
            if let Some(action) = check("domain", candidate)? {
                return Ok(Some(action));
            }
            let Some((_left, rest)) = candidate.split_once('.') else {
                break;
            };
            if !rest.contains('.') {
                break;
            }
            candidate = rest;
        }
        Ok(None)
    };

    match e.event.as_str() {
        "tab_active" => {
            if let Some(domain) = e.domain.as_deref().filter(|s| !s.trim().is_empty()) {
                return check_domain(domain);
            }
        }
        "app_active" => {
            if let Some(app) = e.app.as_deref().filter(|s| !s.trim().is_empty()) {
                return check("app", app);
            }
        }
        _ => {}
    }

    if let Some(domain) = e.domain.as_deref().filter(|s| !s.trim().is_empty()) {
        if let Some(action) = check_domain(domain)? {
            return Ok(Some(action));
        }
    }
    if let Some(app) = e.app.as_deref().filter(|s| !s.trim().is_empty()) {
        if let Some(action) = check("app", app)? {
            return Ok(Some(action));
        }
    }
    Ok(None)
}

fn load_tracking_status(conn: &mut Connection) -> rusqlite::Result<TrackingStatus> {
    let mut stmt = conn.prepare(
        "SELECT paused, paused_until_ts, updated_at FROM tracking_state WHERE id = 1",
    )?;
    stmt.query_row([], |row| {
        let paused: i64 = row.get(0)?;
        Ok(TrackingStatus {
            paused: paused != 0,
            paused_until_ts: row.get(1)?,
            updated_at: row.get(2)?,
        })
    })
}

fn set_tracking_pause(
    conn: &mut Connection,
    paused_until_ts: Option<&str>,
    updated_at: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE tracking_state SET paused = 1, paused_until_ts = ?1, updated_at = ?2 WHERE id = 1",
        (paused_until_ts, updated_at),
    )?;
    Ok(())
}

fn set_tracking_resume(conn: &mut Connection, updated_at: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE tracking_state SET paused = 0, paused_until_ts = NULL, updated_at = ?1 WHERE id = 1",
        [updated_at],
    )?;
    Ok(())
}

fn tracking_is_paused(conn: &mut Connection, now: OffsetDateTime) -> rusqlite::Result<bool> {
    let (paused, paused_until_ts): (i64, Option<String>) = {
        let mut stmt =
            conn.prepare("SELECT paused, paused_until_ts FROM tracking_state WHERE id = 1")?;
        stmt.query_row([], |row| Ok((row.get(0)?, row.get(1)?)))?
    };

    if paused == 0 {
        return Ok(false);
    }

    if let Some(until_ts) = paused_until_ts.as_deref() {
        match OffsetDateTime::parse(until_ts, &Rfc3339) {
            Ok(until) => {
                if until <= now {
                    let updated_at = now.format(&Rfc3339).unwrap_or_default();
                    set_tracking_resume(conn, &updated_at)?;
                    return Ok(false);
                }
            }
            Err(_) => {
                // Corrupted row: auto-resume to avoid being stuck.
                let updated_at = now.format(&Rfc3339).unwrap_or_default();
                set_tracking_resume(conn, &updated_at)?;
                return Ok(false);
            }
        }
    }

    Ok(true)
}

fn list_events(
    conn: &mut Connection,
    limit: usize,
    privacy: &PrivacyIndex,
) -> rusqlite::Result<Vec<EventRecord>> {
    let mut stmt = conn.prepare(
        "SELECT id, ts, source, event, entity, title, payload_json FROM events ORDER BY ts DESC LIMIT ?1",
    )?;
    let rows = stmt.query_map([limit as i64], |row| {
        let payload_json: String = row.get(6)?;
        let activity = serde_json::from_str::<Value>(&payload_json)
            .ok()
            .and_then(|v| v.get("activity").and_then(|a| a.as_str()).map(|s| s.to_string()));
        Ok(EventRecord {
            id: row.get(0)?,
            ts: row.get(1)?,
            source: row.get(2)?,
            event: row.get(3)?,
            entity: row.get(4)?,
            title: row.get(5)?,
            activity,
        })
    })?;

    let mut out = Vec::new();
    for r in rows {
        let mut e = r?;
        if let Some(entity) = e.entity.as_deref() {
            match privacy.decision_for(&e.event, entity) {
                PrivacyDecision::Allow => {}
                PrivacyDecision::Drop => continue,
                PrivacyDecision::Mask => {
                    e.entity = Some("__hidden__".to_string());
                    e.title = None;
                }
            }
        }
        out.push(e);
    }
    Ok(out)
}

#[derive(Clone)]
struct EventForBlocks {
    ts: OffsetDateTime,
    #[allow(dead_code)]
    source: String,
    event: String,
    entity: String,
    #[allow(dead_code)]
    title: Option<String>,
    #[allow(dead_code)]
    activity: Option<String>,
}

fn list_events_between(
    conn: &mut Connection,
    start: OffsetDateTime,
    end: OffsetDateTime,
    privacy: &PrivacyIndex,
) -> rusqlite::Result<Vec<EventForBlocks>> {
    let start_s = start.format(&Rfc3339).unwrap_or_default();
    let end_s = end.format(&Rfc3339).unwrap_or_default();

    let mut stmt = conn.prepare(
        "SELECT ts, source, event, entity, title, payload_json FROM events WHERE ts >= ?1 AND ts < ?2 AND entity IS NOT NULL ORDER BY ts ASC",
    )?;
    let rows = stmt.query_map((start_s, end_s), |row| {
        let ts_s: String = row.get(0)?;
        let ts = OffsetDateTime::parse(&ts_s, &Rfc3339)
            .map_err(|_| rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(std::fmt::Error)))?;
        let payload_json: String = row.get(5)?;
        let activity = serde_json::from_str::<Value>(&payload_json)
            .ok()
            .and_then(|v| v.get("activity").and_then(|a| a.as_str()).map(|s| s.to_string()));
        Ok(EventForBlocks {
            ts,
            source: row.get(1)?,
            event: row.get(2)?,
            entity: row.get(3)?,
            title: row.get(4)?,
            activity,
        })
    })?;

    let mut out = Vec::new();
    for r in rows {
        let mut e = r?;
        match privacy.decision_for(&e.event, &e.entity) {
            PrivacyDecision::Allow => {}
            PrivacyDecision::Drop | PrivacyDecision::Mask => {
                // For timeline/blocks/export: keep timing continuity, but hide sensitive entities retroactively.
                e.entity = "__hidden__".to_string();
                e.title = None;
            }
        }
        out.push(e);
    }
    Ok(out)
}

fn normalize_tz_offset_minutes(v: Option<i32>) -> i32 {
    v.unwrap_or(0)
        .clamp(TZ_OFFSET_MINUTES_MIN, TZ_OFFSET_MINUTES_MAX)
}

fn tz_offset_from_minutes(minutes: i32) -> time::UtcOffset {
    time::UtcOffset::from_whole_seconds(minutes.saturating_mul(60))
        .unwrap_or(time::UtcOffset::UTC)
}

fn parse_day_start_utc_for_offset(
    date: &str,
    tz_offset: time::UtcOffset,
) -> Result<OffsetDateTime, ()> {
    // YYYY-MM-DD in the provided offset; converted to UTC start.
    let parts: Vec<&str> = date.split('-').collect();
    if parts.len() != 3 {
        return Err(());
    }
    let y: i32 = parts[0].parse().map_err(|_| ())?;
    let m: u8 = parts[1].parse().map_err(|_| ())?;
    let d: u8 = parts[2].parse().map_err(|_| ())?;
    let month = time::Month::try_from(m).map_err(|_| ())?;
    let dt = time::Date::from_calendar_date(y, month, d).map_err(|_| ())?;
    Ok(dt
        .with_hms(0, 0, 0)
        .map_err(|_| ())?
        .assume_offset(tz_offset)
        .to_offset(time::UtcOffset::UTC))
}

fn is_browser_app(app: &str) -> bool {
    let name = app
        .rsplit(['\\', '/'])
        .next()
        .unwrap_or(app)
        .to_lowercase();
    matches!(
        name.as_str(),
        "chrome.exe" | "msedge.exe" | "brave.exe" | "vivaldi.exe" | "opera.exe" | "firefox.exe"
    )
}

#[derive(Clone, Copy, Hash, PartialEq, Eq)]
enum EntityKind {
    App,
    Domain,
}

impl EntityKind {
    fn as_str(self) -> &'static str {
        match self {
            EntityKind::App => "app",
            EntityKind::Domain => "domain",
        }
    }
}

#[derive(Clone, Hash, PartialEq, Eq)]
struct BucketKey {
    kind: EntityKind,
    entity: String,
    title: Option<String>,
}

fn normalize_web_title(domain: &str, raw: &str) -> String {
    let mut t = raw.trim().to_string();
    if t.is_empty() {
        return String::new();
    }
    let d = domain.to_lowercase();
    if d.contains("youtube.") && t.ends_with(" - YouTube") {
        t.truncate(t.len().saturating_sub(" - YouTube".len()));
    }
    t.trim().to_string()
}

fn normalized_title_for_domain(domain: &str, raw: Option<&str>, store_titles: bool) -> Option<String> {
    if !store_titles {
        return None;
    }
    let r = raw?.trim();
    if r.is_empty() {
        return None;
    }
    let t = normalize_web_title(domain, r);
    if t.is_empty() { None } else { Some(t) }
}

fn build_blocks(events: &[EventForBlocks], settings: Settings, now: OffsetDateTime) -> Vec<BlockSummary> {
    if events.is_empty() {
        return Vec::new();
    }

    // Background audio (audible tab) should not disturb the primary focus timeline:
    // - primary blocks are built from the focus stream (app_active + tab_active when browser is focused)
    // - background audio is computed separately and attached to blocks as secondary usage
    let mut focus_events: Vec<EventForBlocks> = Vec::new();
    let mut audio_events: Vec<EventForBlocks> = Vec::new();
    let mut audio_primary = false;
    for e in events {
        if (e.event == "tab_active" && e.activity.as_deref() == Some("audio"))
            || e.event == "tab_audio_stop"
            || e.event == "app_audio"
            || e.event == "app_audio_stop"
        {
            audio_events.push(e.clone());
        } else {
            focus_events.push(e.clone());
        }
    }

    // Fallback: if we only have background-audio events (e.g. extension-only setup),
    // still build blocks so the UI can show something useful.
    if focus_events.is_empty() {
        if audio_events.is_empty() {
            return Vec::new();
        }
        audio_primary = true;
        focus_events = std::mem::take(&mut audio_events);
    }

    let block_len = time::Duration::seconds(settings.block_seconds.max(60));
    let default_idle_cutoff = time::Duration::seconds(settings.idle_cutoff_seconds.max(10));
    let audio_idle_cutoff =
        default_idle_cutoff.min(time::Duration::seconds(AUDIO_IDLE_CUTOFF_SECONDS));
    let idle_cutoff = if audio_primary {
        audio_idle_cutoff
    } else {
        default_idle_cutoff
    };
    let domain_freshness = time::Duration::seconds(DOMAIN_FRESHNESS_SECONDS);

    let mut blocks: Vec<BlockSummary> = Vec::new();

    let mut current_start = focus_events[0].ts;
    let mut current_end = current_start;
    let mut active_seconds: i64 = 0;
    let mut bucket: HashMap<BucketKey, i64> = HashMap::new();

    let mut current_app: Option<String> = None;
    let mut current_domain: Option<String> = None;
    let mut current_domain_title: Option<String> = None;
    let mut current_domain_ts: Option<OffsetDateTime> = None;

    for i in 0..focus_events.len() {
        let cur = &focus_events[i];
        let next_ts = focus_events.get(i + 1).map(|e| e.ts).unwrap_or(now);
        if next_ts <= cur.ts {
            continue;
        }

        match cur.event.as_str() {
            "app_active" => {
                current_app = Some(cur.entity.clone());
            }
            "tab_active" => {
                current_domain = Some(cur.entity.clone());
                current_domain_title = cur.title.clone();
                current_domain_ts = Some(cur.ts);
            }
            "tab_audio_stop" => {
                // Stop marker: clear domain so subsequent time isn't attributed to any tab.
                current_domain = None;
                current_domain_title = None;
                current_domain_ts = None;
            }
            "app_audio_stop" => {
                // Stop marker: clear app so subsequent time isn't attributed to any app audio.
                current_app = None;
            }
            _ => {
                // Fallback: treat as app-like entity for attribution.
                current_app = Some(cur.entity.clone());
            }
        }

        let raw_gap = next_ts - cur.ts;
        let mut seg = raw_gap.min(idle_cutoff);
        if seg.is_negative() || seg.is_zero() {
            continue;
        }

        let mut seg_start = cur.ts;

        let resolve_entity = |at: OffsetDateTime| -> Option<(EntityKind, &str, Option<&str>)> {
            if let Some(app) = current_app.as_deref() {
                if is_browser_app(app) {
                    if let (Some(domain), Some(domain_ts)) =
                        (current_domain.as_deref(), current_domain_ts)
                    {
                        if at - domain_ts <= domain_freshness {
                            Some((EntityKind::Domain, domain, current_domain_title.as_deref()))
                        } else {
                            Some((EntityKind::App, app, None))
                        }
                    } else {
                        Some((EntityKind::App, app, None))
                    }
                } else {
                    Some((EntityKind::App, app, None))
                }
            } else {
                current_domain
                    .as_deref()
                    .map(|d| (EntityKind::Domain, d, current_domain_title.as_deref()))
            }
        };

        while seg > time::Duration::ZERO {
            let resolved_entity = resolve_entity(seg_start);
            let remaining = block_len - time::Duration::seconds(active_seconds);
            let take = seg.min(remaining);

            let take_s = take.whole_seconds();
            if take_s > 0 {
                if let Some((kind, entity, title)) = resolved_entity {
                    let key = BucketKey {
                        kind,
                        entity: entity.to_string(),
                        title: if kind == EntityKind::Domain {
                            normalized_title_for_domain(entity, title, settings.store_titles)
                        } else {
                            None
                        },
                    };
                    *bucket.entry(key).or_insert(0) += take_s;
                    active_seconds += take_s;
                    seg_start += take;
                    current_end = seg_start;
                }
            } else {
                break;
            }

            seg -= take;

            if time::Duration::seconds(active_seconds) >= block_len {
                blocks.push(finalize_block(current_start, current_end, &bucket, active_seconds));
                // next block starts exactly at the boundary
                current_start = current_end;
                bucket.clear();
                active_seconds = 0;
            }
        }

        // If there was a long gap, close the current block (do not attribute idle to any entity).
        if raw_gap > idle_cutoff {
            if active_seconds > 0 {
                blocks.push(finalize_block(current_start, current_end, &bucket, active_seconds));
            }
            // Start a new block at next_ts (there may be idle gap).
            current_start = next_ts;
            current_end = next_ts;
            bucket.clear();
            active_seconds = 0;
            current_app = None;
            current_domain = None;
            current_domain_title = None;
            current_domain_ts = None;
        }
    }

    if active_seconds > 0 {
        blocks.push(finalize_block(current_start, current_end, &bucket, active_seconds));
    }

    if !audio_events.is_empty() && !blocks.is_empty() {
        // Audio events are heartbeated by the extension (default 60s). Use a tighter cutoff than the
        // primary focus idle cutoff to avoid over-attributing when audio stops but no "stop" event is sent.
        attach_background_audio(&mut blocks, &audio_events, settings.store_titles, audio_idle_cutoff, now);
    }

    blocks
}

#[derive(Clone)]
struct SegmentAcc {
    kind: EntityKind,
    entity: String,
    title: Option<String>,
    activity: &'static str, // "focus" | "audio"
    start: OffsetDateTime,
    end: OffsetDateTime,
}

fn push_or_merge_segment(out: &mut Vec<SegmentAcc>, seg: SegmentAcc) {
    if seg.end <= seg.start {
        return;
    }
    if let Some(last) = out.last_mut() {
        if last.kind == seg.kind
            && last.entity == seg.entity
            && last.title == seg.title
            && last.activity == seg.activity
            && last.end == seg.start
        {
            last.end = seg.end;
            return;
        }
    }
    out.push(seg);
}

fn build_timeline_segments(
    events: &[EventForBlocks],
    settings: Settings,
    now: OffsetDateTime,
) -> Vec<TimelineSegment> {
    if events.is_empty() {
        return Vec::new();
    }

    let default_idle_cutoff = time::Duration::seconds(settings.idle_cutoff_seconds.max(10));
    let focus_idle_cutoff = default_idle_cutoff;
    let audio_idle_cutoff =
        default_idle_cutoff.min(time::Duration::seconds(AUDIO_IDLE_CUTOFF_SECONDS));
    let domain_freshness = time::Duration::seconds(DOMAIN_FRESHNESS_SECONDS);

    // Split streams.
    let mut focus_events: Vec<EventForBlocks> = Vec::new();
    let mut audio_events: Vec<EventForBlocks> = Vec::new();
    for e in events {
        if (e.event == "tab_active" && e.activity.as_deref() == Some("audio"))
            || e.event == "tab_audio_stop"
            || e.event == "app_audio"
            || e.event == "app_audio_stop"
        {
            audio_events.push(e.clone());
        } else {
            focus_events.push(e.clone());
        }
    }

    // Focus stream segments (foreground usage).
    let mut focus_out: Vec<SegmentAcc> = Vec::new();
    if !focus_events.is_empty() {
        let mut current_app: Option<String> = None;
        let mut current_app_title: Option<String> = None;
        let mut current_domain: Option<String> = None;
        let mut current_domain_title: Option<String> = None;
        let mut current_domain_ts: Option<OffsetDateTime> = None;

        for i in 0..focus_events.len() {
            let cur = &focus_events[i];
            let next_ts = focus_events.get(i + 1).map(|e| e.ts).unwrap_or(now);
            if next_ts <= cur.ts {
                continue;
            }

            match cur.event.as_str() {
                "app_active" => {
                    current_app = Some(cur.entity.clone());
                    current_app_title = cur.title.clone();
                }
                "tab_active" => {
                    current_domain = Some(cur.entity.clone());
                    current_domain_title = cur.title.clone();
                    current_domain_ts = Some(cur.ts);
                }
                _ => {
                    // Fallback: treat as app-like.
                    current_app = Some(cur.entity.clone());
                    current_app_title = cur.title.clone();
                }
            }

            let raw_gap = next_ts - cur.ts;
            let seg = raw_gap.min(focus_idle_cutoff);
            if seg.is_negative() || seg.is_zero() {
                continue;
            }
            let seg_end = cur.ts + seg;

            let resolved = if let Some(app) = current_app.as_deref() {
                if is_browser_app(app) {
                    if let (Some(domain), Some(domain_ts)) =
                        (current_domain.as_deref(), current_domain_ts)
                    {
                        if cur.ts - domain_ts <= domain_freshness {
                            Some((
                                EntityKind::Domain,
                                domain.to_string(),
                                current_domain_title.clone(),
                            ))
                        } else {
                            Some((EntityKind::App, app.to_string(), current_app_title.clone()))
                        }
                    } else {
                        Some((EntityKind::App, app.to_string(), current_app_title.clone()))
                    }
                } else {
                    Some((EntityKind::App, app.to_string(), current_app_title.clone()))
                }
            } else {
                current_domain.as_deref().map(|d| {
                    (
                        EntityKind::Domain,
                        d.to_string(),
                        current_domain_title.clone(),
                    )
                })
            };

            if let Some((kind, entity, title)) = resolved {
                push_or_merge_segment(
                    &mut focus_out,
                    SegmentAcc {
                        kind,
                        entity,
                        title,
                        activity: "focus",
                        start: cur.ts,
                        end: seg_end,
                    },
                );
            }

            if raw_gap > focus_idle_cutoff {
                current_app = None;
                current_app_title = None;
                current_domain = None;
                current_domain_title = None;
                current_domain_ts = None;
            }
        }
    }

	    // Background audio stream segments (audible tab while browser not focused).
	    let mut audio_out: Vec<SegmentAcc> = Vec::new();
	    if !audio_events.is_empty() {
	        for i in 0..audio_events.len() {
	            let cur = &audio_events[i];
	            let kind = match cur.event.as_str() {
	                "tab_active" => EntityKind::Domain,
	                "app_audio" => EntityKind::App,
	                _ => continue,
	            };
	            let next_ts = audio_events.get(i + 1).map(|e| e.ts).unwrap_or(now);
	            if next_ts <= cur.ts {
	                continue;
	            }
            let raw_gap = next_ts - cur.ts;
            let seg = raw_gap.min(audio_idle_cutoff);
            if seg.is_negative() || seg.is_zero() {
                continue;
            }
	            let seg_end = cur.ts + seg;
	            push_or_merge_segment(
	                &mut audio_out,
	                SegmentAcc {
	                    kind,
	                    entity: cur.entity.clone(),
	                    title: cur.title.clone(),
	                    activity: "audio",
	                    start: cur.ts,
	                    end: seg_end,
	                },
	            );
	        }
	    }

    let mut all = Vec::new();
    all.extend(focus_out);
    all.extend(audio_out);
    all.sort_by(|a, b| a.start.cmp(&b.start));

    all.into_iter()
        .filter_map(|s| {
            let seconds = (s.end - s.start).whole_seconds();
            if seconds <= 0 {
                return None;
            }
            Some(TimelineSegment {
                kind: s.kind.as_str().to_string(),
                entity: s.entity,
                title: s.title,
                activity: Some(s.activity.to_string()),
                start_ts: s.start.format(&Rfc3339).unwrap_or_default(),
                end_ts: s.end.format(&Rfc3339).unwrap_or_default(),
                seconds,
            })
        })
        .collect()
}

fn attach_background_audio(
    blocks: &mut [BlockSummary],
    audio_events: &[EventForBlocks],
    store_titles: bool,
    idle_cutoff: time::Duration,
    now: OffsetDateTime,
) {
    let mut block_times: Vec<(OffsetDateTime, OffsetDateTime)> = Vec::with_capacity(blocks.len());
    for b in blocks.iter() {
        let Ok(start) = OffsetDateTime::parse(&b.start_ts, &Rfc3339) else {
            return;
        };
        let Ok(end) = OffsetDateTime::parse(&b.end_ts, &Rfc3339) else {
            return;
        };
        block_times.push((start, end));
    }

    let mut per_block: Vec<HashMap<BucketKey, i64>> = vec![HashMap::new(); blocks.len()];
    let mut per_total: Vec<i64> = vec![0; blocks.len()];

    let mut bi: usize = 0;
    for i in 0..audio_events.len() {
        let cur = &audio_events[i];
        let next_ts = audio_events.get(i + 1).map(|e| e.ts).unwrap_or(now);
        if next_ts <= cur.ts {
            continue;
        }

        // Stop marker: it exists only to end the previous segment early.
        // Do not attribute any usage after it.
        if cur.event == "tab_audio_stop" || cur.event == "app_audio_stop" {
            continue;
        }

        let raw_gap = next_ts - cur.ts;
        let seg = raw_gap.min(idle_cutoff);
        if seg.is_negative() || seg.is_zero() {
            continue;
        }

        let seg_start = cur.ts;
        let seg_end = cur.ts + seg;
        let key = BucketKey {
            kind: if cur.event == "app_audio" {
                EntityKind::App
            } else {
                EntityKind::Domain
            },
            entity: cur.entity.clone(),
            title: if cur.event == "tab_active" {
                normalized_title_for_domain(&cur.entity, cur.title.as_deref(), store_titles)
            } else {
                None
            },
        };

        while bi < block_times.len() && block_times[bi].1 <= seg_start {
            bi += 1;
        }

        let mut j = bi;
        while j < block_times.len() && block_times[j].0 < seg_end {
            let overlap_start = if seg_start > block_times[j].0 {
                seg_start
            } else {
                block_times[j].0
            };
            let overlap_end = if seg_end < block_times[j].1 {
                seg_end
            } else {
                block_times[j].1
            };
            let sec = (overlap_end - overlap_start).whole_seconds();
            if sec > 0 {
                *per_block[j].entry(key.clone()).or_insert(0) += sec;
                per_total[j] += sec;
            }
            j += 1;
        }
    }

    for i in 0..blocks.len() {
        if per_total[i] <= 0 {
            continue;
        }
        let mut items: Vec<TopItem> = per_block[i]
            .iter()
            .map(|(k, sec)| {
                let name = if k.kind == EntityKind::Domain {
                    k.title.clone().unwrap_or_else(|| k.entity.clone())
                } else {
                    k.entity.clone()
                };
                TopItem {
                    kind: k.kind.as_str().to_string(),
                    name,
                    seconds: *sec,
                }
            })
            .collect();
        items.sort_by(|a, b| b.seconds.cmp(&a.seconds));
        items.truncate(5);
        blocks[i].background_seconds = Some(per_total[i]);
        blocks[i].background_top_items = items;
    }
}

fn finalize_block(
    start: OffsetDateTime,
    end: OffsetDateTime,
    bucket: &HashMap<BucketKey, i64>,
    total_seconds: i64,
) -> BlockSummary {
    let start_ts = start.format(&Rfc3339).unwrap_or_default();
    let end_ts = end.format(&Rfc3339).unwrap_or_default();
    let id = start_ts.clone();

    let mut items: Vec<TopItem> = bucket
        .iter()
        .map(|(k, v)| {
            let name = if k.kind == EntityKind::Domain {
                k.title.clone().unwrap_or_else(|| k.entity.clone())
            } else {
                k.entity.clone()
            };
            TopItem {
                kind: k.kind.as_str().to_string(),
                name,
                seconds: *v,
            }
        })
        .collect();
    items.sort_by(|a, b| b.seconds.cmp(&a.seconds));
    items.truncate(5);

    BlockSummary {
        id,
        start_ts,
        end_ts,
        total_seconds,
        top_items: items,
        background_top_items: Vec::new(),
        background_seconds: None,
        review: None,
    }
}

fn upsert_review(
    conn: &mut Connection,
    r: &ReviewUpsert,
    skip_reason: Option<&str>,
    tags_json: &str,
    updated_at: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        r#"
INSERT INTO block_reviews (block_id, skipped, skip_reason, doing, output, next, tags_json, updated_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
ON CONFLICT(block_id) DO UPDATE SET
  skipped=excluded.skipped,
  skip_reason=excluded.skip_reason,
  doing=excluded.doing,
  output=excluded.output,
  next=excluded.next,
  tags_json=excluded.tags_json,
  updated_at=excluded.updated_at
"#,
        (
            &r.block_id,
            if r.skipped { 1_i64 } else { 0_i64 },
            skip_reason,
            r.doing.as_deref(),
            r.output.as_deref(),
            r.next.as_deref(),
            tags_json,
            updated_at,
        ),
    )?;
    Ok(())
}

fn attach_reviews(conn: &mut Connection, mut blocks: Vec<BlockSummary>) -> rusqlite::Result<Vec<BlockSummary>> {
    for b in &mut blocks {
        if let Some(r) = get_review(conn, &b.id)? {
            b.review = Some(r);
        }
    }
    Ok(blocks)
}

fn get_review(conn: &mut Connection, block_id: &str) -> rusqlite::Result<Option<BlockReview>> {
    let mut stmt = conn.prepare(
        "SELECT skipped, skip_reason, doing, output, next, tags_json, updated_at FROM block_reviews WHERE block_id = ?1",
    )?;
    let mut rows = stmt.query([block_id])?;
    if let Some(row) = rows.next()? {
        let tags_json: Option<String> = row.get(5)?;
        let tags: Vec<String> = tags_json
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        let skipped: i64 = row.get(0)?;
        return Ok(Some(BlockReview {
            skipped: skipped != 0,
            skip_reason: row.get(1)?,
            doing: row.get(2)?,
            output: row.get(3)?,
            next: row.get(4)?,
            tags,
            updated_at: row.get(6)?,
        }));
    }
    Ok(None)
}

fn export_markdown(date: &str, blocks: &[BlockSummary], tz_offset: time::UtcOffset) -> String {
    let mut out = String::new();
    out.push_str(&format!("# {date}\n\n"));

    for b in blocks {
        let start = fmt_hhmm(&b.start_ts, tz_offset);
        let end = fmt_hhmm(&b.end_ts, tz_offset);
        out.push_str(&format!("## {start}–{end}\n"));

        if !b.top_items.is_empty() {
            out.push_str("Top: ");
            out.push_str(
                &b.top_items
                    .iter()
                    .map(|it| format!("{} {}", it.name, fmt_duration(it.seconds)))
                    .collect::<Vec<_>>()
                    .join(" · "),
            );
            out.push('\n');
        }

        if let Some(r) = &b.review {
            if r.skipped {
                if let Some(reason) = &r.skip_reason {
                    if !reason.trim().is_empty() {
                        out.push_str(&format!("- Skipped: {reason}\n"));
                    } else {
                        out.push_str("- Skipped\n");
                    }
                } else {
                    out.push_str("- Skipped\n");
                }
            }
            if let Some(v) = &r.doing {
                if !v.trim().is_empty() {
                    out.push_str(&format!("- Doing: {v}\n"));
                }
            }
            if let Some(v) = &r.output {
                if !v.trim().is_empty() {
                    out.push_str(&format!("- Output: {v}\n"));
                }
            }
            if let Some(v) = &r.next {
                if !v.trim().is_empty() {
                    out.push_str(&format!("- Next: {v}\n"));
                }
            }
            if !r.tags.is_empty() {
                out.push_str(&format!("- Tags: {}\n", r.tags.join(", ")));
            }
        }

        out.push('\n');
    }

    out
}

fn export_csv(date: &str, blocks: &[BlockSummary]) -> String {
    let mut out = String::new();
    out.push_str("date,block_id,start_ts,end_ts,total_seconds,top1_name,top1_seconds,top2_name,top2_seconds,top3_name,top3_seconds,top4_name,top4_seconds,top5_name,top5_seconds,skipped,skip_reason,doing,output,next,tags,review_updated_at\n");

    for b in blocks {
        let (skipped, skip_reason, doing, output, next, tags, updated_at) = match &b.review {
            Some(r) => (
                if r.skipped { "1" } else { "0" },
                r.skip_reason.as_deref().unwrap_or(""),
                r.doing.as_deref().unwrap_or(""),
                r.output.as_deref().unwrap_or(""),
                r.next.as_deref().unwrap_or(""),
                r.tags.join(";"),
                r.updated_at.as_str(),
            ),
            None => ("", "", "", "", "", String::new(), ""),
        };

        let mut row: Vec<String> = Vec::with_capacity(24);
        row.push(csv_escape(date));
        row.push(csv_escape(&b.id));
        row.push(csv_escape(&b.start_ts));
        row.push(csv_escape(&b.end_ts));
        row.push(b.total_seconds.to_string());

        for i in 0..5 {
            if let Some(it) = b.top_items.get(i) {
                row.push(csv_escape(&it.name));
                row.push(it.seconds.to_string());
            } else {
                row.push(String::new());
                row.push(String::new());
            }
        }

        row.push(skipped.to_string());
        row.push(csv_escape(skip_reason));
        row.push(csv_escape(doing));
        row.push(csv_escape(output));
        row.push(csv_escape(next));
        row.push(csv_escape(&tags));
        row.push(csv_escape(updated_at));

        out.push_str(&row.join(","));
        out.push('\n');
    }

    out
}

fn csv_escape(s: &str) -> String {
    let needs_quote = s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    if !needs_quote {
        return s.to_string();
    }
    format!("\"{}\"", s.replace('"', "\"\""))
}

fn fmt_duration(seconds: i64) -> String {
    if seconds <= 0 {
        return "0m".to_string();
    }
    let m = (seconds + 30) / 60;
    if m < 60 {
        return format!("{m}m");
    }
    let h = m / 60;
    let rm = m % 60;
    if rm == 0 {
        format!("{h}h")
    } else {
        format!("{h}h {rm}m")
    }
}

fn fmt_hhmm(rfc3339: &str, tz_offset: time::UtcOffset) -> String {
    if let Ok(t) = OffsetDateTime::parse(rfc3339, &Rfc3339) {
        let local = t.to_offset(tz_offset);
        return format!("{:02}:{:02}", local.hour(), local.minute());
    }
    // fallback
    rfc3339
        .split('T')
        .nth(1)
        .and_then(|s| s.get(0..5))
        .unwrap_or("??:??")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_day_start_utc_for_offset_works() {
        let tz = tz_offset_from_minutes(8 * 60);
        let start = parse_day_start_utc_for_offset("2026-02-15", tz).unwrap();
        assert_eq!(start.offset(), time::UtcOffset::UTC);
        assert_eq!(start.date().to_string(), "2026-02-14");
        assert_eq!(start.hour(), 16);
        assert_eq!(start.minute(), 0);

        let tz = tz_offset_from_minutes(-5 * 60);
        let start = parse_day_start_utc_for_offset("2026-02-15", tz).unwrap();
        assert_eq!(start.date().to_string(), "2026-02-15");
        assert_eq!(start.hour(), 5);
        assert_eq!(start.minute(), 0);
    }

    #[test]
    fn build_blocks_prefers_domain_when_browser_active() {
        let base = OffsetDateTime::parse("2026-02-15T00:00:00Z", &Rfc3339).unwrap();
        let m = |mins: i64| base + time::Duration::minutes(mins);

        let events = vec![
            EventForBlocks {
                ts: m(0),
                source: "windows_collector".to_string(),
                event: "app_active".to_string(),
                entity: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe".to_string(),
                title: None,
                activity: None,
            },
            EventForBlocks {
                ts: m(1),
                source: "browser_extension".to_string(),
                event: "tab_active".to_string(),
                entity: "github.com".to_string(),
                title: None,
                activity: None,
            },
            EventForBlocks {
                ts: m(2),
                source: "windows_collector".to_string(),
                event: "app_active".to_string(),
                entity: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe".to_string(),
                title: None,
                activity: None,
            },
            EventForBlocks {
                ts: m(3),
                source: "browser_extension".to_string(),
                event: "tab_active".to_string(),
                entity: "github.com".to_string(),
                title: None,
                activity: None,
            },
            EventForBlocks {
                ts: m(4),
                source: "windows_collector".to_string(),
                event: "app_active".to_string(),
                entity: "C:\\Program Files\\Microsoft VS Code\\Code.exe".to_string(),
                title: None,
                activity: None,
            },
        ];

	        let settings = Settings {
	            block_seconds: 45 * 60,
	            idle_cutoff_seconds: 10 * 60,
	            store_titles: false,
	            store_exe_path: false,
	        };
        let blocks = build_blocks(&events, settings, m(5));
        assert_eq!(blocks.len(), 1);
        let b = &blocks[0];
        assert_eq!(b.total_seconds, 5 * 60);

        let sec = |name: &str| {
            b.top_items
                .iter()
                .find(|it| it.name == name)
                .map(|it| it.seconds)
                .unwrap_or(0)
        };
        assert_eq!(sec("github.com"), 3 * 60);
        assert_eq!(sec("C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"), 60);
        assert_eq!(sec("C:\\Program Files\\Microsoft VS Code\\Code.exe"), 60);
    }

    #[test]
    fn build_blocks_splits_domain_by_title_when_store_titles() {
        let base = OffsetDateTime::parse("2026-02-15T00:00:00Z", &Rfc3339).unwrap();
        let m = |mins: i64| base + time::Duration::minutes(mins);

        let events = vec![
            EventForBlocks {
                ts: m(0),
                source: "windows_collector".to_string(),
                event: "app_active".to_string(),
                entity: "chrome.exe".to_string(),
                title: None,
                activity: None,
            },
            EventForBlocks {
                ts: m(1),
                source: "browser_extension".to_string(),
                event: "tab_active".to_string(),
                entity: "www.youtube.com".to_string(),
                title: Some("Video A - YouTube".to_string()),
                activity: None,
            },
            EventForBlocks {
                ts: m(2),
                source: "browser_extension".to_string(),
                event: "tab_active".to_string(),
                entity: "www.youtube.com".to_string(),
                title: Some("Video B - YouTube".to_string()),
                activity: None,
            },
        ];

        let settings = Settings {
            block_seconds: 45 * 60,
            idle_cutoff_seconds: 10 * 60,
            store_titles: true,
            store_exe_path: false,
        };
        let blocks = build_blocks(&events, settings, m(3));
        assert_eq!(blocks.len(), 1);
        let b = &blocks[0];

        let sec_domain = |name: &str| {
            b.top_items
                .iter()
                .find(|it| it.kind == "domain" && it.name == name)
                .map(|it| it.seconds)
                .unwrap_or(0)
        };

        assert_eq!(sec_domain("Video A"), 60);
        assert_eq!(sec_domain("Video B"), 60);
        assert!(
            b.top_items.iter().all(|it| it.name != "www.youtube.com"),
            "domain should be replaced by normalized title when available"
        );
    }
}
