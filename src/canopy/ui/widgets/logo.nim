## Official Ratatui logo, retained for migration compatibility.
import ../../core/layout/geometry
import ../../core/rendering/buffer
import ../../core/text/index as text

type
  RatatuiLogoSize* {.pure.} = enum Tiny, Small
  RatatuiLogo* = object
    size*: RatatuiLogoSize

func initRatatuiLogo*(size = RatatuiLogoSize.Tiny): RatatuiLogo = RatatuiLogo(size: size)
func tinyLogo*(): RatatuiLogo = initRatatuiLogo()
func smallLogo*(): RatatuiLogo = initRatatuiLogo(RatatuiLogoSize.Small)
func withSize*(logo: RatatuiLogo, size: RatatuiLogoSize): RatatuiLogo = initRatatuiLogo(size)
proc render*(logo: RatatuiLogo, area: Rect, buf: var Buffer) =
  let content = if logo.size == RatatuiLogoSize.Tiny:
    "▛▚▗▀▖▜▘▞▚▝▛▐ ▌▌\n▛▚▐▀▌▐ ▛▜ ▌▝▄▘▌"
  else: "█▀▀▄ ▄▀▀▄▝▜▛▘▄▀▀▄▝▜▛▘█  █ █\n█▀▀▄ █▀▀█ ▐▌ █▀▀█ ▐▌ ▀▄▄▀ █"
  initText(content).render(area, buf)
