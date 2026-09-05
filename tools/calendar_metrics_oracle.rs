use ratatui::{widgets::{Block,Borders,Padding,TitlePosition,calendar::{Monthly,CalendarEventStore}},style::Style};
use time::{Date,Month};
fn main(){
 for i in 0..384usize{
  let (year,month)=[(2015,2),(2024,2),(2024,6)][i%3];let mask=(i/3)%16;let headers=(i/11)%4;let titles=(i/7)%6;
  let pads=[(0,0,0,0),(1,2,3,4),(0,0,101,207),(300,400,500,600),(65535,0,0,65535),(32768,32768,32768,32768),(65535,65535,65535,65535),(0,65514,65528,0)][(i/13)%8];
  let mut borders=Borders::NONE;for(j,b)in [Borders::TOP,Borders::RIGHT,Borders::BOTTOM,Borders::LEFT].iter().enumerate(){if mask&(1<<j)!=0{borders|=*b;}}
  let mut block=Block::new().borders(borders).padding(Padding::new(pads.0,pads.1,pads.2,pads.3));
  block=match titles{1=>block.title(""),2=>block.title_bottom(""),3=>block.title_top("top").title_bottom("bottom"),4=>block.title("implicit").title_position(TitlePosition::Bottom),5=>block.title_top("explicit").title("implicit").title_position(TitlePosition::Bottom),_=>block};
  let mut widget=Monthly::new(Date::from_calendar_date(year,Month::try_from(month).unwrap(),1).unwrap(),CalendarEventStore::default());
  if headers&1!=0{widget=widget.show_month_header(Style::new())}if headers&2!=0{widget=widget.show_weekdays_header(Style::new())}
  if i%29!=0{widget=widget.block(block)}
  println!("    [{},{},{},{},{},{},{},{},{},{},{},{}],",year,month,mask,headers,titles,pads.0,pads.1,pads.2,pads.3,(i%29!=0) as u8,widget.width(),widget.height());
 }
}
