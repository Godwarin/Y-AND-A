use crate::native::{self, Job, Rect};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    io::{BufRead, BufReader, Read, Write},
    net::{SocketAddr, TcpListener},
    os::windows::process::CommandExt,
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::mpsc::{self, Receiver},
    time::{Duration, Instant},
};

const NO_WINDOW: u32 = 0x08000000;
mod companion;
pub use companion::CompanionOffer;
#[derive(Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ConnectRequest {
    pub source: String,
    pub quality: String,
    pub fps: u32,
    pub audio: bool,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub phase: String,
    pub source: String,
    pub message: String,
    pub audio: String,
    pub audio_message: String,
    pub resolution: Option<String>,
    pub elapsed: u64,
    pub logs: Vec<String>,
    pub companion_ready: bool,
    pub apk_ready: bool,
    pub airplay_ready: bool,
    pub embedded: bool,
    pub window_visible: bool,
    pub engine_pid: Option<u32>,
    pub airplay_approval: Option<AirplayApproval>,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AirplayApproval {
    request_id: String,
    fingerprint: String,
    address: String,
    #[serde(skip)]
    received: Instant,
}
pub struct Backend {
    root: PathBuf,
    data: PathBuf,
    job: Job,
    parent: isize,
    host: isize,
    child_hwnd: isize,
    media: Option<Child>,
    events: Option<Receiver<String>>,
    phase: String,
    source: String,
    message: String,
    audio: String,
    audio_message: String,
    video: (i32, i32),
    started: Option<Instant>,
    logs: VecDeque<String>,
    pub bounds: Rect,
    pub top_limit: i32,
    pub fill: bool,
    pub closed: bool,
    volume: f32,
    muted: bool,
    last_volume: Option<Instant>,
    ready_signal: bool,
    companion_token: Option<String>,
    companion_info: Option<companion::Info>,
    airplay_approval: Option<AirplayApproval>,
}
impl Backend {
    pub fn new(root: PathBuf, data: PathBuf, parent: isize) -> Result<Self, String> {
        Ok(Self {
            root,
            data,
            job: Job::new()?,
            parent,
            host: native::host(parent)?,
            child_hwnd: 0,
            media: None,
            events: None,
            phase: "idle".into(),
            source: "android".into(),
            message: "Готово к подключению".into(),
            audio: "waiting".into(),
            audio_message: "Звук появится вместе с трансляцией".into(),
            video: (0, 0),
            started: None,
            logs: VecDeque::new(),
            bounds: Rect {
                x: 0,
                y: 0,
                w: 800,
                h: 600,
            },
            top_limit: 0,
            fill: false,
            closed: false,
            volume: 0.8,
            muted: false,
            last_volume: None,
            ready_signal: false,
            companion_token: None,
            companion_info: None,
            airplay_approval: None,
        })
    }
    fn airplay_exe(&self) -> PathBuf {
        self.root.join("runtime/airplay-yanda/airplay-windows.exe")
    }
    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            phase: self.phase.clone(),
            source: self.source.clone(),
            message: self.message.clone(),
            audio: self.audio.clone(),
            audio_message: self.audio_message.clone(),
            resolution: (self.video.0 > 0).then(|| format!("{} × {}", self.video.0, self.video.1)),
            elapsed: self.started.map_or(0, |s| s.elapsed().as_secs()),
            logs: self.logs.iter().cloned().collect(),
            companion_ready: self.companion_exe().is_file(),
            apk_ready: self
                .root
                .join(concat!(
                    "Y-AND-A-",
                    env!("CARGO_PKG_VERSION"),
                    "-android.apk"
                ))
                .is_file()
                || self
                    .root
                    .join(concat!(
                        "release/Y-AND-A-",
                        env!("CARGO_PKG_VERSION"),
                        "-android.apk"
                    ))
                    .is_file(),
            airplay_ready: self.airplay_exe().is_file(),
            embedded: self.child_hwnd != 0,
            window_visible: native::window_visible(self.parent),
            engine_pid: self.media.as_ref().map(Child::id),
            airplay_approval: self.airplay_approval.clone(),
        }
    }
    fn note(&mut self, text: &str) {
        if self.logs.back().map(String::as_str) != Some(text) {
            self.logs.push_back(text.into());
            if self.logs.len() > 40 {
                self.logs.pop_front();
            }
        }
    }
    pub fn start(&mut self, request: ConnectRequest) -> Result<Snapshot, String> {
        if self.closed {
            return Err("Приложение закрывается".into());
        }
        if !["android", "airplay"].contains(&request.source.as_str()) {
            return Err("Неизвестный источник".into());
        }
        if !["auto", "1080", "1600", "original"].contains(&request.quality.as_str())
            || ![0, 30, 60].contains(&request.fps)
        {
            return Err("Некорректные параметры качества".into());
        }
        if self.media.is_some() {
            return Err("Сначала остановите текущий сеанс".into());
        }
        self.companion_info = None;
        self.companion_token = None;
        if request.source == "android" {
            self.companion_token = Some(companion::new_token()?);
        }
        self.source = request.source.clone();
        self.phase = if self.phase == "error" {
            "reconnecting"
        } else {
            "connecting"
        }
        .into();
        self.message = "Запуск медиадвижка…".into();
        self.video = (0, 0);
        self.ready_signal = false;
        self.last_volume = None;
        self.child_hwnd = 0;
        self.audio = if request.audio { "waiting" } else { "disabled" }.into();
        self.audio_message = if request.audio {
            "Ожидание аудиопотока"
        } else {
            "Передача звука выключена"
        }
        .into();
        let result = self.spawn_media(&request);
        match result {
            Ok(()) => {
                self.started = Some(Instant::now());
                self.note("Запуск сеанса");
                Ok(self.snapshot())
            }
            Err(e) => {
                self.phase = "error".into();
                self.message = e.clone();
                self.note(&e);
                Err(e)
            }
        }
    }
    fn spawn_media(&mut self, r: &ConnectRequest) -> Result<(), String> {
        let mut cmd;
        if r.source == "airplay" {
            let exe = self.airplay_exe();
            if !exe.is_file() {
                return Err(
                    "Приёмник AirPlay ещё не собран. См. docs/BUILD_FROM_SOURCE.md"
                        .into(),
                );
            }
            let state_dir = self.data.join("airplay");
            std::fs::create_dir_all(&state_dir).map_err(|e| e.to_string())?;
            // Reject a competing receiver before announcing our identity.
            if std::net::TcpStream::connect_timeout(
                &SocketAddr::from(([127, 0, 0, 1], 7000)),
                Duration::from_millis(200),
            )
            .is_ok()
                || std::net::TcpStream::connect_timeout(
                    &SocketAddr::from((std::net::Ipv6Addr::LOCALHOST, 7000)),
                    Duration::from_millis(200),
                )
                .is_ok()
            {
                return Err(
                    "Порт AirPlay 7000 занят. Закройте другой приёмник и повторите запуск.".into(),
                );
            }
            let listener = TcpListener::bind("0.0.0.0:7000").map_err(|_| {
                "Порт AirPlay 7000 занят. Закройте другой приёмник и повторите запуск.".to_string()
            })?;
            drop(listener);
            cmd = Command::new(&exe);
            cmd.current_dir(&state_dir)
                .env("YANDA_AIRPLAY_STATE_DIR", &state_dir)
                .env("YANDA_EMBEDDED", "1")
                .args([
                    "--log",
                    "--mirror-res",
                    match r.quality.as_str() {
                        "1080" => "1080x1080",
                        "1600" => "1600x1600",
                        _ => "2560x2560",
                    },
                ]);
            if !r.audio {
                cmd.env("YANDA_AUDIO_DISABLED", "1");
            }
            if !r.audio {
                self.muted = true;
            }
        } else {
            let exe = self.companion_exe();
            if !exe.is_file() {
                return Err("Android-приёмник не найден. Распакуйте полную сборку Y AND A.".into());
            }
            cmd = Command::new(&exe);
            cmd.current_dir(exe.parent().unwrap())
                .arg("--max-size")
                .arg(match r.quality.as_str() {
                    "1080" => "1080",
                    "1600" => "1600",
                    "original" => "2560",
                    _ => "1920",
                })
                .arg("--fps")
                .arg(if r.fps == 60 { "60" } else { "30" });
            if !r.audio {
                cmd.arg("--no-audio");
            }
        }
        cmd.creation_flags(NO_WINDOW)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = cmd
            .spawn()
            .map_err(|e| format!("Не удалось запустить медиадвижок: {e}"))?;
        if let Err(e) = self.job.assign(child.id()) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(e);
        }
        if r.source == "android" {
            let secret = self
                .companion_token
                .as_ref()
                .ok_or("Нет токена подключения")?;
            let written = child
                .stdin
                .take()
                .is_some_and(|mut input| writeln!(input, "{secret}").is_ok());
            if !written {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Не удалось подготовить защищённое подключение".into());
            }
        }
        let (tx, rx) = mpsc::sync_channel(256);
        for reader in [
            child
                .stdout
                .take()
                .map(|r| Box::new(r) as Box<dyn std::io::Read + Send>),
            child
                .stderr
                .take()
                .map(|r| Box::new(r) as Box<dyn std::io::Read + Send>),
        ]
        .into_iter()
        .flatten()
        {
            let tx = tx.clone();
            std::thread::spawn(move || {
                let mut input = BufReader::new(reader);
                let mut bytes = Vec::new();
                loop {
                    bytes.clear();
                    let mut limited = input.by_ref().take(4097);
                    match limited.read_until(b'\n', &mut bytes) {
                        Ok(0) | Err(_) => break,
                        Ok(_) => {}
                    }
                    if bytes.len() > 4096 {
                        break;
                    }
                    if let Ok(line) = String::from_utf8(bytes.clone()) {
                        if tx.send(line.trim_end().to_owned()).is_err() {
                            break;
                        }
                    }
                }
            });
        }
        self.events = Some(rx);
        self.media = Some(child);
        Ok(())
    }
    pub fn poll(&mut self) {
        if self
            .airplay_approval
            .as_ref()
            .is_some_and(|a| a.received.elapsed() > Duration::from_secs(20))
        {
            self.airplay_approval = None;
        }
        let lines = self
            .events
            .as_ref()
            .map(|rx| rx.try_iter().take(200).collect::<Vec<_>>())
            .unwrap_or_default();
        for line in lines {
            self.parse_event(&line);
        }
        if let Some(child) = self.media.as_mut() {
            if let Ok(Some(exit)) = child.try_wait() {
                self.media = None;
                self.airplay_approval = None;
                self.events = None;
                self.child_hwnd = 0;
                if self.host != 0 {
                    native::hide(self.host);
                }
                let was_waiting = self.phase == "waiting";
                self.phase = "error".into();
                if self.message == "Трансляция идёт"
                    || self.message == "Запуск медиадвижка…"
                    || was_waiting
                {
                    self.message =
                        "Медиадвижок завершился. Проверьте соединение и подключитесь снова.".into();
                }
                if exit.code() == Some(0xc0000135u32 as i32) {
                    self.message="Не найден DLL-компонент медиадвижка. Распакуйте всю папку runtime рядом с Y AND A.exe.".into();
                }
                self.note("Медиадвижок остановлен");
                return;
            }
        } else {
            return;
        }
        if matches!(self.phase.as_str(), "connecting" | "reconnecting")
            && self
                .started
                .is_some_and(|t| t.elapsed() > Duration::from_secs(30))
        {
            self.fail(if self.source=="airplay" {"AirPlay не подтвердил регистрацию mDNS за 30 секунд. Проверьте локальную сеть и службу DNS Windows."} else {"Видеопоток не поступил за 30 секунд. Разблокируйте телефон и повторите подключение."});
            return;
        }
        if self.child_hwnd == 0 {
            let pid = self.media.as_ref().unwrap().id();
            if let Some(hwnd) = native::find(pid) {
                // Host is created during Tauri setup on the UI thread. IPC runs
                // on workers so cross-thread Win32 messages cannot deadlock it.
                if self.host == 0 {
                    match native::host(self.parent) {
                        Ok(h) => self.host = h,
                        Err(e) => {
                            self.fail(&e);
                            return;
                        }
                    }
                }
                match native::attach(hwnd, self.host) {
                    Ok(()) => {
                        self.child_hwnd = hwnd;
                        self.note("Видео встроено в основное окно");
                    }
                    Err(e) => {
                        self.fail(&e);
                        return;
                    }
                }
            } else if self
                .started
                .is_some_and(|t| t.elapsed() > Duration::from_secs(25))
            {
                self.fail(
                    "Медиадвижок не создал видеоповерхность за 25 секунд. Проверьте подключение.",
                );
                return;
            }
        }
        if ["airplay", "android"].contains(&self.source.as_str())
            && matches!(self.phase.as_str(), "connecting" | "reconnecting")
            && self.ready_signal
            && self.child_hwnd != 0
        {
            self.phase = "waiting".into();
            self.message = if self.source == "android" {
                "Сканируйте QR в Android-приложении Y AND A"
            } else {
                "На iPhone выберите Y AND A в «Повторе экрана»"
            }
            .into();
        }
        self.layout();
        if self.audio != "disabled"
            && self.audio != "unavailable"
            && (self.phase == "streaming" || self.audio == "active")
            && self
                .last_volume
                .is_none_or(|t| t.elapsed() > Duration::from_secs(2))
        {
            let applied = self.volume(self.volume, self.muted).unwrap_or(false);
            if applied && self.audio == "waiting" {
                self.audio = "active".into();
                self.audio_message =
                    "Аудиовывод открыт; защищённые приложения могут запрещать звук".into();
            }
            self.last_volume = applied.then(Instant::now);
        }
    }
    fn parse_event(&mut self, line: &str) {
        if self.source == "airplay" {
            if let Some((_, tail)) = line.split_once("YANDA_APPROVAL ") {
                let p = tail.split_whitespace().collect::<Vec<_>>();
                let hex = |s: &str, n: usize| {
                    s.len() == n
                        && s.bytes()
                            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
                };
                if p.len() == 3
                    && hex(p[0], 32)
                    && hex(p[1], 64)
                    && p[2].parse::<std::net::IpAddr>().is_ok()
                {
                    self.airplay_approval = Some(AirplayApproval {
                        request_id: p[0].into(),
                        fingerprint: p[1].into(),
                        address: p[2].into(),
                        received: Instant::now(),
                    });
                }
                return;
            }
            if let Some((_, id)) = line.split_once("YANDA_APPROVAL_END ") {
                if self
                    .airplay_approval
                    .as_ref()
                    .is_some_and(|a| a.request_id == id.trim())
                {
                    self.airplay_approval = None;
                }
                return;
            }
        }
        if self.source == "android" {
            if line.starts_with("YANDA_COMPANION_READY ") {
                if let Some(info) = companion::parse_ready(line) {
                    self.companion_info = Some(info);
                    self.ready_signal = true;
                    self.note("Android: защищённый приёмник готов");
                } else {
                    self.fail("На ПК не найден локальный IPv4. Подключите телефон и ПК к одной локальной сети.");
                }
                return;
            }
            if line == "YANDA_COMPANION_CONNECTED" {
                self.ready_signal = false;
                self.companion_info = None;
                self.companion_token = None;
                self.phase = "connecting".into();
                self.started = Some(Instant::now());
                self.message = "Android подключён. Ожидаем видеопоток…".into();
                self.note("Android: защищённое соединение установлено");
                return;
            }
            if line == "YANDA_COMPANION_DISCONNECTED" {
                if self.phase == "error" {
                    return;
                }
                self.stop();
                self.message = "Android завершил трансляцию".into();
                return;
            }
            if line == "YANDA_COMPANION_EXPIRED" {
                self.fail("Срок QR истёк. Нажмите «Создать новый QR-код».");
                return;
            }
            if line == "YANDA_AUDIO_UNAVAILABLE" {
                if self.audio == "disabled" {
                    return;
                }
                self.audio = "unavailable".into();
                self.audio_message="Android не передаёт звук. Проверьте разрешение в приложении; некоторые приложения запрещают захват звука.".into();
                return;
            }
        }
        if self.source == "android" && line == "YANDA_ERROR" {
            self.fail("Android: ошибка видеопотока или соединения. Завершите трансляцию и создайте новый QR-код.");
            return;
        }
        let low = line.to_lowercase();
        if let Some(size) = parse_resolution(line) {
            self.video = size;
        }
        if (self.source != "airplay"
            && line.contains("Texture")
            && parse_resolution(line).is_some())
            || line.contains("YANDA_VIDEO ")
        {
            self.phase = "streaming".into();
            self.message = "Трансляция идёт".into();
            self.note("Получен видеопоток");
        }
        if line.contains("YANDA_READY") {
            self.note("AirPlay: сервер запущен");
        }
        if line.contains("YANDA_BIND_ERROR") {
            self.fail(
                "AirPlay не смог открыть TCP 7000: порт занят или Windows запретила прослушивание.",
            );
            return;
        }
        if line.contains("YANDA_MDNS_AIRPLAY_REGISTERED") {
            self.ready_signal = true;
            self.note("AirPlay: объявление Y AND A зарегистрировано Windows mDNS");
        }
        if line.contains("YANDA_MDNS_RAOP_REGISTERED") {
            self.note("AirPlay: RAOP объявление зарегистрировано Windows mDNS");
        }
        if line.contains("YANDA_MDNS_AIRPLAY_ERROR") {
            self.fail("Windows mDNS не зарегистрировал Y AND A. Проверьте локальную сеть, службу DNS и другой AirPlay-приёмник.");
            return;
        }
        if line.contains("YANDA_MDNS_ERROR") {
            self.message="AirPlay: Windows mDNS не зарегистрировал приёмник. Проверьте сеть и конфликт другого приёмника.".into();
        }
        if line.contains("YANDA_DISCONNECTED") {
            self.phase = "waiting".into();
            self.message = "iPhone завершил трансляцию. Приёмник ожидает подключение.".into();
            self.video = (0, 0);
            self.audio = "waiting".into();
            self.note("AirPlay: отправитель отключился");
        }
        if (low.contains("audio")
            && (low.contains("disabled")
                || low.contains("could not")
                || low.contains("failed")
                || low.contains("not supported")))
            && self.audio != "disabled"
        {
            self.audio = "unavailable".into();
            self.audio_message="Захват или вывод звука недоступен. Проверьте разрешение на аудио в Android-приложении и вывод Windows; защищённые приложения могут запрещать звук.".into();
            self.note("Звук недоступен; видео продолжает работать");
        }
        if self.audio != "disabled"
            && (line.ends_with("YANDA_AUDIO")
                || line.contains("Audio: ")
                || line.contains("Audio device:")
                || line.contains("Audio output:"))
        {
            self.audio = "active".into();
            self.audio_message =
                "Аудиопоток открыт; защищённые приложения могут запрещать звук".into();
        }
        if self.audio != "disabled" && line.contains("YANDA_AUDIO_UNAVAILABLE") {
            self.audio = "unavailable".into();
            self.audio_message="AirPlay не открыл аудиопоток или вывод Windows. Проверьте устройство вывода и повторите сеанс.".into();
            self.note("AirPlay: звук недоступен, видео продолжает работать");
        }
        if low.contains("unauthorized") {
            self.message = "Разрешите отладку по USB на телефоне".into();
        }
        if low.contains("error:") || low.contains("[error]") {
            self.note("Медиадвижок сообщил об ошибке; проверьте соединение и настройки звука");
        }
        if line.contains("YANDA_ERROR") {
            self.message = "AirPlay: ошибка сеанса. Проверьте сеть и повторите подключение.".into();
            self.note("AirPlay: ошибка сеанса");
        }
    }
    fn fail(&mut self, message: &str) {
        self.stop();
        self.phase = "error".into();
        self.message = message.into();
        self.note(message);
    }
    pub fn layout(&self) {
        if self.host != 0 && self.child_hwnd != 0 {
            let intersects = native::clip(self.host, self.bounds, self.top_limit);
            native::layout(
                self.host,
                self.child_hwnd,
                self.bounds,
                self.video,
                self.fill,
                self.phase == "streaming" && intersects,
            );
        }
    }
    pub fn volume(&mut self, level: f32, muted: bool) -> Result<bool, String> {
        self.volume = level;
        self.muted = muted;
        if let Some(child) = &self.media {
            native::volume(child.id(), level, muted)
        } else {
            Ok(false)
        }
    }
    pub fn stop(&mut self) {
        if self.host != 0 {
            native::hide(self.host);
        }
        if let Some(mut child) = self.media.take() {
            if self.child_hwnd != 0 {
                native::close(self.child_hwnd);
            }
            let deadline = Instant::now() + Duration::from_secs(3);
            while Instant::now() < deadline {
                if child.try_wait().ok().flatten().is_some() {
                    break;
                }
                std::thread::sleep(Duration::from_millis(30));
            }
            if child.try_wait().ok().flatten().is_none() {
                let _ = child.kill();
            }
            let _ = child.wait();
        }
        self.events = None;
        self.airplay_approval = None;
        self.companion_token = None;
        self.companion_info = None;
        self.child_hwnd = 0;
        self.started = None;
        self.phase = "idle".into();
        self.message = "Сеанс остановлен".into();
        self.audio = "waiting".into();
        self.audio_message = "Звук появится вместе с трансляцией".into();
        self.video = (0, 0);
        self.note("Сеанс остановлен, ресурсы освобождены");
    }
    pub fn approve_airplay(&mut self, request_id: String, allow: bool) -> Result<(), String> {
        let pending = self
            .airplay_approval
            .as_ref()
            .ok_or("Запрос уже завершён")?;
        if self.source != "airplay"
            || pending.request_id != request_id
            || pending.received.elapsed() > Duration::from_secs(20)
        {
            return Err("Запрос уже завершён".into());
        }
        let input = self
            .media
            .as_mut()
            .and_then(|p| p.stdin.as_mut())
            .ok_or("Приёмник остановлен")?;
        writeln!(
            input,
            "{} {}",
            if allow { "ALLOW" } else { "DENY" },
            request_id
        )
        .map_err(|_| "Приёмник недоступен".to_string())?;
        input
            .flush()
            .map_err(|_| "Приёмник недоступен".to_string())?;
        self.airplay_approval = None;
        self.note(if allow {
            "AirPlay: подключение разрешено владельцем"
        } else {
            "AirPlay: подключение отклонено владельцем"
        });
        Ok(())
    }
    pub fn shutdown(&mut self) {
        self.stop();
        self.closed = true;
    }
}
impl Drop for Backend {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn parse_resolution(line: &str) -> Option<(i32, i32)> {
    if !(line.contains("Texture") || line.contains("texture") || line.contains("YANDA_VIDEO")) {
        return None;
    }
    for token in line.split(|c: char| !(c.is_ascii_digit() || c == 'x')) {
        if let Some((w, h)) = token.split_once('x') {
            if let (Ok(w), Ok(h)) = (w.parse::<i32>(), h.parse::<i32>()) {
                if (1..=16384).contains(&w) && (1..=16384).contains(&h) {
                    return Some((w, h));
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rotated_texture() {
        assert_eq!(
            parse_resolution("INFO: Texture: 2400x1080"),
            Some((2400, 1080))
        );
        assert_eq!(
            parse_resolution("YANDA_VIDEO 1080x2400"),
            Some((1080, 2400))
        );
        assert_eq!(parse_resolution("address=192.168.1.1"), None);
    }
    #[test]
    fn hardware_texture() {
        assert_eq!(
            parse_resolution("INFO: Texture (D3D11VA): 1080x2400"),
            Some((1080, 2400))
        );
    }
}
