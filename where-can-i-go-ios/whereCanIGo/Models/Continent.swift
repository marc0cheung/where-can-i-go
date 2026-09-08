import Foundation

/// Coarse continent grouping used only for the travel-summary "continents" stat.
enum Continent: String, CaseIterable {
    case africa        = "Africa"
    case asia          = "Asia"
    case europe        = "Europe"
    case northAmerica  = "North America"
    case southAmerica  = "South America"
    case oceania       = "Oceania"

    /// Continent for an ISO3 country code, if known.
    static func of(_ iso3: String) -> Continent? {
        lookup[iso3.uppercased()]
    }

    private static let lookup: [String: Continent] = {
        var map: [String: Continent] = [:]
        func add(_ continent: Continent, _ codes: [String]) {
            for code in codes { map[code] = continent }
        }

        add(.africa, ["DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD","COM","COG","COD","DJI","EGY","GNQ","ERI","SWZ","ETH","GAB","GMB","GHA","GIN","GNB","CIV","KEN","LSO","LBR","LBY","MDG","MWI","MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP","SEN","SYC","SLE","SOM","ZAF","SSD","SDN","TZA","TGO","TUN","UGA","ZMB","ZWE"])

        add(.asia, ["AFG","ARM","AZE","BHR","BGD","BTN","BRN","KHM","CHN","CYP","GEO","IND","IDN","IRN","IRQ","ISR","JPN","JOR","KAZ","KWT","KGZ","LAO","LBN","MYS","MDV","MNG","MMR","NPL","PRK","OMN","PAK","PSE","PHL","QAT","SAU","SGP","KOR","LKA","SYR","TWN","TJK","THA","TLS","TUR","TKM","ARE","UZB","VNM","YEM"])

        add(.europe, ["ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA","XKX","LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD","NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP","SWE","CHE","UKR","GBR","VAT"])

        add(.northAmerica, ["ATG","BHS","BRB","BLZ","CAN","CRI","CUB","DMA","DOM","SLV","GRD","GTM","HTI","HND","JAM","MEX","NIC","PAN","KNA","LCA","VCT","TTO","USA"])

        add(.southAmerica, ["ARG","BOL","BRA","CHL","COL","ECU","GUY","PRY","PER","SUR","URY","VEN"])

        add(.oceania, ["AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM","SLB","TON","TUV","VUT"])

        return map
    }()
}
