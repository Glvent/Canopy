## Exact overflow-free floor(value * scale / denominator), bounded to scale.
func scaleFraction*(value, denominator: uint64, scale: int): int =
  ## Ratio of `value` to `denominator` expressed in `scale` steps, exact for the full uint64 range.
  ## Returns 0 for a zero denominator or non-positive scale, and saturates at `scale`.
  if denominator == 0 or scale <= 0: return 0
  if value >= denominator: return scale
  # Binary long division without uint128 or platform-specific intrinsics.
  var remainder = 0'u64
  var quotient = 0
  for bit in countdown(62, 0):
    if (uint64(scale) shr bit) == 0 and quotient == 0 and remainder == 0: continue
    quotient *= 2
    if remainder >= denominator-remainder:
      remainder -= denominator-remainder
      inc quotient
    else: remainder *= 2
    if (uint64(scale) and (1'u64 shl bit)) != 0:
      if remainder >= denominator-value:
        remainder -= denominator-value
        inc quotient
      else: remainder += value
  quotient
