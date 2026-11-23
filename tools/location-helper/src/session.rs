// openSSS location helper — device session actor.
//
// Owns the whole DVT connection chain (provider -> CoreDeviceProxy ->
// software tunnel -> RSD handshake -> RemoteServerClient ->
// LocationSimulationClient) inside one async task, so the lifetime-heavy
// client chain never has to cross an HTTP request boundary. HTTP handlers
// send commands over an mpsc channel and await oneshot replies.
//
// The simulated location lives on the DVT session: while a location is
// active the actor re-sends it every `refresh` interval (the idevice
// reference tool re-sends every 5s), and re-applies it after a reconnect.
// If the connection drops, the actor reconnects in the background and
// pending commands fail fast with a clear error.

use std::{
    net::IpAddr,
    str::FromStr,
    time::Duration,
};

use idevice::{
    IdeviceService, ReadWrite, RsdService,
    core_device_proxy::CoreDeviceProxy,
    dvt::{location_simulation::LocationSimulationClient, remote_server::RemoteServerClient},
    pairing_file::PairingFile,
    provider::{IdeviceProvider, TcpProvider},
    rsd::RsdHandshake,
    tcp::handle::AdapterHandle,
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection, UsbmuxdDevice},
};
use tokio::sync::{mpsc, oneshot};

/// Snapshot reported to HTTP clients.
#[derive(Debug, Clone, Copy)]
pub struct SessionStatus {
    /// Whether the helper currently holds a live DVT session.
    pub connected: bool,
    /// The location being simulated, if any.
    pub active: Option<(f64, f64)>,
}

pub enum Command {
    Set {
        lat: f64,
        lon: f64,
        reply: oneshot::Sender<Result<(), String>>,
    },
    Clear {
        reply: oneshot::Sender<Result<(), String>>,
    },
    Status {
        reply: oneshot::Sender<SessionStatus>,
    },
}

impl Command {
    fn fail(self, msg: String) {
        match self {
            Command::Set { reply, .. } | Command::Clear { reply } => {
                let _ = reply.send(Err(msg));
            }
            Command::Status { reply } => {
                let _ = reply.send(SessionStatus {
                    connected: false,
                    active: None,
                });
            }
        }
    }
}

/// How to find the device. Resolution happens inside the actor's
/// reconnect loop, so the helper starts (and serves HTTP) even when no
/// device is attached yet; the app sees `connected: false` until one
/// appears.
#[derive(Debug, Clone)]
pub struct ProviderArgs {
    pub udid: Option<String>,
    pub host: Option<String>,
    pub pairing_file: Option<String>,
    pub label: String,
}
/// a UDID selects a USB device via usbmuxd; host + pairing file select a
/// TCP (Wi-Fi) device; otherwise the first USB device wins.
pub async fn get_provider(
    udid: Option<&str>,
    host: Option<&str>,
    pairing_file: Option<&str>,
    label: &str,
) -> Result<Box<dyn IdeviceProvider>, String> {
    if let Some(udid) = udid {
        let mut usbmuxd = connect_usbmuxd().await?;
        let dev = usbmuxd
            .get_device(udid)
            .await
            .map_err(|e| format!("device not found: {e:?}"))?;
        return Ok(Box::new(
            dev.to_provider(UsbmuxdAddr::from_env_var().unwrap(), label),
        ));
    }

    if let (Some(host), Some(pairing_file)) = (host, pairing_file) {
        let addr = IpAddr::from_str(host).map_err(|e| format!("invalid host: {e:?}"))?;
        let pairing_file = PairingFile::read_from_file(pairing_file)
            .map_err(|e| format!("unable to read pairing file: {e:?}"))?;
        return Ok(Box::new(TcpProvider {
            addr,
            scope_id: None,
            pairing_file,
            label: label.to_string(),
        }));
    }

    let mut usbmuxd = connect_usbmuxd().await?;
    let devs = usbmuxd
        .get_devices()
        .await
        .map_err(|e| format!("unable to list usbmuxd devices: {e:?}"))?;
    if devs.is_empty() {
        return Err("no devices connected".to_string());
    }
    let usb_devs: Vec<&UsbmuxdDevice> = devs
        .iter()
        .filter(|x| x.connection_type == Connection::Usb)
        .collect();
    let chosen = usb_devs.first().copied().unwrap_or(&devs[0]);
    Ok(Box::new(
        chosen.to_provider(UsbmuxdAddr::from_env_var().unwrap(), label),
    ))
}

async fn connect_usbmuxd() -> Result<UsbmuxdConnection, String> {
    if let Ok(var) = std::env::var("USBMUXD_SOCKET_ADDRESS") {
        let socket = std::net::SocketAddr::from_str(&var)
            .map_err(|_| "bad USBMUXD_SOCKET_ADDRESS".to_string())?;
        let stream = tokio::net::TcpStream::connect(socket)
            .await
            .map_err(|e| format!("unable to connect to usbmuxd socket: {e}"))?;
        Ok(UsbmuxdConnection::new(Box::new(stream), 1))
    } else {
        UsbmuxdConnection::default()
            .await
            .map_err(|e| format!("unable to connect to usbmuxd: {e:?}"))
    }
}

