#!/usr/bin/env python3
"""Generate Resources/airports_iata.json from OurAirports and countries.json.

Reads OurAirports public-domain `airports.csv` (downloaded automatically unless
`--csv` is supplied) together with `countries.json`, normalizes metropolitan
hub city names and overseas territories not listed separately in `countries.json`,
and writes compact `[ISO3, city, lat, lon]` entries keyed by 3-letter IATA code.

Usage:
    python3 scripts/generate_airports.py
    python3 scripts/generate_airports.py --csv /path/to/airports.csv
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import urllib.request
from pathlib import Path

OURAIRPORTS_CSV_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_COUNTRIES_PATH = REPO_ROOT / "where-can-i-go-ios/whereCanIGo/Resources/countries.json"
DEFAULT_OUTPUT_PATH = REPO_ROOT / "where-can-i-go-ios/whereCanIGo/Resources/airports_iata.json"

AIRPORT_TYPE_PRIORITY = {
    "large_airport": 5,
    "medium_airport": 4,
    "small_airport": 3,
    "seaplane_base": 2,
    "heliport": 1,
    "balloonport": 0,
}

# Overseas territories absent from `countries.json` -> (sovereign ISO3, territory label).
OVERSEAS_TERRITORY_MAP: dict[str, tuple[str, str]] = {
    "AS": ("USA", "American Samoa"),
    "GU": ("USA", "Guam"),
    "PR": ("USA", "Puerto Rico"),
    "UM": ("USA", "U.S. Outlying Islands"),
    "VI": ("USA", "U.S. Virgin Islands"),
    "CC": ("AUS", "Cocos Islands"),
    "CX": ("AUS", "Christmas Island"),
    "NF": ("AUS", "Norfolk Island"),
    "GG": ("GBR", "Guernsey"),
    "IM": ("GBR", "Isle of Man"),
    "IO": ("GBR", "British Indian Ocean Territory"),
    "JE": ("GBR", "Jersey"),
    "KY": ("GBR", "Cayman Islands"),
    "AX": ("FIN", "Åland Islands"),
    "SJ": ("NOR", "Svalbard"),
}

# Multi-airport metropolitan hubs where OurAirports `municipality` names a
# suburb, ward, island, or neighbouring town instead of the metro city.
METRO_CITY_OVERRIDES: dict[str, str] = {
    # East Asia
    "HKG": "Hong Kong",
    "MFM": "Macau",
    "TPE": "Taipei",
    "TSA": "Taipei",
    "RMQ": "Taichung",
    "KHH": "Kaohsiung",
    "NRT": "Tokyo",
    "HND": "Tokyo",
    "KIX": "Osaka",
    "ITM": "Osaka",
    "UKB": "Kobe",
    "NGO": "Nagoya",
    "NKM": "Nagoya",
    "CTS": "Sapporo",
    "OKD": "Sapporo",
    "FUK": "Fukuoka",
    "OKA": "Okinawa",
    "ICN": "Seoul",
    "GMP": "Seoul",
    "PUS": "Busan",
    "CJU": "Jeju",
    "PEK": "Beijing",
    "PKX": "Beijing",
    "NAY": "Beijing",
    "PVG": "Shanghai",
    "SHA": "Shanghai",
    "CAN": "Guangzhou",
    "SZX": "Shenzhen",
    "CTU": "Chengdu",
    "TFU": "Chengdu",
    "CKG": "Chongqing",
    "XIY": "Xi'an",
    "HGH": "Hangzhou",
    "NKG": "Nanjing",
    "WUH": "Wuhan",
    "KMG": "Kunming",
    "CSX": "Changsha",
    "TAO": "Qingdao",
    "XMN": "Xiamen",
    "HAK": "Haikou",
    "SYX": "Sanya",
    "HUZ": "Huizhou",
    # Southeast Asia & Oceania
    "SIN": "Singapore",
    "XSP": "Singapore",
    "BKK": "Bangkok",
    "DMK": "Bangkok",
    "HKT": "Phuket",
    "CNX": "Chiang Mai",
    "KUL": "Kuala Lumpur",
    "SZB": "Kuala Lumpur",
    "PEN": "Penang",
    "BKI": "Kota Kinabalu",
    "CGK": "Jakarta",
    "HLP": "Jakarta",
    "DPS": "Bali",
    "SUB": "Surabaya",
    "MNL": "Manila",
    "CRK": "Clark",
    "CEB": "Cebu",
    "SGN": "Ho Chi Minh City",
    "HAN": "Hanoi",
    "DAD": "Da Nang",
    "SYD": "Sydney",
    "MEL": "Melbourne",
    "AVV": "Melbourne",
    "BNE": "Brisbane",
    "OOL": "Gold Coast",
    "PER": "Perth",
    "ADL": "Adelaide",
    "AKL": "Auckland",
    "ZQN": "Queenstown",
    # South Asia & Middle East
    "DEL": "New Delhi",
    "BOM": "Mumbai",
    "BLR": "Bengaluru",
    "MAA": "Chennai",
    "HYD": "Hyderabad",
    "CCU": "Kolkata",
    "DXB": "Dubai",
    "DWC": "Dubai",
    "AUH": "Abu Dhabi",
    "DOH": "Doha",
    "IST": "Istanbul",
    "SAW": "Istanbul",
    "ISL": "Istanbul",
    # Europe
    "LHR": "London",
    "LGW": "London",
    "STN": "London",
    "LTN": "London",
    "LCY": "London",
    "SEN": "London",
    "MAN": "Manchester",
    "EDI": "Edinburgh",
    "CDG": "Paris",
    "ORY": "Paris",
    "BVA": "Paris",
    "FRA": "Frankfurt",
    "HHN": "Frankfurt",
    "MUC": "Munich",
    "BER": "Berlin",
    "AMS": "Amsterdam",
    "BRU": "Brussels",
    "CRL": "Brussels",
    "ZRH": "Zurich",
    "GVA": "Geneva",
    "VIE": "Vienna",
    "MXP": "Milan",
    "LIN": "Milan",
    "BGY": "Milan",
    "FCO": "Rome",
    "CIA": "Rome",
    "VCE": "Venice",
    "TSF": "Venice",
    "NAP": "Naples",
    "MAD": "Madrid",
    "BCN": "Barcelona",
    "LIS": "Lisbon",
    "OPO": "Porto",
    "ATH": "Athens",
    "ARN": "Stockholm",
    "BMA": "Stockholm",
    "NYO": "Stockholm",
    "OSL": "Oslo",
    "TRF": "Oslo",
    "CPH": "Copenhagen",
    "HEL": "Helsinki",
    "WAW": "Warsaw",
    "WMI": "Warsaw",
    "PRG": "Prague",
    "BUD": "Budapest",
    "DUB": "Dublin",
    "KEF": "Reykjavik",
    "RKV": "Reykjavik",
    "SVO": "Moscow",
    "DME": "Moscow",
    "VKO": "Moscow",
    # Americas
    "JFK": "New York",
    "EWR": "New York",
    "LGA": "New York",
    "LAX": "Los Angeles",
    "BUR": "Los Angeles",
    "SNA": "Los Angeles",
    "ONT": "Los Angeles",
    "LGB": "Los Angeles",
    "SFO": "San Francisco",
    "OAK": "Oakland",
    "SJC": "San Jose",
    "ORD": "Chicago",
    "MDW": "Chicago",
    "IAD": "Washington, D.C.",
    "DCA": "Washington, D.C.",
    "BWI": "Baltimore",
    "DFW": "Dallas",
    "DAL": "Dallas",
    "IAH": "Houston",
    "HOU": "Houston",
    "MIA": "Miami",
    "FLL": "Fort Lauderdale",
    "MCO": "Orlando",
    "SFB": "Orlando",
    "SEA": "Seattle",
    "BOS": "Boston",
    "ATL": "Atlanta",
    "LAS": "Las Vegas",
    "DEN": "Denver",
    "PHX": "Phoenix",
    "DTW": "Detroit",
    "MSP": "Minneapolis",
    "PHL": "Philadelphia",
    "HNL": "Honolulu",
    "GUM": "Guam",
    "YYZ": "Toronto",
    "YTZ": "Toronto",
    "YVR": "Vancouver",
    "YUL": "Montreal",
    "YYC": "Calgary",
    "MEX": "Mexico City",
    "NLU": "Mexico City",
    "CUN": "Cancun",
    "GRU": "São Paulo",
    "CGH": "São Paulo",
    "VCP": "São Paulo",
    "GIG": "Rio de Janeiro",
    "SDU": "Rio de Janeiro",
    "EZE": "Buenos Aires",
    "AEP": "Buenos Aires",
    "SCL": "Santiago",
    "LIM": "Lima",
    "BOG": "Bogotá",
}

# Decommissioned passenger hubs cleared from active OurAirports `iata_code`
# that still appear in historical Flighty exports.
HISTORICAL_FALLBACKS: dict[str, list[object]] = {
    "TXL": ["DEU", "Berlin", 52.5597, 13.2877],
    "SXF": ["DEU", "Berlin", 52.3800, 13.5225],
    "THF": ["DEU", "Berlin", 52.4730, 13.4039],
}

_PAREN_RE = re.compile(r"\s*\([^)]*\)")


def clean_city(raw_city: str) -> str:
    city = _PAREN_RE.sub("", raw_city or "").strip(" ,")
    city = re.sub(r"\s+", " ", city)
    return city


def load_iso2_to_iso3(countries_path: Path) -> dict[str, str]:
    with countries_path.open("r", encoding="utf-8") as fh:
        entries = json.load(fh)
    return {
        entry["iso2"].strip().upper(): entry["code"].strip().upper()
        for entry in entries
        if entry.get("iso2") and entry.get("code")
    }


def read_ourairports_csv(csv_path: Path | None) -> str:
    if csv_path is not None:
        return csv_path.read_text(encoding="utf-8")
    req = urllib.request.Request(
        OURAIRPORTS_CSV_URL,
        headers={"User-Agent": "where-can-i-go-airport-generator/1.0"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8")


def build_airport_catalog(csv_text: str, iso2_to_iso3: dict[str, str]) -> dict[str, list[object]]:
    best_by_iata: dict[str, tuple[tuple[int, int], list[object]]] = {}
    reader = csv.DictReader(io.StringIO(csv_text))

    for row in reader:
        airport_type = (row.get("type") or "").strip()
        if airport_type not in AIRPORT_TYPE_PRIORITY:
            continue

        iata = (row.get("iata_code") or "").strip().upper()
        if len(iata) != 3 or not iata.isascii() or not iata.isalpha():
            continue

        iso2 = (row.get("iso_country") or "").strip().upper()
        territory_suffix: str | None = None
        if iso2 in iso2_to_iso3:
            iso3 = iso2_to_iso3[iso2]
        elif iso2 in OVERSEAS_TERRITORY_MAP:
            iso3, territory_suffix = OVERSEAS_TERRITORY_MAP[iso2]
        else:
            continue

        try:
            lat = round(float(row["latitude_deg"]), 4)
            lon = round(float(row["longitude_deg"]), 4)
        except (KeyError, TypeError, ValueError):
            continue

        if iata in METRO_CITY_OVERRIDES:
            city = METRO_CITY_OVERRIDES[iata]
        else:
            base_city = clean_city(row.get("municipality") or "")
            if territory_suffix:
                if not base_city or territory_suffix.lower() in base_city.lower():
                    city = territory_suffix
                else:
                    city = f"{base_city}, {territory_suffix}"
            else:
                city = base_city

        scheduled = 1 if (row.get("scheduled_service") or "").strip().lower() == "yes" else 0
        rank = (scheduled, AIRPORT_TYPE_PRIORITY[airport_type])
        record: list[object] = [iso3, city, lat, lon]

        existing = best_by_iata.get(iata)
        if existing is None or rank > existing[0]:
            best_by_iata[iata] = (rank, record)

    catalog = {iata: entry[1] for iata, entry in best_by_iata.items()}
    for iata, fallback in HISTORICAL_FALLBACKS.items():
        catalog.setdefault(iata, fallback)

    return dict(sorted(catalog.items()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--csv",
        type=Path,
        default=None,
        help="Optional local OurAirports airports.csv path (downloads upstream if omitted).",
    )
    parser.add_argument(
        "--countries",
        type=Path,
        default=DEFAULT_COUNTRIES_PATH,
        help="Path to countries.json.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_PATH,
        help="Destination path for airports_iata.json.",
    )
    args = parser.parse_args()

    iso2_to_iso3 = load_iso2_to_iso3(args.countries)
    csv_text = read_ourairports_csv(args.csv)
    catalog = build_airport_catalog(csv_text, iso2_to_iso3)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))
    args.output.write_text(serialized + "\n", encoding="utf-8")
    print(f"Wrote {len(catalog)} airports to {args.output} ({len(serialized) / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
