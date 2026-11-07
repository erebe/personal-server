use maxminddb::{MaxMindDbError, Mmap, Reader, geoip2};
use std::net::IpAddr;
use std::path::Path;

/// Where an ip is, and who it belongs to.
#[derive(Debug, Default, PartialEq)]
pub struct IpInfo<'a> {
    pub country: Option<&'a str>,
    pub city: Option<&'a str>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub asn: Option<u32>,
    pub org: Option<&'a str>,
}

/// MaxMind-format databases resolving an ip to its location and to its owner, i.e the DB-IP lite ones.
#[derive(Debug)]
pub struct GeoIp {
    city: Option<Reader<Mmap>>,
    asn: Option<Reader<Mmap>>,
}

impl GeoIp {
    /// Both databases are optional, a missing one leaves its own fields empty instead of refusing to start.
    pub fn load(city_db: Option<&Path>, asn_db: Option<&Path>) -> Result<Self, MaxMindDbError> {
        Ok(Self {
            // mmap, as the city database is 120MB: only the pages actually looked up are faulted in, and the
            // kernel can drop them again under pressure. open_readfile would keep the whole file resident.
            // SAFETY: mmap is undefined behaviour if the file is written to while mapped. These are baked
            // read-only into the container image and replaced by a new image, never rewritten in place.
            city: city_db.map(|db| unsafe { Reader::open_mmap(db) }).transpose()?,
            asn: asn_db.map(|db| unsafe { Reader::open_mmap(db) }).transpose()?,
        })
    }

    /// A miss is normal (private ranges, gaps in the lite databases) and so is a record that fails to
    /// decode: both yield empty fields, a log line is not worth failing a request for.
    pub fn lookup(&self, ip: IpAddr) -> IpInfo<'_> {
        let location = self
            .city
            .as_ref()
            .and_then(|db| db.lookup(ip).ok()?.decode::<geoip2::City>().ok().flatten());
        let owner = self
            .asn
            .as_ref()
            .and_then(|db| db.lookup(ip).ok()?.decode::<geoip2::Asn>().ok().flatten());

        IpInfo {
            country: location.as_ref().and_then(|l| l.country.iso_code),
            city: location.as_ref().and_then(|l| l.city.names.english),
            latitude: location.as_ref().and_then(|l| l.location.latitude),
            longitude: location.as_ref().and_then(|l| l.location.longitude),
            asn: owner.as_ref().and_then(|o| o.autonomous_system_number),
            org: owner.as_ref().and_then(|o| o.autonomous_system_organization),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lookup_without_database() {
        let geoip = GeoIp::load(None, None).unwrap();
        assert_eq!(geoip.lookup("8.8.8.8".parse().unwrap()), IpInfo::default());
    }
}
