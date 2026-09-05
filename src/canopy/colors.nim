## Native Ratatui palette color conversions (palette 0.7.7, MIT/Apache-2.0).
## Inputs use float32 like palette's default Hsl/Hsluv types. Arithmetic order,
## clamping, hue normalization and ties-to-even bytes follow the pinned source.
## Attribution and numerical coverage: tools/colors_README.md.
import std/math
import ./style
export style

func colorFromU32*(value:uint32):Color =
  rgbColor(int((value shr 16) and 255),int((value shr 8) and 255),int(value and 255))

func bounded(value,maximum:float32):float32 =
  if value<0:0'f32
  elif value>maximum:maximum
  else:value # Rust clamp preserves NaN.
func stimulus(value:float32):int =
  let value=bounded(value,1)
  let scaled=value*255'f32
  let limited=if scaled!=scaled:255'f32 else:min(scaled,255'f32)
  let bits=cast[uint32](limited+8388608'f32)
  int(if bits<0x4b000000'u32:0'u32 else:(bits-0x4b000000'u32) and 255)
func colorFromHsl*(hue,saturation,lightness:float32):Color =
  ## Hue is degrees (wrapped); saturation/lightness are clamped to 0..1.
  let s=bounded(saturation,1)
  let l=bounded(lightness,1)
  let c=(1'f32-abs(l*2'f32-1'f32))*s
  var degrees=hue-floor(hue/360'f32)*360'f32
  if (degrees!=0 and abs(degrees)<1.1754943508222875e-38'f32) or degrees>=360:degrees=0
  let h=degrees/60'f32
  let hmod=h-floor(h*0.5'f32)*2'f32
  let x=c*(1'f32-abs(hmod-1'f32))
  let m=l-c*0.5'f32
  let z0=h>=0 and h<1
  let z1=h>=1 and h<2
  let z2=h>=2 and h<3
  let z3=h>=3 and h<4
  let z4=h>=4 and h<5
  let r=if z1 or z4:x elif z2 or z3:0'f32 else:c
  let g=if z0 or z3:x elif z1 or z2:c else:0'f32
  let b=if z0 or z1:0'f32 elif z3 or z4:c else:x
  rgbColor(stimulus(r+m),stimulus(g+m),stimulus(b+m))

func cube[T:SomeFloat](value:T):T = value*value*value
func maxChroma(l,hue:float32):float32 =
  const matrix=[
    [3.240969941904521,-1.537383177570093,-0.498610760293],
    [-0.96924363628087,1.87596750150772,0.041555057407175],
    [0.055630079696993,-0.20397695888897,1.056971514242878]]
  let lightness=float64(l)
  let sub1=cube(lightness+16.0)/1560896.0
  let sub2=if sub1>0.0088564516:sub1 else:lightness/903.2962962
  let angle=float64(hue*(PI.float32/180'f32))
  let sn=sin(angle)
  let cs=cos(angle)
  var minimum=1.7976931348623157e308
  for row in matrix:
    for ti in 0..1:
      let t=float64(ti)
      let top1=(284517.0*row[0]-94839.0*row[2])*sub2
      let top2=(838422.0*row[2]+769860.0*row[1]+731718.0*row[0])*lightness*sub2-769860.0*t*lightness
      let bottom=(632260.0*row[2]-126452.0*row[1])*sub2+126452.0*t
      let slope=top1/bottom
      let intercept=top2/bottom
      let denominator=sn-slope*cs
      if abs(denominator)>1.0e-6:
        let distance=intercept/denominator
        if distance>=0 and minimum>distance:minimum=distance
  float32(minimum)
func encoded(value:float32):float32 =
  if value<=0.0031308'f32:12.92'f32*value
  else:pow(value,float32(1.0/2.4))*1.055'f32-0.055'f32
func colorFromHsluv*(hue,saturation,lightness:float32):Color =
  ## Hue is degrees; saturation/lightness are clamped to 0..100.
  let s=bounded(saturation,100)
  let l=bounded(lightness,100)
  let chroma=s*maxChroma(l,hue)*0.01'f32
  let nonnegative=if chroma!=chroma or chroma<0:0'f32 else:chroma
  let angle=hue*(PI.float32/180'f32)
  let u=nonnegative*cos(angle)
  let v=nonnegative*sin(angle)
  if l<1e-5'f32:return rgbColor(0,0,0)
  let reciprocal=1'f32/(0.95047'f32+15'f32*1'f32+3'f32*1.08883'f32)
  let uref=4'f32*0.95047'f32*reciprocal
  let vref=9'f32*1'f32*reciprocal
  let y=if l>8'f32:cube((l+16'f32)*(1'f32/116'f32)) else:l*(1'f32/cube(float32(29.0/3.0)))
  let up=u/(13'f32*l)+uref
  let vp=v/(13'f32*l)+vref
  let x=y*2.25'f32*up/vp
  let z=y*(3'f32-0.75'f32*up-5'f32*vp)/vp
  let r=3.2404542'f32*x + -1.5371385'f32*y + -0.4985314'f32*z
  let g= -0.9692660'f32*x + 1.8760108'f32*y + 0.0415560'f32*z
  let b=0.0556434'f32*x + -0.2040259'f32*y + 1.0572252'f32*z
  rgbColor(stimulus(encoded(r)),stimulus(encoded(g)),stimulus(encoded(b)))
