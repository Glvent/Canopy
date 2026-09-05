## Native port of unicode-width 0.2.2's non-CJK reverse string state machine.
## Copyright Rust Project Developers; MIT or Apache-2.0. See licenses/unicode/.
import ./[props, widthinfo]

const ligatureMask = 0x2000

proc withSelector(info, selector: int): int =
  if (info and ligatureMask) != 0 or
      (selector == wiVARIATION_SELECTOR_16 and (info and 0x9000) == 0x1000):
    # Preserve upstream operator precedence: existing state bits are retained.
    info or selector
  else: selector

# Width of one rune given `next`, the state carried back from the rune that follows it. Negative
# widths correct the width already charged to that following rune.

proc widthInString(r: DecodedRune, next: int): tuple[width, info: int] =
  let c = r.code
  let p = r.property
  var n = next
  if (n and wiVARIATION_SELECTOR_16) != 0:
    if (p.flags and 1) != 0:
      return ((if (n and 0xB000) == 0x9000: 0 else: 2),
              wiEMOJI_PRESENTATION)
    else:
      n = if (n and ligatureMask) != 0: n and not wiVARIATION_SELECTOR_16
          else: wiDEFAULT
  if c <= 0xA0:
    if c == 10: return (1, wiLINE_FEED)
    if c == 13 and n == wiLINE_FEED: return (0, wiDEFAULT)
    return (1, wiDEFAULT)
  if n != wiDEFAULT:
    if c == 0xFE0F: return (0, withSelector(n, wiVARIATION_SELECTOR_16))
    if c == 0xFE01: return (0, withSelector(n, wiVARIATION_SELECTOR_1_2_OR_3))
    if c == 0xFE0E: return (0, withSelector(n, wiVARIATION_SELECTOR_15))
    if (n and wiVARIATION_SELECTOR_15) != 0:
      if (p.flags and 2) != 0: return (1, wiDEFAULT)
      n = n and not wiVARIATION_SELECTOR_15
    elif (n and wiVARIATION_SELECTOR_1_2_OR_3) != 0:
      if c in [0x2018, 0x2019, 0x201C, 0x201D]: return (2, wiDEFAULT)
      n = n and not wiVARIATION_SELECTOR_1_2_OR_3
    if (n and 0x0800) != 0:
      if c == 0x200D: return (0, n or 0x0400)
      if (p.flags and 16) != 0: return (0, n)
    case n
    of wiJOINING_GROUP_ALEF:
      if c in [0x644, 0x76A, 0x8A6, 0x8C7] or c in 0x6B5..0x6B8:
        return (0, wiDEFAULT)
      if (p.flags and 8) != 0: return (0, wiJOINING_GROUP_ALEF)
    of wiZWJ_HEBREW_LETTER_LAMED:
      if c == 0x5D0: return (0, wiDEFAULT)
    of wiKHMER_COENG_ELIGIBLE_LETTER:
      if c == 0x17D2: return (-1, wiDEFAULT)
    of wiZWJ_BUGINESE_LETTER_YA:
      if c == 0x1A17: return (0, wiBUGINESE_VOWEL_SIGN_I_ZWJ_LETTER_YA)
    of wiBUGINESE_VOWEL_SIGN_I_ZWJ_LETTER_YA:
      if c == 0x1A15: return (0, wiDEFAULT)
    of wiTIFINAGH_CONSONANT, wiZWJ_TIFINAGH_CONSONANT:
      if c == 0x2D7F: return (1, wiTIFINAGH_JOINER_CONSONANT)
      if n == wiZWJ_TIFINAGH_CONSONANT and (c in 0x2D31..0x2D65 or c == 0x2D6F):
        return (0, wiDEFAULT)
    of wiTIFINAGH_JOINER_CONSONANT:
      if c in 0x2D31..0x2D65 or c == 0x2D6F: return (-1, wiDEFAULT)
    of wiLISU_TONE_LETTER_MYA_NA_JEU:
      if c in 0xA4F8..0xA4FB: return (0, wiDEFAULT)
    of wiZWJ_OLD_TURKIC_LETTER_ORKHON_I:
      if c == 0x10C32: return (0, wiDEFAULT)
    of wiEMOJI_MODIFIER:
      if (p.flags and 4) != 0: return (0, wiEMOJI_PRESENTATION)
      if c == 0x200D: return (0, wiZWJ_EMOJI_PRESENTATION)
    of wiREGIONAL_INDICATOR, wiSEVERAL_REGIONAL_INDICATOR:
      if c in 0x1F1E6..0x1F1FF: return (1, wiSEVERAL_REGIONAL_INDICATOR)
      if n == wiSEVERAL_REGIONAL_INDICATOR and c == 0x200D:
        return (0, wiZWJ_EMOJI_PRESENTATION)
    of wiEMOJI_PRESENTATION:
      if c == 0x200D: return (0, wiZWJ_EMOJI_PRESENTATION)
    of wiZWJ_EMOJI_PRESENTATION:
      if c == 0x20E3: return (0, wiKEYCAP_ZWJ_EMOJI_PRESENTATION)
      if c in 0x1F1E6..0x1F1FF: return (1, wiREGIONAL_INDICATOR_ZWJ_PRESENTATION)
      if c in 0x1F3FB..0x1F3FF: return (0, wiEMOJI_MODIFIER)
      if c == 0xE007F: return (0, wiTAG_END_ZWJ_EMOJI_PRESENTATION)
      if p.info == wiEMOJI_PRESENTATION: return (0, wiEMOJI_PRESENTATION)
    of wiVS16_ZWJ_EMOJI_PRESENTATION:
      if (p.flags and 1) != 0: return (0, wiEMOJI_PRESENTATION)
    of wiVS16_KEYCAP_ZWJ_EMOJI_PRESENTATION:
      if c in 0x30..0x39 or c in [0x23, 0x2A]: return (0, wiEMOJI_PRESENTATION)
    of wiREGIONAL_INDICATOR_ZWJ_PRESENTATION, wiODD_REGIONAL_INDICATOR_ZWJ_PRESENTATION:
      if c in 0x1F1E6..0x1F1FF: return (-1, wiEVEN_REGIONAL_INDICATOR_ZWJ_PRESENTATION)
      if n == wiODD_REGIONAL_INDICATOR_ZWJ_PRESENTATION and c == 0x200D:
        return (0, wiZWJ_EMOJI_PRESENTATION)
    of wiEVEN_REGIONAL_INDICATOR_ZWJ_PRESENTATION:
      if c in 0x1F1E6..0x1F1FF: return (3, wiODD_REGIONAL_INDICATOR_ZWJ_PRESENTATION)
      if c == 0x200D: return (0, wiZWJ_EMOJI_PRESENTATION)
    of wiTAG_END_ZWJ_EMOJI_PRESENTATION, wiTAG_A1_END_ZWJ_EMOJI_PRESENTATION,
        wiTAG_A2_END_ZWJ_EMOJI_PRESENTATION, wiTAG_A3_END_ZWJ_EMOJI_PRESENTATION,
        wiTAG_A4_END_ZWJ_EMOJI_PRESENTATION, wiTAG_A5_END_ZWJ_EMOJI_PRESENTATION,
        wiTAG_A6_END_ZWJ_EMOJI_PRESENTATION:
      if c in 0xE0061..0xE007A:
        if n == wiTAG_END_ZWJ_EMOJI_PRESENTATION:
          return (0, wiTAG_A1_END_ZWJ_EMOJI_PRESENTATION)
        if n < wiTAG_A6_END_ZWJ_EMOJI_PRESENTATION: return (0, n+1)
      if c in 0xE0030..0xE0039 and n <= wiTAG_A4_END_ZWJ_EMOJI_PRESENTATION:
        return (0, wiTAG_D1_END_ZWJ_EMOJI_PRESENTATION)
      if c == 0x1F3F4 and n >= wiTAG_A3_END_ZWJ_EMOJI_PRESENTATION:
        return (0, wiEMOJI_PRESENTATION)
    of wiTAG_D1_END_ZWJ_EMOJI_PRESENTATION, wiTAG_D2_END_ZWJ_EMOJI_PRESENTATION:
      if c in 0xE0030..0xE0039: return (0, n+1)
    of wiTAG_D3_END_ZWJ_EMOJI_PRESENTATION:
      if c == 0x1F3F4: return (0, wiEMOJI_PRESENTATION)
    of wiKIRAT_RAI_VOWEL_SIGN_E:
      if c in [0x16D63, 0x16D69]: return (0, wiDEFAULT)
      if c == 0x16D67: return (0, wiKIRAT_RAI_VOWEL_SIGN_AI)
      if c == 0x16D68: return (1, wiKIRAT_RAI_VOWEL_SIGN_E)
    of wiKIRAT_RAI_VOWEL_SIGN_AI:
      if c == 0x16D63: return (0, wiDEFAULT)
    else: discard
  (p.width, p.info)

proc stringWidth*(s: string): int =
  ## Iterates in reverse because a rune's width can depend on what follows it, such as a variation
  ## selector or a ZWJ sequence.
  let runes = decode(s)
  var info = wiDEFAULT
  for i in countdown(runes.high, 0):
    let step = widthInString(runes[i], info)
    result += step.width
    info = step.info
