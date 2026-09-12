import { describe, expect, it } from "vitest";
import { currencyMinorUnitExponent, formatMinorUnits } from "./money";

describe("bounded demo money policy", () => {
  it.each([
    ["USD", 2],
    ["EUR", 2],
    ["JPY", 0],
    ["KWD", 3],
  ] as const)("defines %s with exponent %s", (currency, exponent) => {
    expect(currencyMinorUnitExponent(currency)).toBe(exponent);
  });

  it.each(["ZZZ", "usd", "US", "USDD"])("does not infer support for %s from Intl fallback behavior", (currency) => {
    expect(currencyMinorUnitExponent(currency)).toBeNull();
  });

  it("formats the maximum accepted safe-integer amount without dropping its last minor unit", () => {
    const rendered = formatMinorUnits(Number.MAX_SAFE_INTEGER, "USD", 2);

    expect(rendered).toMatch(/409,91/);
    expect(rendered).not.toMatch(/409,90/);
  });
});
