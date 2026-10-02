# Taiwan Passport Preset

Policy snapshot researched on 2026-10-02 for ordinary Taiwan passports with a national ID number (household registration). This preset does not represent passports without a national ID number, diplomatic passports, or official passports. The national ID requirement applies throughout the preset and is not repeated in the concise duration remarks.

The data uses the existing `DefaultVisaEntry` fields and categories. Taiwan is the home entry. Destinations outside the preset default to `visa_required`; this does not imply that an ordinary visa is always obtainable. The preset covers destinations in the app's current country catalog, not every territory in the Henley index, and should not be compared directly with Henley's total.

## Sources

- [Visa requirements for Taiwanese citizens](https://en.wikipedia.org/wiki/Visa_requirements_for_Taiwanese_citizens): ordinary-passport and territory policy tables, stay limits, national ID requirements, and special travel documents. The reference article is available under CC BY-SA 4.0; entries here record policy facts rather than copied explanatory prose.
- [UK ETA eligibility](https://www.gov.uk/guidance/check-when-you-can-get-an-electronic-travel-authorisation-eta): Taiwan passports must contain the national ID number; visits up to six months.
- [Canada entry requirements](https://www.canada.ca/en/immigration-refugees-citizenship/services/visit-canada/entry-requirements-country.html): air travel requires an eTA for eligible visa-exempt travelers; land and sea entry generally do not.
- [Hong Kong pre-arrival registration](https://www.immd.gov.hk/eng/services/visas/pre-arrival_registration_for_taiwan_residents.html): separate registration scheme for eligible Taiwan residents, represented by the app's `eta` category.
- [Macao immigration clearance](https://www.gov.mo/en/services/ps-1474/ps-1474b/): travel-document and authorization-to-stay rules. The Taiwan-specific 30-day stay is recorded in the reference policy table.
- [Taipei Economic and Cultural Center in Chennai](https://www.roc-taiwan.org/inmaa/post/13786.html): 2026-06-25 notice explaining Sri Lanka's suspension of visa on arrival for Taiwan travelers, sponsored advance visa application, and Landing Endorsement requirement.
- [Philippines exemption extension](https://www.taiwannews.com.tw/news/6392900): reports MECO's extension of 14-day tourist entry through 2027-06-30; stays cannot be extended or converted.
- [Saudi official eVisa portal](https://visa.visitsaudi.com/): Taiwan is not explicitly included in the ordinary eVisa nationality list. The preset conservatively retains `visa_required`; conditional visa on arrival is noted from the reference table rather than presented as general eligibility.
- [K-ETA notices](https://www.k-eta.go.kr/portal/board/viewboardlist.do?tmpltNm=notice): extension notice dated 2025-12-23. The reference table records the Taiwan exemption through 2026-12-31.

## Representation and Limits

- eVisas and online visa applications remain `visa_required`, with an eVisa or online-visa note in `duration`.
- Where both an eVisa and ordinary visa on arrival are listed, the preset uses `visa_on_arrival`. Saudi Arabia is an exception because access depends on additional qualifying visas.
- Mainland China requires a Mainland Travel Permit for Taiwan Residents or a Chinese Travel Document; it is not unconditional passport-only visa-free entry. Argentina, Jamaica, and Serbia also have special-document requirements.
- Georgia, Kiribati, Moldova, and Venezuela are recorded as `visa_required` with admission-refusal notes because the app has no separate admission-refused category.
- Schengen's 90 days within 180 days is a shared regional allowance, not a fresh allowance in each country.
- The Guam-CNMI 45-day waiver also requires a Taiwan national ID card, prior authorization, and a direct Taiwan flight. The card requirement is documented here rather than repeated in the duration remark; the separate 90-day ESTA route has its own eligibility rules.
- Unknown stay limits remain `varies`. Ordinary visa-required destinations with no additional policy information are omitted and use the existing fallback.
- Temporary exemptions and passport requirements are notes, not rules enforced by the app. Reconfirm destination and airline requirements before travel. This snapshot is for personal planning, not a guarantee of entry or a complete checklist of conditions.