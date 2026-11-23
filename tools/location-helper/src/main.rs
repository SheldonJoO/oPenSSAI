// openSSS location helper (Mac side).
//
// HTTP front-end for the DVT location simulation session (see session.rs).
// The openSSS app posts coordinates here; the helper forwards them to the
// iPhone over USB (usbmuxd) or TCP (Wi-Fi + pairing file).
//
// Endpoints:
//   POST   /location  {"latitude": 37.5, "longitude": 121.3}  — start/update
//   DELETE /location                                        — stop, restore real location
//   GET    /status    {"active","latitude","longitude","connected"}
//   GET    /health    {"ok": true}

mod session;

use std::{net::SocketAddr, time::Duration};

use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use clap::Parser;
use serde::{Deserialize, Serialize};
use session::{Command, ProviderArgs, SessionStatus, run_actor};
use tokio::sync::{mpsc, oneshot};

#[derive(Parser, Debug)]
#[command(version, about = "openSSS virtual-location helper for Mac")]
struct Args {
    /// HTTP listen port (the app connects to http://<mac-lan-ip>:<port>).
    #[arg(long, default_value_t = 17878)]
    port: u16,

    /// Target a specific device by UDID over USB. Without it, the first
    /// USB device from usbmuxd is used.
    #[arg(long)]
    udid: Option<String>,

    /// Device IP for a TCP (Wi-Fi) connection. Requires --pairing-file.
    #[arg(long)]
    host: Option<String>,

    /// Lockdown pairing file for a TCP (Wi-Fi) connection.
    #[arg(long)]
    pairing_file: Option<String>,

    /// Re-send the active location every N seconds (the idevice reference
    /// tool uses 5s; the simulated location lives on the DVT session).
    #[arg(long, default_value_t = 5)]
    refresh_secs: u64,
}

#[derive(Clone)]
struct AppState {
    cmd_tx: mpsc::Sender<Command>,
}

#[derive(Deserialize)]
struct SetLocationRequest {
    latitude: f64,
    longitude: f64,
}

#[derive(Serialize)]
struct StatusResponse {
    active: bool,
    latitude: Option<f64>,
    longitude: Option<f64>,
    connected: bool,
}

impl From<SessionStatus> for StatusResponse {
    fn from(status: SessionStatus) -> Self {
        StatusResponse {
            active: status.active.is_some(),
            latitude: status.active.map(|(lat, _)| lat),
            longitude: status.active.map(|(_, lon)| lon),
            connected: status.connected,
        }
    }
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

fn json_error(status: StatusCode, message: String) -> axum::response::Response {
    (status, Json(ErrorResponse { error: message })).into_response()
}

/// Send a command to the actor and await its reply (30s cap).
async fn ask<T>(
    cmd_tx: &mpsc::Sender<Command>,
    make: impl FnOnce(oneshot::Sender<T>) -> Command,
) -> Result<T, String> {
    let (tx, rx) = oneshot::channel();
    let cmd = make(tx);
    tokio::time::timeout(Duration::from_secs(5), cmd_tx.send(cmd))
        .await
        .map_err(|_| "helper is busy".to_string())?
        .map_err(|_| "helper session ended".to_string())?;
    tokio::time::timeout(Duration::from_secs(30), rx)
        .await
        .map_err(|_| "device did not respond in time".to_string())?
        .map_err(|_| "helper session ended".to_string())
}

async fn set_location(
    State(state): State<AppState>,
    Json(body): Json<SetLocationRequest>,
) -> axum::response::Response {
    if !(-90.0..=90.0).contains(&body.latitude) || !(-180.0..=180.0).contains(&body.longitude) {
        return json_error(
            StatusCode::BAD_REQUEST,
            "latitude must be -90..90 and longitude -180..180".to_string(),
        );
    }
    let lat = body.latitude;
    let lon = body.longitude;
    match ask(&state.cmd_tx, |reply| Command::Set {
        lat,
        lon,
        reply,
    })
    .await
    {
        Ok(Ok(())) => (StatusCode::OK, Json(StatusResponse::from(SessionStatus {
            connected: true,
            active: Some((lat, lon)),
        })))
        .into_response(),
        Ok(Err(e)) => json_error(StatusCode::BAD_GATEWAY, e),
        Err(e) => json_error(StatusCode::GATEWAY_TIMEOUT, e),
    }
}

async fn clear_location(State(state): State<AppState>) -> axum::response::Response {
    match ask(&state.cmd_tx, |reply| Command::Clear { reply }).await {
        Ok(Ok(())) => (StatusCode::OK, Json(StatusResponse::from(SessionStatus {
            connected: true,
            active: None,
        })))
        .into_response(),
        Ok(Err(e)) => json_error(StatusCode::BAD_GATEWAY, e),
        Err(e) => json_error(StatusCode::GATEWAY_TIMEOUT, e),
    }
}

async fn get_status(State(state): State<AppState>) -> axum::response::Response {
    match ask(&state.cmd_tx, |reply| Command::Status { reply }).await {
        Ok(status) => (StatusCode::OK, Json(StatusResponse::from(status))).into_response(),
        Err(e) => json_error(StatusCode::GATEWAY_TIMEOUT, e),
    }
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "ok": true }))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "openssai_location_helper=info,idevice=warn".into()),
        )
        .init();

    let args = Args::parse();
    if args.host.is_some() != args.pairing_file.is_some() {
        eprintln!("--host and --pairing-file must be given together");
        std::process::exit(2);
    }

    let provider_args = ProviderArgs {
        udid: args.udid.clone(),
        host: args.host.clone(),
        pairing_file: args.pairing_file.clone(),
        label: "openssai-location-helper".to_string(),
    };

    let (cmd_tx, cmd_rx) = mpsc::channel(64);

    let app = Router::new()
        .route("/location", post(set_location).delete(clear_location))
        .route("/status", get(get_status))
        .route("/health", get(health))
        .with_state(AppState { cmd_tx });

    let addr = SocketAddr::from(([0, 0, 0, 0], args.port));
    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("cannot listen on {addr}: {e}");
            std::process::exit(1);
        }
    };

    // Run the actor and the HTTP server side by side with select!, not
    // tokio::spawn: the actor future is not 'static (idevice's RsdService
    // is only implemented for RemoteServerClient<Box<dyn ReadWrite +
    // 'static>>, and spawn's 'static bound makes the compiler demand the
    // impl for any lifetime). select! imposes no such bound.
    let actor = run_actor(
        provider_args,
        cmd_rx,
        Duration::from_secs(args.refresh_secs),
    );
    let server = axum::serve(listener, app);
    tracing::info!("location helper listening on {addr}");
    tracing::info!("in the app: Me -> Virtual Location -> Helper Address -> http://<this-mac-lan-ip>:{}", args.port);
    tokio::select! {
        _ = actor => {
            tracing::error!("session actor ended unexpectedly");
        }
        result = server => {
            if let Err(e) = result {
                eprintln!("server error: {e}");
                std::process::exit(1);
            }
        }
    }
}
