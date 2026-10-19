use ratatui::{buffer::Buffer, layout::{Rect, Alignment, Constraint}, style::{Color,Style,Modifier},
  symbols::Marker, text::{Line,Span}, widgets::{Widget,Block,Borders,Chart,Dataset,Axis,GraphType,LegendPosition,
  canvas::{Canvas,Context,Painter,Shape,Line as CanvasLine,FilledLine,Rectangle,Circle,Points,Map,MapResolution}}};
use serde_json::{Value,json};
use std::io::{self,Read};

fn integer(v:&Value,key:&str,default:i64)->i64 {v[key].as_i64().unwrap_or(default)}
fn number(v:&Value,key:&str,default:f64)->f64 {v[key].as_f64().unwrap_or(default)}
fn string<'a>(v:&'a Value,key:&str,default:&'a str)->&'a str {v[key].as_str().unwrap_or(default)}
fn color(v:&Value)->Color {
  if let Some(s)=v.as_str() {return s.parse().unwrap()}
  if let Some(n)=v.as_u64() {return Color::Indexed(n as u8)}
  if let Some(a)=v.as_array() {return Color::Rgb(a[0].as_u64().unwrap() as u8,a[1].as_u64().unwrap() as u8,a[2].as_u64().unwrap() as u8)}
  Color::Reset
}
fn style(v:&Value)->Style {
  let mut s=if v["reset"].as_bool().unwrap_or(false) {Style::reset()} else {Style::default()};
  if !v["fg"].is_null() {s=s.fg(color(&v["fg"]))}
  if !v["bg"].is_null() {s=s.bg(color(&v["bg"]))}
  if !v["underlineColor"].is_null() {s=s.underline_color(color(&v["underlineColor"]))}
  s.add_modifier(Modifier::from_bits_truncate(integer(v,"add",0) as u16))
   .remove_modifier(Modifier::from_bits_truncate(integer(v,"remove",0) as u16))
}
fn alignment(s:&str)->Alignment {match s {"Center"=>Alignment::Center,"Right"=>Alignment::Right,_=>Alignment::Left}}
fn line(v:&Value)->Line<'static> {
  if let Some(s)=v.as_str() {return Line::from(s.to_owned())}
  let spans=v["spans"].as_array().map(|a| a.iter().map(|s| Span::styled(string(s,"text","").to_owned(),style(&s["style"]))).collect::<Vec<_>>()).unwrap_or_default();
  let mut l=Line::from(spans).style(style(&v["style"]));
  if let Some(a)=v["alignment"].as_str() {l=l.alignment(alignment(a))} l
}
fn marker(v:&Value)->Marker {match string(v,"marker","Braille") {
  "Dot"=>Marker::Dot,"Block"=>Marker::Block,"Bar"=>Marker::Bar,"HalfBlock"=>Marker::HalfBlock,
  "Quadrant"=>Marker::Quadrant,"Sextant"=>Marker::Sextant,"Octant"=>Marker::Octant,
  "Custom"=>Marker::Custom(string(v,"customSymbol","*").chars().next().unwrap()),_=>Marker::Braille}}
fn bounds(v:&Value)->[f64;2] {[v[0].as_f64().unwrap_or(0.0),v[1].as_f64().unwrap_or(0.0)]}
fn coords(v:&Value)->Vec<(f64,f64)> {v.as_array().map(|a| a.iter().map(|p|(p[0].as_f64().unwrap(),p[1].as_f64().unwrap())).collect()).unwrap_or_default()}
fn block(v:&Value)->Block<'static> {
  let mut b=Block::default().style(style(&v["style"])).border_style(style(&v["borderStyle"]));
  if v["bordered"].as_bool().unwrap_or(true) {b=b.borders(Borders::ALL)}
  if !v["title"].is_null() {b=b.title(line(&v["title"]))} b
}
struct Pixels {coords:Vec<(f64,f64)>,color:Color}
impl Shape for Pixels {fn draw(&self,p:&mut Painter) {for &(x,y) in &self.coords {p.paint(x as usize,y as usize,self.color)}}}
fn paint(ctx:&mut Context,actions:&Value) {
  for a in actions.as_array().unwrap() {
    let (x,y,x2,y2)=(number(a,"x",0.0),number(a,"y",0.0),number(a,"x2",0.0),number(a,"y2",0.0));
    let c=color(&a["color"]);
    match string(a,"kind","") {
      "line"=>ctx.draw(&CanvasLine::new(x,y,x2,y2,c)),
      "filledLine"=>ctx.draw(&FilledLine::new(x,y,x2,y2,number(a,"fillToY",0.0),c)),
      "rectangle"=>ctx.draw(&Rectangle::new(x,y,number(a,"width",0.0),number(a,"height",0.0),c)),
      "circle"=>ctx.draw(&Circle::new(x,y,number(a,"radius",0.0),c)),
      "points"=>ctx.draw(&Points::new(&coords(&a["coords"]),c)),
      "pixels"=>ctx.draw(&Pixels{coords:coords(&a["coords"]),color:c}),
      "map"=>ctx.draw(&Map{resolution:if string(a,"resolution","Low")=="High" {MapResolution::High} else {MapResolution::Low},color:c}),
      "print"=>ctx.print(x,y,line(&a["line"])),"layer"=>ctx.layer(),"marker"=>ctx.marker(marker(a)),
      other=>panic!("unknown action {other}")
    }
  }
}
fn constraint(v:&Value)->Constraint {let n=integer(v,"value",0) as u16;match string(v,"kind","ratio") {
  "length"=>Constraint::Length(n),"min"=>Constraint::Min(n),"max"=>Constraint::Max(n),"fill"=>Constraint::Fill(n),
  "percentage"=>Constraint::Percentage(n),_=>Constraint::Ratio(integer(v,"numerator",1) as u32,integer(v,"denominator",4) as u32)}}
