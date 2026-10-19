//! Development-only oracle, pinned Ratatui 0.30.2.
use ratatui::{buffer::Buffer, layout::{Rect,Alignment,Offset}, style::{Color,Style,Modifier}, text::{Line,Span}, widgets::{Block,Borders,BorderType,Widget,Padding,TitlePosition as Position,Shadow,dimmed}, symbols::merge::MergeStrategy};
use serde_json::{json,Value};
mod block_symbol_catalog;
fn color(c:Color)->Value {match c {Color::Rgb(r,g,b)=>json!(["Rgb",r,g,b]),_=>json!([format!("{c:?}")])}}
fn capture(b:&Buffer)->Value {json!(b.content.iter().map(|c|json!([c.symbol(),color(c.fg),color(c.bg),color(c.underline_color),c.modifier.bits()])).collect::<Vec<_>>())}
fn kind(i:usize)->BorderType {[BorderType::Plain,BorderType::Rounded,BorderType::Double,BorderType::Thick,BorderType::QuadrantInside,BorderType::QuadrantOutside,BorderType::Plain,BorderType::LightDoubleDashed,BorderType::HeavyDoubleDashed,BorderType::LightTripleDashed,BorderType::HeavyTripleDashed,BorderType::LightQuadrupleDashed,BorderType::HeavyQuadrupleDashed][i]}
fn strategy(i:usize)->MergeStrategy {[MergeStrategy::Replace,MergeStrategy::Exact,MergeStrategy::Fuzzy][i]}
fn align(i:usize)->Alignment {[Alignment::Left,Alignment::Center,Alignment::Right][i]}
fn borders(mask:usize)->Borders {let mut b=Borders::NONE;for(i,v)in [Borders::TOP,Borders::RIGHT,Borders::BOTTOM,Borders::LEFT].iter().enumerate(){if mask&(1<<i)!=0{b|=*v}}b}
fn main(){
 let symbols=(0x2500..=0x257f).map(|c|char::from_u32(c).unwrap().to_string()).chain([" ","x","界","──",""] .map(str::to_string)).collect::<Vec<_>>();
 let mut merges=Vec::new();for s in 0..3{for a in &symbols{for b in &symbols{merges.push(strategy(s).merge(a,b).to_string());}}}
 let mut cases=Vec::new();
 for k in 0..13{for mask in 0..16{for merge in 0..3{for size in 0..6{
  let (w,h)=[(0,0),(1,1),(1,3),(3,1),(2,2),(5,4)][size];let area=Rect::new(1,1,w,h);let mut buf=Buffer::empty(Rect::new(0,0,7,6));
  let fill=(k+mask+size)%5;for(i,c)in buf.content.iter_mut().enumerate(){match fill{0=>(),1=>{c.set_symbol(" ");},2=>{c.set_symbol("x");},3=>{c.set_symbol("╋");},_=>{c.set_symbol(["─","║","╭","┇"][i%4]);}}}
  let mut widget=Block::new().borders(borders(mask)).border_type(kind(k)).merge_borders(strategy(merge)).style(Style::new().fg(Color::Red)).border_style(Style::new().bg(Color::Blue));
  if k==6 {widget=widget.border_set(ratatui::symbols::border::FULL);}
  widget.render(area,&mut buf);cases.push(json!({"type":"border","k":k,"mask":mask,"merge":merge,"size":size,"fill":fill,"cells":capture(&buf)}));
 }}}}
 for i in 0..864usize{
  let w=(i%12)as u16;let h=((i/12)%3)as u16;let mask=(i/3)%16;let a=(i/7)%3;let p=(i/11)%2;let content=(i/13)%4;
  let area=Rect::new(1,1,w,h);let mut buf=Buffer::empty(Rect::new(0,0,14,5));for c in &mut buf.content{c.set_symbol(".");}
  let values=[["a","b","c"],["one long","界e\u{301}","tail"],["界界界","👩‍🔬x","a"],["","x",""]][content];
  let mut widget=Block::new().borders(borders(mask)).title_alignment(align(a)).title_position(if p==0{Position::Top}else{Position::Bottom}).style(Style::new().fg(Color::Red)).title_style(Style::new().bg(Color::Blue));
  for(j,v)in values.iter().enumerate(){let mut line=Line::from(vec![Span::styled(*v,Style::new().fg(Color::Yellow))]);if i%2==0{line=line.alignment(align(j));}widget=if j==1&&i%3==0{widget.title_bottom(line)}else if j==2&&i%5==0{widget.title_top(line)}else{widget.title(line)};}
  let inner=widget.inner(area);widget.render(area,&mut buf);cases.push(json!({"type":"title","i":i,"cells":capture(&buf),"inner":[inner.x,inner.y,inner.width,inner.height]}));
 }
 for i in 0..336usize{
  let effect=i%7;let (dx,dy)=[(1,1),(-1,-1),(2,0),(0,-2),(0,0),(20,20),(-20,-20)][(i/7)%7];let rgb=i%2==0;let styled=i%3==0;let standalone=i%5==0;
  let mut buf=Buffer::empty(Rect::new(0,0,8,7));for c in &mut buf.content{c.set_symbol(".").set_bg(if rgb{Color::Rgb(101,202,255)}else{Color::Green});}
  let area=if i%11==0{Rect::new(6,5,4,4)}else{Rect::new(1,1,4,3)};
  let mut shadow=match effect{0=>Shadow::overlay(),1=>Shadow::block(),2=>Shadow::light_shade(),3=>Shadow::medium_shade(),4=>Shadow::dark_shade(),5=>Shadow::symbol("界"),_=>Shadow::custom(dimmed())}.offset(Offset{x:dx,y:dy});
  if styled{shadow=shadow.style(Style::new().fg(Color::Yellow).bg(Color::Rgb(201,101,51)).add_modifier(Modifier::ITALIC));}
  if standalone{shadow.render(area,&mut buf)}else{Block::bordered().shadow(shadow).render(area,&mut buf)}
  cases.push(json!({"type":"shadow","i":i,"cells":capture(&buf)}));
 }
 println!("{}",json!({"ratatui":"0.30.2","catalog":block_symbol_catalog::catalog(),"symbols":symbols,"merges":merges,"cases":cases}));
}
