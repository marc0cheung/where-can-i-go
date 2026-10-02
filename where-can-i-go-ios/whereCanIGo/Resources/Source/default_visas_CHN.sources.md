# China Passport (CHN) Preset

Source summary recorded on 2026-10-02 for ordinary Chinese passports. 

## Sources

- [Henley Passport Index](https://www.henleyglobal.com/passport-index): starting destination list. 
- [Visa requirements for Chinese citizens](https://en.wikipedia.org/wiki/Visa_requirements_for_Chinese_citizens): ordinary-passport and territory policy tables, entry categories, stay limits, and conditions. The reference article is available under CC BY-SA 4.0.
- [Singapore Immigration & Checkpoints Authority](https://www.ica.gov.sg/news-and-publications/newsroom/media-release/mutual-30-day-visa-exemption-arrangement-between-singapore-and-the-people-s-republic-of-china): mutual 30-day visa exemption.
- [Azerbaijan Ministry of Foreign Affairs](https://mfa.gov.az/en/category/visa/visa-free-countries): visa-free eligibility and stay limits.
- [Philippine Embassy in Beijing](https://beijingpe.dfa.gov.ph/announcements/1388-philippines-to-allow-visa-free-entry-for-14-days-for-chinese-nationals): announcement of 14-day visa-free entry; consult the notice for eligibility and entry conditions.
- [US Customs and Border Protection](https://www.cbp.gov/travel/international-visitors/guam-cnmi-visa-waiver-program): Guam-CNMI travel rules. The preset's Northern Mariana Islands entry is CNMI-specific, not a general US or Guam exemption; confirm current pre-travel requirements.
- [Djibouti eVisa](https://www.evisa.gouv.dj/), [Guinea visa information](https://www.paf.gov.gn/visa), and [Guyana visitor visa services](https://eservices.iss.gov.gy/visitor-visa): references consulted for advance visa applications rather than unconditional visa-free access.

## Representation and Limits

- eVisas requiring an application remain `visa_required`, with an eVisa note in `duration`. This includes Djibouti, Guinea, and Guyana.
- Visa-free entry, visa on arrival, and ETA are separate app categories. Additional registrations and entry conditions may still apply; the app does not enforce eligibility or application requirements.
- Duration remarks are concise and have been manually simplified. They do not include every supporting-document requirement, temporary-policy expiry, purpose restriction, or permitted entry route. Unknown stay limits remain `varies`.
- The preset is a manually maintained planning aid, not live immigration advice, a complete checklist, or a guarantee of entry. Reconfirm current rules with destination authorities and the airline before travel, especially for temporary exemptions and territory-specific arrangements.