fn axis(v:&Value)->Axis<'static> {
  let mut a=Axis::default().bounds(bounds(&v["bounds"])).style(style(&v["style"]))
    .labels_alignment(alignment(string(v,"alignment","Left")));
  if !v["title"].is_null() {a=a.title(line(&v["title"]))}
  if let Some(labels)=v["labels"].as_array() {a=a.labels(labels.iter().map(line))} a
}
fn encode_color(c:Color)->Value {match c {Color::Indexed(n)=>json!({"indexed":n}),Color::Rgb(r,g,b)=>json!({"rgb":[r,g,b]}),_=>json!(format!("{c:?}"))}}
fn render(v:&Value)->Value {
  let a=&v["area"];
  let area=Rect::new(integer(a,"x",0) as u16,integer(a,"y",0) as u16,integer(a,"width",0) as u16,integer(a,"height",0) as u16);
  let mut buf=Buffer::empty(area);
  for cell in &mut buf.content {cell.set_symbol(string(v,"initialSymbol"," ")).set_style(style(&v["initialStyle"]));}
  if string(v,"kind","canvas")=="canvas" {
    let mut c=Canvas::default().marker(marker(v)).x_bounds(bounds(&v["xBounds"])).y_bounds(bounds(&v["yBounds"]))
      .background_color(color(&v["backgroundColor"])).paint(|ctx|paint(ctx,&v["actions"]));
    if !v["block"].is_null() {c=c.block(block(&v["block"]))} c.render(area,&mut buf);
  } else {
    let ds=v["datasets"].as_array().unwrap();
    let data=ds.iter().map(|d|coords(&d["data"])).collect::<Vec<_>>();
    let datasets=ds.iter().zip(&data).map(|(d,data)| {
      let mut s=Dataset::default().data(data).marker(if d["marker"].is_null() {Marker::Dot} else {marker(d)}).style(style(&d["style"]))
        .graph_type(match string(d,"graphType","Scatter") {"Line"=>GraphType::Line,"Bar"=>GraphType::Bar,"Area"=>GraphType::Area,_=>GraphType::Scatter})
        .fill_to_y(number(d,"fillToY",0.0));
      if !d["name"].is_null() {s=s.name(line(&d["name"]))} s
    }).collect::<Vec<_>>();
    let mut c=Chart::new(datasets).x_axis(axis(&v["xAxis"])).y_axis(axis(&v["yAxis"])).style(style(&v["style"]));
    if !v["block"].is_null() {c=c.block(block(&v["block"]))}
    if let Some(h)=v["hiddenLegendConstraints"].as_array() {c=c.hidden_legend_constraints((constraint(&h[0]),constraint(&h[1])))}
    if let Some(position)=v.get("legendPosition") {
      c=c.legend_position(position.as_str().map(|p|match p {"Top"=>LegendPosition::Top,"TopLeft"=>LegendPosition::TopLeft,
        "Left"=>LegendPosition::Left,"Right"=>LegendPosition::Right,"Bottom"=>LegendPosition::Bottom,
        "BottomLeft"=>LegendPosition::BottomLeft,"BottomRight"=>LegendPosition::BottomRight,_=>LegendPosition::TopRight}));
    } c.render(area,&mut buf);
  }
  #[allow(deprecated)]
  let cells=buf.content.iter().map(|c|json!({"symbol":c.symbol(),"fg":encode_color(c.fg),"bg":encode_color(c.bg),
    "underlineColor":encode_color(c.underline_color),"modifiers":c.modifier.bits(),"skip":c.skip,"diffOption":format!("{:?}",c.diff_option)})).collect::<Vec<_>>();
  json!({"area":{"x":area.x,"y":area.y,"width":area.width,"height":area.height},"cells":cells})
}
fn main() {
  let mut input=String::new();io::stdin().read_to_string(&mut input).unwrap();
  let input:Value=serde_json::from_str(&input).unwrap();
  let cases=input.as_array().unwrap().iter().map(|v|json!({"name":v["name"],"input":v,"expected":render(v)})).collect::<Vec<_>>();
  println!("{}",json!({"schemaVersion":1,"ratatui":"0.30.2","ratatuiCore":"0.1.2","ratatuiWidgets":"0.3.2","cases":cases}));
}
