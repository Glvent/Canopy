//! Palette-enabled, development-only oracle for native color conversions.
use palette::{Hsl,Hsluv};
use ratatui_core::style::Color;
use serde_json::{json,Value};
fn sample(cases:&mut Vec<Value>,kind:usize,h:f32,s:f32,l:f32){
 let color=if kind==0{Color::from_hsl(Hsl::new(h,s,l))}else{Color::from_hsluv(Hsluv::new(h,s,l))};
 let Color::Rgb(r,g,b)=color else{unreachable!()};
 cases.push(json!([kind,h.to_bits(),s.to_bits(),l.to_bits(),r,g,b]));
}
fn main(){let mut cases=Vec::new();
 for kind in 0..2{let max=if kind==0{1.0}else{100.0};
  for h in [-1080.0,-720.0,-361.0,-360.0,-180.0,-120.0,-94.13,-0.00001,0.0,12.18,59.99999,60.0,120.0,180.0,240.0,300.0,359.99997,360.0,720.0,100000000.0,f32::NAN,f32::INFINITY,f32::NEG_INFINITY]{
   for s in [-max,0.0,max*0.00000001,max*0.25,max*0.5,max*0.9999999,max,2.0*max,f32::NAN,f32::INFINITY,f32::NEG_INFINITY]{
    for l in [-max,0.0,max*0.00000001,max*0.08,max*0.25,max*0.5,max*0.9999999,max,2.0*max,f32::NAN,f32::INFINITY,f32::NEG_INFINITY]{sample(&mut cases,kind,h,s,l);}
   }
  }
  let mut seed=302u64;
  for _ in 0..12000{let mut next=||{seed=seed.wrapping_mul(6364136223846793005).wrapping_add(1);(seed>>32)as f32/(u32::MAX as f32)};
   let h=next()*2160.0-1080.0;let s=next()*max*1.2-max*0.1;let l=next()*max*1.2-max*0.1;sample(&mut cases,kind,h,s,l);
  }
  if kind==0{for byte in 0..255{let middle=(byte as f32+0.5)/255.0;for delta in -2i32..=2{let l=f32::from_bits((middle.to_bits()as i64+delta as i64)as u32);sample(&mut cases,kind,0.0,0.0,l);}}}
 }
 let packed=[0,1,0x123456,0xffabcdef,0xffffffff].map(|value|{let Color::Rgb(r,g,b)=Color::from_u32(value)else{unreachable!()};json!([value,r,g,b])});
 println!("{}",json!({"ratatuiCore":"0.1.2","palette":"0.7.7","cases":cases,"packed":packed}));
}
