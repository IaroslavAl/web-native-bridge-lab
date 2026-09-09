const MINOR_UNIT_EXPONENTS = {
  USD: 2,
  EUR: 2,
  JPY: 0,
  KWD: 3,
} as const;

export function currencyMinorUnitExponent(currency: string): number | null {
  if (!Object.prototype.hasOwnProperty.call(MINOR_UNIT_EXPONENTS, currency)) return null;
  return MINOR_UNIT_EXPONENTS[currency as keyof typeof MINOR_UNIT_EXPONENTS];
}

export function formatMinorUnits(totalMinor: number, currency: string, exponent: number): string {
  if (!Number.isSafeInteger(totalMinor) || totalMinor < 0) {
    throw new RangeError("totalMinor must be a nonnegative safe integer.");
  }
  if (currencyMinorUnitExponent(currency) !== exponent) {
    throw new RangeError("Currency and minor-unit exponent are not supported.");
  }

  const factor = 10 ** exponent;
  const major = Math.floor(totalMinor / factor);
  const fraction = String(totalMinor % factor).padStart(exponent, "0");
  const formatter = new Intl.NumberFormat("ru-RU", {
    style: "currency",
    currency,
    minimumFractionDigits: exponent,
    maximumFractionDigits: exponent,
  });

  return formatter.formatToParts(major)
    .map((part) => part.type === "fraction" ? fraction : part.value)
    .join("");
}
