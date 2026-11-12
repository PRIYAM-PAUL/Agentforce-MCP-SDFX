/**
 * Fonada MCP - phone helpers shared by the CRM agent actions.
 * Fonada dials domestic numbers as digits only with the country code
 * (e.g. 919310997248 for India) and international numbers as +<digits>.
 * The domestic country code comes from Fonada Settings (default 91).
 */
public with sharing class FonadaPhone {

    /** Normalises a CRM phone value to Fonada's dial format (org country code); null when unusable. */
    public static String toDialNumber(String raw) {
        return toDialNumber(raw, FonadaSettings.countryCode());
    }

    /** Same, with an explicit domestic country code (digits only, e.g. '91' or '1'). */
    public static String toDialNumber(String raw, String countryCode) {
        if (String.isBlank(raw)) return null;
        String cc = String.isBlank(countryCode) ? FonadaSettings.DEFAULT_COUNTRY_CODE : countryCode;
        String trimmed = raw.trim();
        String digits = trimmed.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) return null;

        if (trimmed.startsWith('+') && !digits.startsWith(cc)) {
            return '+' + digits;                 // international: keep the +
        }
        if (digits.startsWith('00')) {
            digits = digits.substring(2);        // 00 international prefix
            if (!digits.startsWith(cc)) return '+' + digits;
        }
        while (digits.startsWith('0')) digits = digits.substring(1);   // trunk 0
        if (digits.length() == 10) return cc + digits;
        if (digits.length() == cc.length() + 10 && digits.startsWith(cc)) return digits;
        return digits.length() >= 8 ? digits : null;
    }

    /** First usable number from the given candidates (e.g. Phone, MobilePhone). */
    public static String firstDialNumber(List<String> candidates) {
        String cc = FonadaSettings.countryCode();
        for (String c : candidates) {
            String n = toDialNumber(c, cc);
            if (n != null) return n;
        }
        return null;
    }
}
