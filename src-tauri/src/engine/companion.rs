use super::*;
use std::net::Ipv4Addr;

pub(super) struct Info {
    port: u16,
    fingerprint: String,
    addresses: Vec<String>,
    ready: Instant,
}
#[derive(Serialize)]
pub struct Destination {
    address: String,
    payload: String,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CompanionOffer {
    destinations: Vec<Destination>,
    expires_in: u64,
}

pub(super) fn new_token() -> Result<String, String> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|_| "Не удалось создать ключ сеанса".to_string())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
pub(super) fn parse_ready(line: &str) -> Option<Info> {
    let p = line.split_whitespace().collect::<Vec<_>>();
    if p.len() != 4 || p[0] != "YANDA_COMPANION_READY" {
        return None;
    }
    let port = p[1].parse::<u16>().ok()?;
    if port == 0
        || p[2].len() != 64
        || !p[2]
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        return None;
    }
    let mut addresses = p[3]
        .split(',')
        .filter_map(|s| {
            let ip = s.parse::<Ipv4Addr>().ok()?;
            (ip.is_private() || ip.is_link_local()).then(|| ip.to_string())
        })
        .collect::<Vec<_>>();
    addresses.sort_by_key(|a| {
        if a.starts_with("192.168.") {
            0
        } else if a.starts_with("10.") {
            1
        } else {
            2
        }
    });
    addresses.dedup();
    addresses.truncate(8);
    if addresses.is_empty() {
        return None;
    }
    Some(Info {
        port,
        fingerprint: p[2].into(),
        addresses,
        ready: Instant::now(),
    })
}
impl Backend {
    pub(super) fn companion_exe(&self) -> PathBuf {
        self.root.join("runtime/android-yanda/yanda-android.exe")
    }
    pub fn companion_offer(&self) -> Result<CompanionOffer, String> {
        if self.source != "android" || self.phase != "waiting" || self.media.is_none() {
            return Err("Сначала включите Android-приёмник".into());
        }
        let info = self
            .companion_info
            .as_ref()
            .ok_or("Подключение телефона уже началось")?;
        let token = self.companion_token.as_ref().ok_or("QR уже использован")?;
        let expires = 180u64.saturating_sub(info.ready.elapsed().as_secs());
        if expires == 0 {
            return Err("Срок QR истёк. Создайте новый код".into());
        }
        Ok(CompanionOffer {
            destinations: info
                .addresses
                .iter()
                .map(|a| Destination {
                    address: a.clone(),
                    payload: format!(
                        "yanda://connect?v=3&host={a}&alt={}&port={}&fp={}&token={token}",
                        info.addresses
                            .iter()
                            .filter(|other| *other != a)
                            .cloned()
                            .collect::<Vec<_>>()
                            .join(","),
                        info.port,
                        info.fingerprint
                    ),
                })
                .collect(),
            expires_in: expires,
        })
    }
    pub fn open_android_apk(&self) -> Result<(), String> {
        let name = concat!("Y-AND-A-", env!("CARGO_PKG_VERSION"), "-android.apk");
        let path = if self.root.join(name).is_file() {
            self.root.join(name)
        } else {
            self.root.join("release").join(name)
        };
        if !path.is_file() {
            return Err("APK не найден рядом с приложением. Распакуйте полную сборку.".into());
        }
        Command::new("explorer.exe")
            .arg(format!("/select,{}", path.display()))
            .spawn()
            .map_err(|_| "Не удалось открыть папку APK".to_string())?;
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn strict_readiness() {
        let fp = "a".repeat(64);
        let r = parse_ready(&format!(
            "YANDA_COMPANION_READY 12345 {fp} 192.168.1.2,8.8.8.8,127.0.0.1"
        ))
        .unwrap();
        assert_eq!(r.addresses, vec!["192.168.1.2"]);
        assert!(parse_ready(&format!("YANDA_COMPANION_READY 0 {fp} 192.168.1.1")).is_none());
        assert!(parse_ready(&format!("YANDA_COMPANION_READY 12 {fp} 8.8.8.8")).is_none());
        assert!(parse_ready("YANDA_COMPANION_READY 12 secret 192.168.1.1").is_none());
    }
    #[test]
    fn token_freshness() {
        let a = new_token().unwrap();
        assert_eq!(a.len(), 64);
        assert_ne!(a, new_token().unwrap());
    }
}