/// Build the tunnel + RSD handshake. Returns owned halves; the DVT clients
/// are built from them inside the actor so the borrow chain stays in one
/// function scope.
async fn connect_chain(
    provider: &dyn IdeviceProvider,
) -> Result<(AdapterHandle, RsdHandshake), String> {
    let proxy = CoreDeviceProxy::connect(provider)
        .await
        .map_err(|e| format!("CoreDeviceProxy connect failed: {e}"))?;
    let rsd_port = proxy.tunnel_info().server_rsd_port;
    let adapter = proxy
        .create_software_tunnel()
        .map_err(|e| format!("software tunnel failed: {e}"))?;
    let mut adapter = adapter.to_async_handle();
    let stream = adapter
        .connect(rsd_port)
        .await
        .map_err(|e| format!("RSD connect failed: {e}"))?;
    let handshake = RsdHandshake::new(stream)
        .await
        .map_err(|e| format!("RSD handshake failed: {e}"))?;
    Ok((adapter, handshake))
}

/// Fail every command currently queued, non-blockingly.
fn drain_with_error(cmd_rx: &mut mpsc::Receiver<Command>, msg: &str) {
    while let Ok(cmd) = cmd_rx.try_recv() {
        cmd.fail(msg.to_string());
    }
}

/// The actor: resolves the provider, holds the DVT session, serves
/// commands, re-sends the active location on a timer, and reconnects on
/// failure. Runs until the command channel closes.
pub async fn run_actor(
    provider_args: ProviderArgs,
    mut cmd_rx: mpsc::Receiver<Command>,
    refresh: Duration,
) {
    // Last location the user asked for; survives reconnects (re-applied).
    let mut active: Option<(f64, f64)> = None;

    'outer: loop {
        let provider = match get_provider(
            provider_args.udid.as_deref(),
            provider_args.host.as_deref(),
            provider_args.pairing_file.as_deref(),
            &provider_args.label,
        )
        .await
        {
            Ok(provider) => provider,
            Err(e) => {
                tracing::warn!("no device provider: {e}");
                tokio::time::sleep(Duration::from_secs(2)).await;
                drain_with_error(&mut cmd_rx, &format!("no device: {e}"));
                continue 'outer;
            }
        };

        let (mut adapter, mut handshake) = match connect_chain(&*provider).await {
            Ok(chain) => chain,
            Err(e) => {
                tracing::warn!("device connect failed: {e}");
                tokio::time::sleep(Duration::from_secs(2)).await;
                drain_with_error(&mut cmd_rx, &format!("not connected to device: {e}"));
                continue 'outer;
            }
        };

        // Pin the stream type to 'static: RsdService is only implemented
        // for RemoteServerClient<Box<dyn ReadWrite + 'static>>.
        let mut rs_client: RemoteServerClient<Box<dyn ReadWrite>> =
            match RemoteServerClient::connect_rsd(&mut adapter, &mut handshake).await {
                Ok(client) => client,
                Err(e) => {
                    tracing::warn!("RemoteServer connect failed: {e}");
                    drain_with_error(&mut cmd_rx, &format!("RemoteServer connect failed: {e}"));
                    tokio::time::sleep(Duration::from_secs(2)).await;
                    continue 'outer;
                }
            };
        if rs_client.read_message(0).await.is_err() {
            tracing::warn!("RemoteServer initial read failed");
            continue 'outer;
        }
        let mut ls_client = match LocationSimulationClient::new(&mut rs_client).await {
            Ok(client) => client,
            Err(e) => {
                tracing::warn!("location simulation channel failed: {e}");
                drain_with_error(
                    &mut cmd_rx,
                    &format!("location simulation channel failed: {e}"),
                );
                tokio::time::sleep(Duration::from_secs(2)).await;
                continue 'outer;
            }
        };
        tracing::info!("DVT location simulation session established");

        // Re-apply the active location after a reconnect.
        if let Some((lat, lon)) = active
            && let Err(e) = ls_client.set(lat, lon).await
        {
            tracing::warn!("re-apply location failed: {e}");
            continue 'outer;
        }

        let mut ticker = tokio::time::interval(refresh);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

        loop {
            tokio::select! {
                biased;
                cmd = cmd_rx.recv() => {
                    let Some(cmd) = cmd else {
                        tracing::info!("command channel closed, actor stopping");
                        return;
                    };
                    match cmd {
                        Command::Set { lat, lon, reply } => {
                            match ls_client.set(lat, lon).await {
                                Ok(()) => {
                                    active = Some((lat, lon));
                                    tracing::info!("location set to {lat}, {lon}");
                                    let _ = reply.send(Ok(()));
                                }
                                Err(e) => {
                                    let _ = reply.send(Err(e.to_string()));
                                    continue 'outer;
                                }
                            }
                        }
                        Command::Clear { reply } => {
                            match ls_client.clear().await {
                                Ok(()) => {
                                    active = None;
                                    tracing::info!("location cleared");
                                    let _ = reply.send(Ok(()));
                                }
                                Err(e) => {
                                    let _ = reply.send(Err(e.to_string()));
                                    continue 'outer;
                                }
                            }
                        }
                        Command::Status { reply } => {
                            let _ = reply.send(SessionStatus {
                                connected: true,
                                active,
                            });
                        }
                    }
                }
                _ = ticker.tick() => {
                    if let Some((lat, lon)) = active
                        && let Err(e) = ls_client.set(lat, lon).await
                    {
                        tracing::warn!("periodic location refresh failed: {e}");
                        continue 'outer;
                    }
                }
            }
        }
    }
}
