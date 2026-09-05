## Compile against an installed package with repository config disabled.
import canopy
import canopy/input
import canopy/animation
doAssert displayWidth("👩‍🔬界") == 4
doAssert colorFromU32(0x123456'u32) == rgbColor(18,52,86)
var parser = initInputParser()
parser.feed("q")
doAssert parser.nextEvent().get.key.text == "q"
let animator = initAnimator()
let tween = initTween(0,10,initDuration(milliseconds=100))
let now = getMonoTime()
animator.play(tween)
discard animator.advance(now)
discard animator.advance(now+initDuration(milliseconds=50))
doAssert tween.value == 5
withTerminal(terminal,initTestBackend(20,3)):
  let frame = terminal.draw(proc(frame:var Frame) =
    frame.renderWidget(initParagraph("Installed package").withBlock(borderedBlock()),frame.area))
  doAssert frame.buffer[0,0].symbol == "┌"
echo "Installed package imports, animates and renders successfully"
